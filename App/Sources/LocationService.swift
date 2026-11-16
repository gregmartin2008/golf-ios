import CaddieCore
import CoreLocation
import Foundation

/// The phone's position while a round is on screen.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: Coordinate?
    /// Accuracy of the last fix in meters.
    @Published var accuracy: Double?
    @Published var denied = false

    private let manager = CLLocationManager()
    private var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.activityType = .fitness
    }

    /// Asks for permission if needed and starts following the phone.
    func start() {
        running = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            denied = true
        default:
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        denied = status == .denied || status == .restricted
        if running && (status == .authorizedWhenInUse || status == .authorizedAlways) {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        // Ignore a fix that is old (left over from before the app was opened).
        if abs(latest.timestamp.timeIntervalSinceNow) > 15 { return }
        coordinate = Coordinate(lat: latest.coordinate.latitude, lon: latest.coordinate.longitude)
        accuracy = latest.horizontalAccuracy
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix is followed by another attempt; nothing to do.
    }
}
