//
//  MapView.swift
//  BikeNav
//
//  Google Maps view using UIViewRepresentable (GMSMapView).
//  Displays user location, route polyline, and destination marker.
//  Camera follows user during active navigation.
//

import SwiftUI
import GoogleMaps

// MARK: - MapView

/// SwiftUI wrapper for GMSMapView that displays the navigation map.
struct MapView: UIViewRepresentable {
    
    @EnvironmentObject var navigationManager: NavigationManager
    
    // MARK: - UIViewRepresentable
    
    func makeUIView(context: Context) -> GMSMapView {
        // Default camera position (will be updated with user location)
        let camera = GMSCameraPosition.camera(
            withLatitude: 10.0,
            longitude: 76.0,
            zoom: 15
        )
        
        let options = GMSMapViewOptions()
        options.camera = camera
        
        let mapView = GMSMapView(options: options)
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.rotateGestures = true
        mapView.settings.tiltGestures = true
        mapView.padding = UIEdgeInsets(top: 60, left: 0, bottom: 200, right: 0)
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        
        // Update route polyline
        if !navigationManager.routePolylinePoints.isEmpty {
            coordinator.updateRoutePolyline(
                points: navigationManager.routePolylinePoints,
                on: mapView
            )
        } else {
            coordinator.clearRoutePolyline(on: mapView)
        }
        
        // Update destination marker
        if let dest = navigationManager.destination {
            coordinator.updateDestinationMarker(
                coordinate: dest,
                title: navigationManager.destinationName,
                on: mapView
            )
        } else {
            coordinator.clearDestinationMarker()
        }
        
        // Follow user during navigation
        if case .navigating = navigationManager.navigationState,
           let location = navigationManager.currentLocation {
            let camera = GMSCameraPosition.camera(
                withLatitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                zoom: 17,
                bearing: location.course >= 0 ? location.course : 0,
                viewingAngle: 45
            )
            mapView.animate(to: camera)
        }
        
        // Fit route bounds when route is first calculated
        if coordinator.shouldFitBounds && !navigationManager.routePolylinePoints.isEmpty {
            coordinator.fitBoundsToRoute(points: navigationManager.routePolylinePoints, on: mapView)
            coordinator.shouldFitBounds = false
        }
    }
    
    func makeCoordinator() -> MapCoordinator {
        MapCoordinator()
    }
}

// MARK: - MapCoordinator

/// Coordinator for managing map overlays and markers.
class MapCoordinator: NSObject {
    
    var mapView: GMSMapView?
    
    /// Flag to fit bounds once when route is first calculated
    var shouldFitBounds = true
    
    /// Current route polyline
    private var routePolyline: GMSPolyline?
    
    /// Destination marker
    private var destinationMarker: GMSMarker?
    
    /// Previous polyline points hash for change detection
    private var lastPolylineHash: Int = 0
    
    // MARK: - Route Polyline
    
    /// Calculates a fast hash for coordinate arrays to detect route changes
    private func computeHash(for points: [CLLocationCoordinate2D]) -> Int {
        var hasher = Hasher()
        hasher.combine(points.count)
        for point in points {
            hasher.combine(point.latitude)
            hasher.combine(point.longitude)
        }
        return hasher.finalize()
    }
    
    /// Updates the route polyline on the map.
    /// - Parameters:
    ///   - points: Array of coordinates forming the route.
    ///   - mapView: The GMSMapView to draw on.
    func updateRoutePolyline(points: [CLLocationCoordinate2D], on mapView: GMSMapView) {
        let newHash = computeHash(for: points)
        guard newHash != lastPolylineHash else { return }
        lastPolylineHash = newHash
        
        // Remove existing polyline
        routePolyline?.map = nil
        
        // Create new polyline
        let path = GMSMutablePath()
        for point in points {
            path.add(point)
        }
        
        let polyline = GMSPolyline(path: path)
        polyline.strokeWidth = 5.0
        polyline.strokeColor = UIColor.systemBlue
        polyline.geodesic = true
        polyline.map = mapView
        
        routePolyline = polyline
        shouldFitBounds = true
    }
    
    /// Removes the route polyline from the map.
    func clearRoutePolyline(on mapView: GMSMapView) {
        routePolyline?.map = nil
        routePolyline = nil
        lastPolylineHash = 0
    }
    
    // MARK: - Destination Marker
    
    /// Updates or creates the destination marker.
    /// - Parameters:
    ///   - coordinate: The destination coordinate.
    ///   - title: The marker title.
    ///   - mapView: The GMSMapView to add the marker to.
    func updateDestinationMarker(coordinate: CLLocationCoordinate2D, title: String, on mapView: GMSMapView) {
        if let marker = destinationMarker {
            marker.position = coordinate
            marker.title = title
        } else {
            let marker = GMSMarker(position: coordinate)
            marker.title = title
            marker.icon = GMSMarker.markerImage(with: .red)
            marker.map = mapView
            destinationMarker = marker
        }
    }
    
    /// Removes the destination marker from the map.
    func clearDestinationMarker() {
        destinationMarker?.map = nil
        destinationMarker = nil
    }
    
    // MARK: - Bounds Fitting
    
    /// Adjusts the camera to fit all route points within the visible area.
    /// - Parameters:
    ///   - points: Array of coordinates to fit.
    ///   - mapView: The GMSMapView.
    func fitBoundsToRoute(points: [CLLocationCoordinate2D], on mapView: GMSMapView) {
        guard !points.isEmpty else { return }
        
        var bounds = GMSCoordinateBounds()
        for point in points {
            bounds = bounds.includingCoordinate(point)
        }
        
        let update = GMSCameraUpdate.fit(bounds, withPadding: 60)
        mapView.animate(with: update)
    }
}
