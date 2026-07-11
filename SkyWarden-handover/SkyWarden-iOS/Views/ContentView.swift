// SkyWarden — ContentView
// Root view: 10-tab structure + location + fetch orchestration.

import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var aggregator      = WeatherAggregator()
    @StateObject private var locationManager = LocationManager()
    @State private var showSettings = false
    // Observed so changing a unit re-renders every tab (the views read `Units`,
    // which reads UserDefaults, so they need a reason to re-evaluate).
    @AppStorage(UnitKey.temperature) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(UnitKey.wind)        private var windUnit        = WindUnit.kmh.rawValue
    @AppStorage("display.nowSimple") private var nowSimple       = true
    // Initial tab (overridable via SKYWARDEN_TAB env var for screenshots/QA).
    @State private var selectedTab: Tab = {
        if let t = ProcessInfo.processInfo.environment["SKYWARDEN_TAB"], let tab = Tab(rawValue: t) { return tab }
        return .now
    }()

    // `week` and `today` were retired — the week lives on the Detail at-a-glance
    // and the day opens as an overlay when you tap the temperature. `sky` now
    // folds in news (astronomy + space + weather stories).
    enum Tab: String, CaseIterable, Identifiable {
        case now, scene, map, tides, plans, uv, sky, sources
        var id: String { rawValue }
        var emoji: String {
            switch self {
            case .now: "🌤"; case .scene: "🏖"; case .map: "🗺"
            case .tides: "🌊"; case .plans: "📆"; case .uv: "☀️"; case .sky: "🔭"
            case .sources: "📡"
            }
        }
        var label: String {
            switch self {
            case .now: "Now"; case .scene: "Scene"; case .map: "Map"
            case .tides: "Tides"; case .plans: "Plans"; case .uv: "UV"; case .sky: "Sky"
            case .sources: "Sources"
            }
        }
    }

    var body: some View {
        ZStack {
            Sky.navy.ignoresSafeArea()

            switch locationManager.state {
            case .notDetermined:
                LocationPermissionView { locationManager.requestPermission() }
            case .denied:
                LocationDeniedView()
            case .authorized(let location):
                mainContent(location: location)
                    .task(id: location.coordinate.latitude) { await aggregator.refresh(location: location) }
            case .unknown:
                LoadingView(message: "Finding your location…")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Main tab content
    @ViewBuilder
    private func mainContent(location: CLLocation) -> some View {
        VStack(spacing: 0) {
            NavBar(title: locationManager.placeName ?? "Current Location",
                   fetchState: aggregator.fetchState,
                   nowMode: selectedTab == .now ? $nowSimple : nil,
                   onSettings: { showSettings = true })

            switch aggregator.fetchState {
            case .idle, .loading:
                LoadingView(message: "Gathering weather from all sources…")
            case .loaded(let consensus), .partialLoad(let consensus, _):
                TabView(selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        tabContent(tab, consensus: consensus, location: location).tag(tab)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            case .failed(let error):
                ErrorView(error: error) { Task { await aggregator.refresh(location: location, force: true) } }
            }

            SkyTabBar(selected: $selectedTab, flags: flags)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab, consensus: ConsensusWeather, location: CLLocation) -> some View {
        switch tab {
        case .now:
            HomeView(consensus: consensus, failedSources: aggregator.failedSources,
                     location: location, placeName: locationManager.placeName,
                     tideDay: aggregator.tideDay, moonData: aggregator.moonData,
                     region: locationManager.region, countryCode: locationManager.countryCode,
                     onOpenTab: { selectedTab = $0 },
                     refresh: { await aggregator.refresh(location: location, force: true) })
        case .scene:
            SceneView(consensus: consensus, tideDay: aggregator.tideDay)
        case .map:
            WeatherMapView(location: location)
        case .tides:
            TidesDetailView(tideDay: aggregator.tideDay, moonData: aggregator.moonData)
        case .plans:
            PlansView(dailyForecast: consensus.dailyForecast)
        case .uv:
            UVView(consensus: consensus)
        case .sky:
            SkyView(location: location,
                    region: locationManager.region, countryCode: locationManager.countryCode)
        case .sources:
            SourcesView(consensus: consensus, location: location)
        }
    }

    private var flags: Set<Tab> {
        if case .loaded(let c) = aggregator.fetchState, c.hasDisagreements { return [.sources] }
        if case .partialLoad(let c, _) = aggregator.fetchState, c.hasDisagreements { return [.sources] }
        return []
    }
}

// MARK: - Navigation bar
private struct NavBar: View {
    let title: String
    let fetchState: FetchState
    /// The Simple↔Detailed toggle, present only on the Now tab. Pull-to-refresh
    /// replaced the old refresh button, so the bar stays quiet.
    var nowMode: Binding<Bool>? = nil
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.fill").font(.system(size: 12)).foregroundColor(Sky.muted)
            Text(title).font(SkyType.body).fontWeight(.medium).foregroundColor(Sky.white)
            if case .loading = fetchState {
                ProgressView().tint(Sky.muted).scaleEffect(0.6)
            }
            Spacer()
            if let nowMode {
                Button { withAnimation(.easeInOut(duration: 0.2)) { nowMode.wrappedValue.toggle() } } label: {
                    Image(systemName: nowMode.wrappedValue ? "gauge.with.dots.needle.bottom.50percent"
                                                           : "square.text.square")
                        .font(.system(size: 16)).foregroundColor(Sky.muted)
                }
                .accessibilityLabel(nowMode.wrappedValue ? "Show detailed view" : "Show simple view")
            }
            Button(action: onSettings) {
                Image(systemName: "gearshape").font(.system(size: 15)).foregroundColor(Sky.muted)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Sky.ink)
    }
}

// MARK: - Scrollable emoji tab bar
private struct SkyTabBar: View {
    @Binding var selected: ContentView.Tab
    let flags: Set<ContentView.Tab>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ContentView.Tab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selected = tab }
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    Text(tab.emoji).font(.system(size: 17))
                                    if flags.contains(tab) {
                                        Circle().fill(Sky.amber).frame(width: 6, height: 6).offset(x: 12, y: -9)
                                    }
                                }
                                Text(tab.label)
                                    .font(.system(size: 9, weight: selected == tab ? .bold : .regular))
                                    .foregroundColor(selected == tab ? Sky.white : Sky.muted)
                                Circle().fill(selected == tab ? Sky.tide : .clear).frame(width: 3, height: 3)
                            }
                            .frame(minWidth: 46).padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.top, 8).padding(.bottom, 6)
            .background(Sky.ink)
            .overlay(alignment: .top) { Divider().background(Sky.surface) }
            .onChange(of: selected) { _, tab in
                withAnimation { proxy.scrollTo(tab, anchor: .center) }
            }
        }
    }
}

// MARK: - Loading / error / permission states
struct LoadingView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Sky.tide).scaleEffect(1.3)
            Text(message).font(SkyType.caption).foregroundColor(Sky.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let error: Error
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundColor(Sky.amber)
            Text(error.localizedDescription).font(SkyType.caption).foregroundColor(Sky.text)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Try Again", action: retry)
                .font(SkyType.body).fontWeight(.medium).foregroundColor(Sky.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Sky.card).clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LocationPermissionView: View {
    let onRequest: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle").font(.system(size: 60)).foregroundColor(Sky.tide)
            Text("Sky Warden needs your location\nto fetch local weather")
                .font(SkyType.body).foregroundColor(Sky.text).multilineTextAlignment(.center)
            Button("Enable Location", action: onRequest)
                .font(SkyType.body).fontWeight(.semibold).foregroundColor(Sky.navy)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(Sky.tide).clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LocationDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash").font(.system(size: 44)).foregroundColor(Sky.amber)
            Text("Location access denied").font(SkyType.smallTemp).foregroundColor(Sky.white)
            Text("Enable Location Services for Sky Warden\nin Settings → Privacy → Location Services")
                .font(SkyType.caption).foregroundColor(Sky.muted).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(SkyType.body).foregroundColor(Sky.tide)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
