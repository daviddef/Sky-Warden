// SkyWarden — LocationManager

import Foundation
import CoreLocation

enum LocationState {
    case notDetermined
    case denied
    case authorized(CLLocation)
    case unknown
}

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var state: LocationState = .unknown
    @Published var placeName: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000  // Update every 1km
        checkCurrentState()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    private func checkCurrentState() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .notDetermined
        case .denied, .restricted:
            state = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            state = .unknown
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in checkCurrentState() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            state = .authorized(location)
            await reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                placeName = [place.subLocality, place.locality]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
        } catch {
            print("Geocode error: \(error)")
        }
    }
}
