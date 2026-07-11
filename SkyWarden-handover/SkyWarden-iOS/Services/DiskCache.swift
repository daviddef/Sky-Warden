// Sky Warden — persistent response cache
//
// The aggregator's in-memory debounce only survives while the process does, so
// every cold launch re-hit every provider. For WorldTides — which bills per
// call — that meant a fresh paid request each launch, plus one on every forced
// refresh and every background wake, for data that changes on a 12-hour cycle.
//
// This caches responses on disk, keyed by a coarse location grid so that
// wandering around a suburb doesn't re-bill, with a TTL per data class:
//
//   tides       6 h   astronomical, published days ahead
//   archive    24 h   historical normals; the past does not change
//   news       30 m
//
// Cache lives in Caches/, so iOS may evict it under storage pressure — that is
// the correct trade for data we can always refetch.

import Foundation
import CoreLocation

enum DiskCache {

    /// Wrapper carrying the write time, so TTL is enforced on read.
    private struct Entry<T: Codable>: Codable {
        let storedAt: Date
        let value: T
    }

    /// Where a file lives, and therefore whether iOS may delete it.
    ///
    /// Cached API responses belong in Caches — evictable, and always refetchable.
    /// The forecast-skill ledger does not: it takes days of use to accumulate and
    /// no server can hand it back, so it goes in Application Support.
    enum Store {
        case cache, durable

        var directory: URL? {
            let search: FileManager.SearchPathDirectory = self == .cache ? .cachesDirectory : .applicationSupportDirectory
            guard let base = FileManager.default.urls(for: search, in: .userDomainMask).first else { return nil }
            let dir = base.appendingPathComponent("SkyWarden\(self == .cache ? "Cache" : "Data")", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    private static let directory: URL? = Store.cache.directory

    /// Rounds a coordinate to a grid so nearby requests share one cache entry.
    /// 0.05° ≈ 5.5 km — well inside the distance over which a tide or a 30-year
    /// normal is identical, and it keeps the user's exact position out of the
    /// cache key.
    ///
    /// A grid has edges: two points a few hundred metres apart can still land in
    /// different cells and cost a second call. That's bounded waste, not zero
    /// waste — the TTL, not the grid, is what does the heavy lifting.
    static func gridKey(_ prefix: String, _ location: CLLocation, precision: Double = 0.05) -> String {
        let lat = (location.coordinate.latitude / precision).rounded() * precision
        let lon = (location.coordinate.longitude / precision).rounded() * precision
        return String(format: "%@_%.3f_%.3f", prefix, lat, lon)
    }

    static func load<T: Codable>(_ type: T.Type, key: String, ttl: TimeInterval) -> T? {
        guard let url = directory?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry<T>.self, from: data)
        else { return nil }

        guard Date().timeIntervalSince(entry.storedAt) < ttl else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.value
    }

    static func save<T: Codable>(_ value: T, key: String) {
        guard let url = directory?.appendingPathComponent("\(key).json"),
              let data = try? JSONEncoder().encode(Entry(storedAt: Date(), value: value))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Fetches through the cache: a hit costs nothing, a miss calls `fetch` and
    /// stores the result. Failures are not cached — a provider outage shouldn't
    /// pin an empty answer for hours.
    static func through<T: Codable>(key: String, ttl: TimeInterval,
                                    fetch: () async throws -> T) async throws -> T {
        if let hit = load(T.self, key: key, ttl: ttl) { return hit }
        let fresh = try await fetch()
        save(fresh, key: key)
        return fresh
    }

    // MARK: - Durable store (no TTL; survives cache eviction)

    static func loadDurable<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let url = Store.durable.directory?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func saveDurable<T: Codable>(_ value: T, key: String) {
        guard let url = Store.durable.directory?.appendingPathComponent("\(key).json"),
              let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        // Skill data is derived, but only over days of real use — don't ship it
        // to iCloud, and don't let it be purged as "recreatable".
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = false
        var mutable = url
        try? mutable.setResourceValues(resources)
    }

    static func clearDurable() {
        guard let dir = Store.durable.directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Testing/support: wipe everything.
    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

// MARK: - TTLs, in one place so the cost story is auditable

enum CacheTTL {
    /// Tides are astronomical and published days ahead; WorldTides bills per call.
    static let tides: TimeInterval = 6 * 3600
    /// Historical normals for a calendar day. The past does not change.
    static let archive: TimeInterval = 24 * 3600
    static let news: TimeInterval = 30 * 60
    /// Government warning feeds — polite to volunteer-run servers, short enough
    /// that an escalating warning still surfaces within a refresh or two.
    static let warnings: TimeInterval = 5 * 60
}
