import CaddieCore
import MapKit
import SwiftUI
import UIKit

/// A pin to draw on the hole map.
struct MapPin: Equatable, Identifiable {
    enum Kind: Equatable {
        case mark(number: Int, lie: Lie, penalty: Bool)
        case flag
        case teeMarker
        case measure
    }

    var id: String
    var coordinate: Coordinate
    var kind: Kind
    var draggable: Bool = false
}

final class PinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let pin: MapPin

    init(pin: MapPin) {
        self.pin = pin
        self.coordinate = pin.coordinate.clLocation
    }
}

/// The satellite map of one hole: course outlines, the marks, the flag, and the phone's position.
/// Tapping measures, a long press places a point, and marks can be dragged.
struct HoleMapView: UIViewRepresentable {
    var hole: Hole?
    var features: [CourseFeature]
    var pins: [MapPin]
    /// Lines to draw between points, in order (the path of the shots).
    var path: [Coordinate]
    /// A line from the first point through the second to the third, for the measuring tool.
    var measure: [Coordinate]
    var fallbackCenter: Coordinate
    var showsUser: Bool
    /// Change this to make the map frame the hole again.
    var frameToken: Int
    var onTap: (Coordinate) -> Void = { _ in }
    var onLongPress: (Coordinate) -> Void = { _ in }
    var onMovePin: (String, Coordinate) -> Void = { _, _ in }
    var onSelectPin: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .satellite
        map.isPitchEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.45
        press.delegate = context.coordinator
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.showsUserLocation = showsUser

        let outlineKey = "\(hole?.number ?? 0)|\(features.count)|\(features.first?.id ?? "")|\(features.last?.id ?? "")"
        if outlineKey != coordinator.outlineKey {
            coordinator.outlineKey = outlineKey
            map.removeOverlays(map.overlays.filter { ($0 as? MKShape)?.title != "path" && ($0 as? MKShape)?.title != "measure" })
            // Draw big shapes first so bunkers and greens sit on top of fairways.
            let order: [FeatureKind] = [.rough, .water, .fairway, .tee, .bunker, .green]
            for kind in order {
                for feature in features where feature.kind == kind && feature.ring.count >= 3 {
                    let points = feature.ring.map { $0.clLocation }
                    let polygon = MKPolygon(coordinates: points, count: points.count)
                    polygon.title = kind.rawValue
                    map.addOverlay(polygon)
                }
            }
        }

        if path != coordinator.path || measure != coordinator.measure {
            coordinator.path = path
            coordinator.measure = measure
            map.removeOverlays(map.overlays.filter { ($0 as? MKShape)?.title == "path" || ($0 as? MKShape)?.title == "measure" })
            if path.count >= 2 {
                let points = path.map { $0.clLocation }
                let line = MKPolyline(coordinates: points, count: points.count)
                line.title = "path"
                map.addOverlay(line)
            }
            if measure.count >= 2 {
                let points = measure.map { $0.clLocation }
                let line = MKPolyline(coordinates: points, count: points.count)
                line.title = "measure"
                map.addOverlay(line)
            }
        }

        if pins != coordinator.pins && !coordinator.isDragging {
            coordinator.pins = pins
            map.removeAnnotations(map.annotations.filter { $0 is PinAnnotation })
            map.addAnnotations(pins.map { PinAnnotation(pin: $0) })
        }

        if frameToken != coordinator.frameToken {
            coordinator.frameToken = frameToken
            frame(map, animated: coordinator.hasFramed)
            coordinator.hasFramed = true
        }
    }

    /// Points the map up the hole with the tee at the bottom and the green at the top.
    private func frame(_ map: MKMapView, animated: Bool) {
        if let hole = hole, let tee = hole.tee, let green = hole.greenCenter {
            let length = Geo.meters(tee, green)
            let middle = Coordinate(lat: (tee.lat + green.lat) / 2, lon: (tee.lon + green.lon) / 2)
            let camera = MKMapCamera(lookingAtCenter: middle.clLocation, fromDistance: max(260, length * 2.7),
                                     pitch: 0, heading: Geo.bearing(tee, green))
            map.setCamera(camera, animated: animated)
        } else {
            let camera = MKMapCamera(lookingAtCenter: fallbackCenter.clLocation, fromDistance: 1800, pitch: 0, heading: 0)
            map.setCamera(camera, animated: animated)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: HoleMapView
        var outlineKey = ""
        var path: [Coordinate] = []
        var measure: [Coordinate] = []
        var pins: [MapPin] = []
        var frameToken = Int.min
        var hasFramed = false
        var isDragging = false

        init(_ parent: HoleMapView) {
            self.parent = parent
        }

        func coordinate(of recognizer: UIGestureRecognizer) -> Coordinate? {
            guard let map = recognizer.view as? MKMapView else { return nil }
            let point = recognizer.location(in: map)
            return Coordinate(map.convert(point, toCoordinateFrom: map))
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let coordinate = coordinate(of: recognizer) else { return }
            parent.onTap(coordinate)
        }

        @objc func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let coordinate = coordinate(of: recognizer) else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(coordinate)
        }

        // Touches on a pin belong to the pin (select, drag), not to the map's tap and long press.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is MKAnnotationView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                let kind = FeatureKind(rawValue: polygon.title ?? "") ?? .rough
                var color: UIColor
                switch kind {
                case .green: color = UIColor(red: 0.45, green: 0.95, blue: 0.50, alpha: 1)
                case .fairway: color = UIColor(red: 0.35, green: 0.80, blue: 0.40, alpha: 1)
                case .tee: color = UIColor(red: 0.80, green: 0.95, blue: 0.80, alpha: 1)
                case .bunker: color = UIColor(red: 0.96, green: 0.87, blue: 0.60, alpha: 1)
                case .water: color = UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)
                case .rough: color = UIColor(red: 0.20, green: 0.50, blue: 0.25, alpha: 1)
                }
                renderer.fillColor = color.withAlphaComponent(kind == .rough ? 0.10 : 0.28)
                renderer.strokeColor = color.withAlphaComponent(0.9)
                renderer.lineWidth = kind == .green ? 2 : 1
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                if line.title == "measure" {
                    renderer.strokeColor = UIColor.white.withAlphaComponent(0.9)
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [6, 5]
                } else {
                    renderer.strokeColor = UIColor.systemYellow
                    renderer.lineWidth = 2.5
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let item = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation)
            guard let marker = view as? MKMarkerAnnotationView else { return view }
            marker.canShowCallout = false
            marker.isDraggable = item.pin.draggable
            marker.displayPriority = .required
            marker.glyphImage = nil
            marker.glyphText = nil
            marker.animatesWhenAdded = false
            marker.titleVisibility = .hidden
            switch item.pin.kind {
            case .mark(let number, let lie, let penalty):
                marker.glyphText = "\(number)"
                marker.markerTintColor = penalty ? .systemRed : Theme.color(for: lie)
                marker.glyphTintColor = .black
            case .flag:
                marker.glyphImage = UIImage(systemName: "flag.fill")
                marker.markerTintColor = .systemRed
                marker.glyphTintColor = .white
            case .teeMarker:
                marker.glyphText = "T"
                marker.markerTintColor = .white
                marker.glyphTintColor = .black
            case .measure:
                marker.glyphImage = UIImage(systemName: "scope")
                marker.markerTintColor = .darkGray
                marker.glyphTintColor = .white
            }
            return marker
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let item = view.annotation as? PinAnnotation else { return }
            mapView.deselectAnnotation(item, animated: false)
            if case .mark = item.pin.kind {
                parent.onSelectPin(item.pin.id)
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting, .dragging:
                isDragging = true
            case .ending, .canceling:
                isDragging = false
                view.setDragState(.none, animated: false)
                if newState == .ending, let item = view.annotation as? PinAnnotation {
                    parent.onMovePin(item.pin.id, Coordinate(item.coordinate))
                }
            default:
                break
            }
        }
    }
}
