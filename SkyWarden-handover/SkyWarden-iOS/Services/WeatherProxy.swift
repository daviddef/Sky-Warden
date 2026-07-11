// Sky Warden — provider request router
// Routes provider calls through the central Supabase proxy when PROXY_BASE_URL is
// configured (keys live server-side, responses cached per location-grid). Falls
// back to direct provider calls otherwise, so the app runs before the backend is
// deployed. Apple WeatherKit is native and never routed here.

import Foundation

enum WeatherProxy {
    static var baseURL: String { info("PROXY_BASE_URL") }
    static var appToken: String { info("PROXY_APP_TOKEN") }
    static var isEnabled: Bool { !baseURL.isEmpty }

    /// The pooled-ledger endpoint, derived from the proxy base by swapping the
    /// trailing path component (…/functions/v1/weather → …/functions/v1/ledger).
    /// Empty when the proxy is off, so the pool is simply skipped in direct mode.
    static var ledgerURL: URL? {
        guard isEnabled, let u = URL(string: baseURL) else { return nil }
        return u.deletingLastPathComponent().appendingPathComponent("ledger")
    }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    /// Builds a request for a provider call.
    /// - In proxy mode: hits `PROXY_BASE_URL?source=…` with the provider's params;
    ///   the API key is omitted (the server injects it) and the app token is added.
    /// - In direct mode: hits the provider directly and appends the key param.
    /// - `items` should NOT include the key — pass it via `keyParam`/`keyValue`.
    static func request(source: String,
                        directBase: String,
                        items: [URLQueryItem],
                        keyParam: String? = nil,
                        keyValue: String? = nil) -> URLRequest? {
        var components: URLComponents?
        if isEnabled {
            components = URLComponents(string: baseURL)
            components?.queryItems = [URLQueryItem(name: "source", value: source)] + items
        } else {
            components = URLComponents(string: directBase)
            var q = items
            if let keyParam, let keyValue, !keyValue.isEmpty {
                q.append(URLQueryItem(name: keyParam, value: keyValue))
            }
            components?.queryItems = q
        }
        guard let url = components?.url else { return nil }
        var req = URLRequest(url: url)
        if isEnabled && !appToken.isEmpty {
            req.setValue(appToken, forHTTPHeaderField: "x-skywarden-app")
        }
        return req
    }
}
