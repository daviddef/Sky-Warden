// Sky Warden — Map tab
// A weather-system view on an Apple Maps basemap. Deliberately NOT called
// "Radar": the free, licence-free imagery is ~4 km cloud and ~10 km rainfall.
// Real radar arrives when a BOM / RainViewer licence does.

import SwiftUI
import MapKit
import CoreLocation

struct WeatherMapView: View {
    let location: CLLocation

    @State private var layer: WeatherMapLayer = .cloud
    @State private var frames: [Date] = []
    @State private var index: Int = 0
    @State private var playing = true
    @State private var loading = true
    @State private var unavailable = false

    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    private var spec: TileLayerSpec? { layer.spec(forLongitude: location.coordinate.longitude) }
    private var currentFrame: Date? { frames.indices.contains(index) ? frames[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let spec, !frames.isEmpty {
                    MapCanvas(center: location.coordinate, spec: spec, frames: frames, index: index)
                        .ignoresSafeArea(edges: .horizontal)
                } else {
                    Rectangle().fill(Sky.surface)
                }

                if loading {
                    VStack(spacing: 10) {
                        ProgressView().tint(Sky.tide)
                        Text("Finding the latest imagery…")
                            .font(.system(size: 11)).foregroundColor(Sky.muted)
                    }
                } else if unavailable {
                    unavailableCard
                }

                VStack {
                    Spacer()
                    if !frames.isEmpty { scrubber }
                }
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .task(id: layer.rawValue + "\(location.coordinate.latitude)") { await load() }
        .onReceive(timer) { _ in
            guard playing, frames.count > 1 else { return }
            index = (index + 1) % frames.count
        }
    }

    // MARK: - Loading
    private func load() async {
        loading = true; unavailable = false; frames = []
        guard let spec else { loading = false; unavailable = true; return }
        guard let latest = await WeatherMapService.latestFrame(spec, near: location.coordinate) else {
            loading = false; unavailable = true; return
        }
        let all = WeatherMapService.frames(endingAt: latest, spec: spec, count: layer == .cloud ? 10 : 6)

        // Pull every frame's source tiles up front. MapKit cancels a renderer's
        // downloads as soon as it's hidden, so a frame that has to fetch during
        // its ~1.2 s on screen never finishes and never draws.
        await TileSource.shared.warm(spec: spec, frames: all, region: MapCanvas.region(around: location.coordinate))

        frames = all
        index = all.count - 1
        loading = false
    }

    // MARK: - Pieces
    private var unavailableCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe.americas").font(.system(size: 28)).foregroundColor(Sky.muted)
            Text(layer == .cloud ? "No satellite covers this longitude" : "Imagery unavailable right now")
                .font(.system(size: 13)).foregroundColor(Sky.text)
            if layer == .cloud {
                Text("Geostationary satellites each see one face of the Earth.\nTry the rainfall layer, which is global.")
                    .font(.system(size: 11)).foregroundColor(Sky.muted).multilineTextAlignment(.center)
            }
        }
        .padding(18).background(Sky.card.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(Sky.navy)
                        .frame(width: 28, height: 28).background(Sky.tide).clipShape(Circle())
                }
                .accessibilityLabel(playing ? "Pause" : "Play")

                Slider(value: Binding(
                    get: { Double(index) },
                    set: { index = Int($0.rounded()); playing = false }
                ), in: 0...Double(max(1, frames.count - 1)), step: 1)
                .tint(Sky.tide)

                Text(currentFrame.map(timeLabel) ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Sky.white).frame(width: 62, alignment: .trailing)
            }
            Text(layer.attribution)
                .font(.system(size: 8.5)).foregroundColor(Sky.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(12)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Layer", selection: $layer) {
                ForEach(WeatherMapLayer.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 9))
                Text(layer.caption)
                Spacer()
            }
            .font(.system(size: 10)).foregroundColor(Sky.muted)

            Text("A weather-system view, not a street-level radar. Local radar needs a BOM data licence.")
                .font(.system(size: 9.5)).foregroundColor(Sky.muted.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        .background(Sky.navy)
    }

    private func timeLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - MapKit bridge
private struct MapCanvas: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let spec: TileLayerSpec
    let frames: [Date]
    let index: Int

    /// The one definition of what's on screen — the warm-up prefetches exactly
    /// the tiles this covers.
    static func region(around center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, latitudinalMeters: 1_400_000, longitudinalMeters: 1_400_000)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        // Apple's logo and legal link must stay visible — lift them above the scrubber.
        map.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 74, right: 0)
        // ~1400 km across — the scale this imagery actually resolves.
        map.setRegion(Self.region(around: center), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.isInfrared = spec.id.contains("Infrared")

        // Add every frame ONCE. Removing and re-adding an overlay on each tick
        // cancels its in-flight tile loads, so nothing ever finishes drawing.
        // Instead all frames stay mounted and we animate by toggling alpha.
        // MapKit calls rendererFor SYNCHRONOUSLY inside addOverlay, so `active`
        // must already be set — otherwise every renderer is built with alpha 0
        // and raising it later never makes those tiles draw.
        c.active = frames.indices.contains(index) ? frames[index] : frames.last

        let key = spec.id + frames.map { "\($0.timeIntervalSince1970)" }.joined()
        if c.key != key {
            map.overlays.forEach(map.removeOverlay)
            c.renderers.removeAll()
            c.key = key
            for f in frames { map.addOverlay(GIBSTileOverlay(spec: spec, frame: f), level: .aboveRoads) }
        }
        c.applyAlphas()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var isInfrared = true
        var key = ""
        var active: Date?
        var renderers: [Date: MKTileOverlayRenderer] = [:]

        func applyAlphas() {
            let visible: CGFloat = isInfrared ? 0.95 : 0.75
            for (frame, r) in renderers {
                let a: CGFloat = (frame == active) ? visible : 0
                if r.alpha != a { r.alpha = a; r.setNeedsDisplay() }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? GIBSTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKTileOverlayRenderer(tileOverlay: tile)
            // Cloud tiles are made transparent in GIBSTileOverlay.cloudMask, and
            // precipitation tiles already are — so both composite normally.
            r.blendMode = .normal
            r.alpha = (tile.frame == active) ? (isInfrared ? 0.95 : 0.75) : 0
            renderers[tile.frame] = r
            return r
        }
    }
}
