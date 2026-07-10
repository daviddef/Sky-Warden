// Sky Warden — Map tab
//
// Radar is the headline layer: a real ground-radar composite, ~1 km, ~5 minutes
// behind. Cloud and rainfall are the wide, licence-free fallbacks that still
// work where no radar reaches.
//
// See WeatherMapService for the licensing position on each provider.

import SwiftUI
import MapKit
import CoreLocation

struct WeatherMapView: View {
    let location: CLLocation

    @State private var layer: WeatherMapLayer = .radar
    @State private var frames: [MapFrame] = []
    @State private var index: Int = 0
    @State private var playing = false
    @State private var loading = true
    @State private var warming = false      // blocking: the frame on screen isn't ready
    @State private var buffering = false    // background: the other frames are still coming
    @State private var unavailable = false
    @State private var warmTask: Task<Void, Never>?

    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    private var spec: TileLayerSpec? { layer.spec(forLongitude: location.coordinate.longitude) }
    private var currentFrame: MapFrame? { frames.indices.contains(index) ? frames[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let spec, !frames.isEmpty {
                    MapCanvas(center: location.coordinate, spec: spec, frames: frames, index: index,
                              onRegionSettled: warm)
                        .ignoresSafeArea(edges: .horizontal)
                        .id(layer)          // a new layer means a new camera, so rebuild the map
                } else {
                    Rectangle().fill(Sky.surface)
                }

                if loading || warming {
                    VStack(spacing: 10) {
                        ProgressView().tint(Sky.tide)
                        Text(loading ? "Finding the latest imagery…" : "Loading radar…")
                            .font(.system(size: 11)).foregroundColor(Sky.muted)
                    }
                    .padding(16)
                    .background(Sky.card.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .onDisappear { warmTask?.cancel() }
        .onReceive(timer) { _ in
            guard playing, !warming, !buffering, frames.count > 1 else { return }
            index = (index + 1) % frames.count
        }
    }

    // MARK: - Loading

    private func load() async {
        warmTask?.cancel()
        loading = true; warming = false; playing = false; unavailable = false; frames = []
        guard let spec else { loading = false; unavailable = true; return }

        let found = await WeatherMapService.frames(spec, near: location.coordinate)
        guard !found.isEmpty else { loading = false; unavailable = true; return }

        frames = found
        index = found.count - 1
        loading = false
        warming = true          // MapCanvas will report its camera, and `warm` takes it from there
    }

    /// MapKit cancels a renderer's downloads the moment it's hidden, so a frame
    /// that has to fetch during its ~1.2 s on screen never finishes. Pull every
    /// frame's tiles for the visible camera first, then start the animation.
    private func warm(rect: MKMapRect, zoom: Int) {
        guard let spec, !frames.isEmpty else { return }
        warmTask?.cancel()
        warming = true
        playing = false
        let all = self.frames
        let visible = all.indices.contains(index) ? all[index] : all[all.count - 1]

        warmTask = Task {
            // Fetch what's ON SCREEN first and let go of the UI immediately —
            // waiting for all ten frames before showing anything is what made the
            // tab feel stuck. The rest stream in behind it.
            await TileSource.shared.warm(spec: spec, frames: [visible], rect: rect, zoom: zoom)
            guard !Task.isCancelled else { return }
            warming = false
            buffering = all.count > 1

            let rest = all.filter { $0 != visible }
            await TileSource.shared.warm(spec: spec, frames: rest, rect: rect, zoom: zoom)
            guard !Task.isCancelled else { return }
            buffering = false
            playing = true
        }
    }

    // MARK: - Pieces

    private var unavailableCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe.americas").font(.system(size: 28)).foregroundColor(Sky.muted)
            Text(unavailableTitle)
                .font(.system(size: 13)).foregroundColor(Sky.text)
            if layer == .cloud {
                Text("Geostationary satellites each see one face of the Earth.\nTry the rainfall layer, which is global.")
                    .font(.system(size: 11)).foregroundColor(Sky.muted).multilineTextAlignment(.center)
            }
        }
        .padding(18).background(Sky.card.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var unavailableTitle: String {
        switch layer {
        case .radar: "Radar unavailable right now"
        case .cloud: "No satellite covers this longitude"
        case .rainfall: "Imagery unavailable right now"
        }
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
                .disabled(warming || buffering)

                Slider(value: Binding(
                    get: { Double(index) },
                    set: { index = Int($0.rounded()); playing = false }
                ), in: 0...Double(max(1, frames.count - 1)), step: 1)
                .tint(Sky.tide)
                .disabled(warming)

                Text(currentFrame.map { timeLabel($0.date) } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Sky.white).frame(width: 62, alignment: .trailing)
            }
            if layer == .radar { radarLegend }

            Text(layer.attribution)
                .font(.system(size: 8.5)).foregroundColor(Sky.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(12)
    }

    /// The provider's ramp runs beige → blue → cyan → yellow, so intensity isn't
    /// guessable from colour alone. Without this, cyan cores read as light rain.
    private var radarLegend: some View {
        HStack(spacing: 6) {
            Text("Light").font(.system(size: 8.5)).foregroundColor(Sky.muted)
            HStack(spacing: 0) {
                ForEach(Array(WeatherMapService.radarRamp.enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255))
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
            Text("Heavy").font(.system(size: 8.5)).foregroundColor(Sky.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radar intensity scale, light to heavy")
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

            Text(layer.footnote)
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
    let frames: [MapFrame]
    let index: Int
    /// Fires once the camera stops moving, with exactly the rect and zoom MapKit
    /// is about to request tiles for.
    let onRegionSettled: (MKMapRect, Int) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        // Apple's logo and legal link must stay visible — lift them above the
        // scrubber, which is taller on the radar layer because of its legend.
        map.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 104, right: 0)
        map.setRegion(MKCoordinateRegion(center: center,
                                         latitudinalMeters: spec.regionMetres,
                                         longitudinalMeters: spec.regionMetres), animated: false)
        context.coordinator.onRegionSettled = onRegionSettled
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.onRegionSettled = onRegionSettled

        let target = frames.indices.contains(index) ? frames[index] : frames.last

        // Add every frame ONCE. Removing and re-adding an overlay on each tick
        // cancels its in-flight tile loads, so nothing ever finishes drawing.
        // Instead all frames stay mounted and we animate by fading between them.
        let key = spec.id + frames.map(\.token).joined()
        if c.key != key {
            // MapKit calls rendererFor SYNCHRONOUSLY inside addOverlay, so `active`
            // must already be set — otherwise every renderer is built with alpha 0
            // and raising it later never makes those tiles draw.
            c.setActiveImmediately(target)
            map.overlays.forEach(map.removeOverlay)
            c.renderers.removeAll()
            c.key = key
            for f in frames { map.addOverlay(WeatherTileOverlay(spec: spec, frame: f), level: .aboveRoads) }
            c.reportRegion(map)      // first camera — nothing has moved, so no delegate callback comes
        } else {
            c.crossfade(to: target)  // smooth dissolve, no hard cut / blank flash
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isInfrared: spec.post == .infraredCloud) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let isInfrared: Bool
        var key = ""
        var active: MapFrame?               // the frame we're showing / fading to
        private var previous: MapFrame?     // the frame fading out
        var renderers: [MapFrame: MKTileOverlayRenderer] = [:]
        var onRegionSettled: ((MKMapRect, Int) -> Void)?
        private var settle: DispatchWorkItem?
        private var lastReported: (rect: MKMapRect, zoom: Int)?

        private var link: CADisplayLink?
        private var fadeStart: CFTimeInterval = 0
        private let fadeDuration: CFTimeInterval = 0.4

        init(isInfrared: Bool) { self.isInfrared = isInfrared }

        private var visibleAlpha: CGFloat { isInfrared ? 0.95 : 0.8 }

        /// First mount / layer change: snap to the frame, no fade.
        func setActiveImmediately(_ frame: MapFrame?) {
            link?.invalidate(); link = nil
            previous = nil
            active = frame
            applyAlphas(progress: 1)
        }

        /// Advance to `frame` by dissolving: the outgoing frame stays up while the
        /// incoming one draws and fades in, so there's never a blank gap — that
        /// gap is what read as a flash on every tick.
        func crossfade(to frame: MapFrame?) {
            guard frame != active else { return }
            previous = active
            active = frame
            // Nudge the incoming renderer to draw now (invisible overlays are
            // never drawn); it composites from the warmed tile cache, so this is
            // cheap and the outgoing frame covers it meanwhile.
            if let f = frame { renderers[f]?.setNeedsDisplay() }
            fadeStart = CACurrentMediaTime()
            if link == nil {
                link = CADisplayLink(target: self, selector: #selector(step))
                link?.add(to: .main, forMode: .common)
            }
        }

        @objc private func step() {
            let t = min(1, (CACurrentMediaTime() - fadeStart) / fadeDuration)
            applyAlphas(progress: t)
            if t >= 1 { link?.invalidate(); link = nil; previous = nil }
        }

        /// Alpha alone recomposites the renderer (no `setNeedsDisplay`, which
        /// would force a tile reload and reintroduce the flicker).
        private func applyAlphas(progress: Double) {
            for (frame, r) in renderers {
                let a: CGFloat
                if frame == active { a = visibleAlpha * CGFloat(progress) }
                else if frame == previous { a = visibleAlpha * CGFloat(1 - progress) }
                else { a = 0 }
                if r.alpha != a { r.alpha = a }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? WeatherTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKTileOverlayRenderer(tileOverlay: tile)
            r.blendMode = .normal   // every layer is transparent by the time it reaches us
            r.alpha = (tile.frame == active) ? visibleAlpha : 0
            renderers[tile.frame] = r
            return r
        }

        /// Debounced: a pinch fires this continuously, and each warm-up is a
        /// burst of tile fetches we don't want to start and abandon.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            settle?.cancel()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let mapView else { return }
                self?.reportRegion(mapView)
            }
            settle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        func reportRegion(_ map: MKMapView) {
            guard map.bounds.width > 0 else { return }
            let rect = map.visibleMapRect
            let zoom = WeatherMapService.zoomLevel(visibleMapRect: rect, widthPoints: Double(map.bounds.width))
            // A pan inside the tiles we already warmed doesn't need another sweep.
            if let last = lastReported, last.zoom == zoom, last.rect.contains(rect) { return }
            lastReported = (rect, zoom)
            onRegionSettled?(rect, zoom)
        }
    }
}
