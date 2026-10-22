//
//  NavigationManager.swift
//  BikeNav
//
//  Google Maps Directions API integration and real-time navigation tracking.
//  Calculates routes, tracks user location, detects step transitions,
//  and forwards navigation data to the BLE manager.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Navigation State

/// Represents the current state of navigation.
enum NavigationState {
    case idle
    case calculatingRoute
    case navigating
    case arrived
    case error(String)
}

// MARK: - NavigationManager

/// Manages route calculation, real-time navigation tracking, and BLE data forwarding.
class NavigationManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current navigation state
    @Published var navigationState: NavigationState = .idle
    
    /// Current navigation data being sent to ESP32
    @Published var currentNavData: NavigationData = .idle
    
    /// All route steps from the Directions API
    @Published var routeSteps: [RouteStep] = []
    
    /// Index of the current step being navigated
    @Published var currentStepIndex: Int = 0
    
    /// Destination coordinate
    @Published var destination: CLLocationCoordinate2D?
    
    /// Destination name for display
    @Published var destinationName: String = ""
    
    /// Current user location
    @Published var currentLocation: CLLocation?
    
    /// Encoded polyline points for the entire route (for map display)
    @Published var routePolylinePoints: [CLLocationCoordinate2D] = []
    
    /// Total route distance text
    @Published var totalDistanceText: String = ""
    
    /// Total route duration text
    @Published var totalDurationText: String = ""
    
    /// Estimated arrival time
    @Published var estimatedArrival: String = ""
    
    // MARK: - Internal Properties
    
    /// Reference to BLE manager for sending data
    var bleManager: BLEManager?
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    private let session = URLSession.shared
    private var bleUpdateTimer: Timer?
    private var lastBLEUpdate: Date = .distantPast
    
    /// Distance threshold to advance to next step (in meters)
    private let stepAdvanceThreshold: CLLocationDistance = 30.0
    
    /// Minimum interval between BLE updates (seconds)
    private let bleUpdateInterval: TimeInterval = 5.0
    
    /// Google Maps API key from UserDefaults
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "googleMapsAPIKey") ?? ""
    }
    
    /// Distance unit preference
    private var distanceUnit: DistanceUnit {
        let raw = UserDefaults.standard.string(forKey: "distanceUnit") ?? DistanceUnit.metric.rawValue
        return DistanceUnit(rawValue: raw) ?? .metric
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Location Manager Setup
    
    /// Configures the CLLocationManager for navigation-grade accuracy.
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5 // Update every 5 meters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.requestAlwaysAuthorization()
    }
    
    // MARK: - Public Methods
    
    /// Calculates a route from the current location to the specified destination.
    /// - Parameters:
    ///   - coordinate: The destination coordinate.
    ///   - name: The destination name for display.
    func calculateRoute(to coordinate: CLLocationCoordinate2D, name: String) {
        guard !apiKey.isEmpty else {
            navigationState = .error("Google Maps API key not set. Go to Settings to add it.")
            return
        }
        
        guard let currentLoc = currentLocation else {
            // Request location and retry
            locationManager.requestLocation()
            navigationState = .error("Waiting for current location...")
            return
        }
        
        destination = coordinate
        destinationName = name
        navigationState = .calculatingRoute
        
        let origin = "\(currentLoc.coordinate.latitude),\(currentLoc.coordinate.longitude)"
        let dest = "\(coordinate.latitude),\(coordinate.longitude)"
        
        let urlString = "https://maps.googleapis.com/maps/api/directions/json"
            + "?origin=\(origin)"
            + "&destination=\(dest)"
            + "&mode=bicycling"
            + "&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            navigationState = .error("Invalid directions URL")
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.navigationState = .error("Route calculation failed: \(error.localizedDescription)")
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.navigationState = .error("No data received from Directions API")
                }
                return
            }
            
            self.parseDirectionsResponse(data: data)
        }.resume()
    }
    
    /// Starts navigation along the calculated route.
    func startNavigation() {
        guard !routeSteps.isEmpty else { return }
        
        currentStepIndex = 0
        navigationState = .navigating
        locationManager.startUpdatingLocation()
        
        // Start periodic BLE updates
        startBLEUpdateTimer()
        
        // Send initial navigation data
        updateAndSendNavigationData()
    }
    
    /// Stops the current navigation session.
    func stopNavigation() {
        navigationState = .idle
        routeSteps = []
        currentStepIndex = 0
        destination = nil
        destinationName = ""
        routePolylinePoints = []
        totalDistanceText = ""
        totalDurationText = ""
        estimatedArrival = ""
        currentNavData = .idle
        
        bleUpdateTimer?.invalidate()
        bleUpdateTimer = nil
        
        // Send idle state to ESP32
        bleManager?.sendNavigationData(.idle)
    }
    
    // MARK: - Directions Response Parsing
    
    /// Parses the Google Directions API JSON response into route steps.
    private func parseDirectionsResponse(data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { self.navigationState = .error("Invalid response format") }
                return
            }
            
            let status = json["status"] as? String
            guard status == "OK" else {
                let errorMsg = json["error_message"] as? String ?? "Route not found"
                DispatchQueue.main.async { self.navigationState = .error("Directions API: \(errorMsg)") }
                return
            }
            
            guard let routes = json["routes"] as? [[String: Any]],
                  let route = routes.first else {
                DispatchQueue.main.async { self.navigationState = .error("No routes found") }
                return
            }
            
            // Parse overview polyline for map display
            var polylinePoints: [CLLocationCoordinate2D] = []
            if let overviewPolyline = route["overview_polyline"] as? [String: Any],
               let encodedPath = overviewPolyline["points"] as? String {
                polylinePoints = decodePolyline(encodedPath)
            }
            
            // Parse legs (we only have one leg for single destination)
            guard let legs = route["legs"] as? [[String: Any]],
                  let leg = legs.first else {
                DispatchQueue.main.async { self.navigationState = .error("No route legs found") }
                return
            }
            
            let totalDistance = (leg["distance"] as? [String: Any])?["text"] as? String ?? ""
            let totalDuration = (leg["duration"] as? [String: Any])?["text"] as? String ?? ""
            
            // Calculate ETA
            let durationSeconds = (leg["duration"] as? [String: Any])?["value"] as? Int ?? 0
            let arrivalDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let etaString = formatter.string(from: arrivalDate)
            
            // Parse individual steps
            guard let stepsArray = leg["steps"] as? [[String: Any]] else {
                DispatchQueue.main.async { self.navigationState = .error("No route steps found") }
                return
            }
            
            var parsedSteps: [RouteStep] = []
            
            for (index, stepJson) in stepsArray.enumerated() {
                let maneuverString = stepJson["maneuver"] as? String ?? ""
                let maneuver: ManeuverType
                
                // Last step is arrival
                if index == stepsArray.count - 1 && maneuverString.isEmpty {
                    maneuver = .arrived
                } else {
                    maneuver = ManeuverType.from(googleManeuver: maneuverString)
                }
                
                let distanceInfo = stepJson["distance"] as? [String: Any] ?? [:]
                let durationInfo = stepJson["duration"] as? [String: Any] ?? [:]
                
                let startLoc = stepJson["start_location"] as? [String: Any] ?? [:]
                let endLoc = stepJson["end_location"] as? [String: Any] ?? [:]
                
                let htmlInstructions = stepJson["html_instructions"] as? String ?? ""
                let streetName = extractStreetName(from: htmlInstructions)
                
                let stepPolyline = (stepJson["polyline"] as? [String: Any])?["points"] as? String ?? ""
                
                let step = RouteStep(
                    maneuver: maneuver,
                    distanceText: distanceInfo["text"] as? String ?? "",
                    distanceValue: distanceInfo["value"] as? Int ?? 0,
                    durationText: durationInfo["text"] as? String ?? "",
                    durationValue: durationInfo["value"] as? Int ?? 0,
                    htmlInstructions: htmlInstructions,
                    streetName: streetName,
                    startLocation: CLLocationCoordinate2D(
                        latitude: startLoc["lat"] as? Double ?? 0,
                        longitude: startLoc["lng"] as? Double ?? 0
                    ),
                    endLocation: CLLocationCoordinate2D(
                        latitude: endLoc["lat"] as? Double ?? 0,
                        longitude: endLoc["lng"] as? Double ?? 0
                    ),
                    polyline: stepPolyline
                )
                
                parsedSteps.append(step)
            }
            
            DispatchQueue.main.async {
                self.routeSteps = parsedSteps
                self.routePolylinePoints = polylinePoints
                self.totalDistanceText = totalDistance
                self.totalDurationText = totalDuration
                self.estimatedArrival = etaString
                self.navigationState = .calculatingRoute // Ready to start
            }
            
        } catch {
            DispatchQueue.main.async {
                self.navigationState = .error("Failed to parse route: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Street Name Extraction
    
    /// Extracts the street name from Google Directions HTML instructions.
    /// HTML instructions typically look like: "Turn <b>left</b> onto <b>Main Street</b>"
    /// - Parameter html: The HTML instruction string.
    /// - Returns: The extracted street name, or "Unknown" if not found.
    private func extractStreetName(from html: String) -> String {
        // Find the last bold tag content (usually the street name)
        let pattern = "<b>([^<]+)</b>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "Unknown" }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        // The last <b>...</b> match is typically the street name
        if let lastMatch = matches.last,
           let range = Range(lastMatch.range(at: 1), in: html) {
            return String(html[range])
        }
        
        // Fallback: strip all HTML tags
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped.isEmpty ? "Unknown" : stripped
    }
    
    // MARK: - Polyline Decoding
    
    /// Decodes a Google Maps encoded polyline string into coordinates.
    /// - Parameter encoded: The encoded polyline string.
    /// - Returns: Array of decoded coordinates.
    private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat: Int32 = 0
        var lng: Int32 = 0
        
        while index < encoded.endIndex {
            // Decode latitude
            var result: Int32 = 0
            var shift: Int32 = 0
            var byte: Int32
            
            repeat {
                byte = Int32(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            
            let dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += dlat
            
            // Decode longitude
            result = 0
            shift = 0
            
            repeat {
                byte = Int32(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            
            let dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += dlng
            
            coordinates.append(CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            ))
        }
        
        return coordinates
    }
    
    // MARK: - Navigation Tracking
    
    /// Updates navigation data based on current location and sends it via BLE.
    private func updateAndSendNavigationData() {
        guard case .navigating = navigationState,
              !routeSteps.isEmpty,
              currentStepIndex < routeSteps.count else { return }
        
        let currentStep = routeSteps[currentStepIndex]
        let location = currentLocation
        
        // Calculate distance to the end of the current step
        let stepEndLocation = CLLocation(
            latitude: currentStep.endLocation.latitude,
            longitude: currentStep.endLocation.longitude
        )
        let distanceToStepEnd = location?.distance(from: stepEndLocation) ?? Double(currentStep.distanceValue)
        
        // Calculate remaining distance (sum of remaining steps)
        let remainingDistance = routeSteps[currentStepIndex...].reduce(0.0) { sum, step in
            sum + Double(step.distanceValue)
        }
        
        // Get current speed in km/h
        let speedKmh = max(0, (location?.speed ?? 0) * 3.6)
        
        // Calculate dynamic ETA based on remaining distance and current speed
        let eta: String
        if speedKmh > 0 {
            let remainingSeconds = (remainingDistance / 1000.0) / (speedKmh / 3600.0)
            let arrivalDate = Date().addingTimeInterval(remainingSeconds)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            eta = formatter.string(from: arrivalDate)
        } else {
            eta = estimatedArrival
        }
        
        // Get "then" maneuver (next step after current)
        let thenManeuver: String
        if currentStepIndex + 1 < routeSteps.count {
            thenManeuver = "THEN: \(routeSteps[currentStepIndex + 1].maneuver.rawValue)"
        } else {
            thenManeuver = "THEN: ARRIVED"
        }
        
        let navData = NavigationData(
            turn: currentStep.maneuver.rawValue,
            dist: distanceUnit.format(meters: distanceToStepEnd),
            street: currentStep.streetName,
            eta: eta,
            rem: distanceUnit.format(meters: remainingDistance),
            speed: round(speedKmh * 10) / 10,
            then: thenManeuver,
            lat: location?.coordinate.latitude ?? 0,
            lng: location?.coordinate.longitude ?? 0
        )
        
        DispatchQueue.main.async {
            self.currentNavData = navData
        }
        
        // Send to ESP32
        bleManager?.sendNavigationData(navData)
        lastBLEUpdate = Date()
    }
    
    /// Checks if the user has reached the current step's end location
    /// and advances to the next step if so.
    private func checkStepAdvancement(location: CLLocation) {
        guard case .navigating = navigationState,
              currentStepIndex < routeSteps.count else { return }
        
        let currentStep = routeSteps[currentStepIndex]
        let stepEndLocation = CLLocation(
            latitude: currentStep.endLocation.latitude,
            longitude: currentStep.endLocation.longitude
        )
        
        let distanceToEnd = location.distance(from: stepEndLocation)
        
        if distanceToEnd <= stepAdvanceThreshold {
            // Advance to next step
            if currentStepIndex + 1 < routeSteps.count {
                DispatchQueue.main.async {
                    self.currentStepIndex += 1
                }
                updateAndSendNavigationData()
            } else {
                // Arrived at destination
                DispatchQueue.main.async {
                    self.navigationState = .arrived
                    let arrivedData = NavigationData(
                        turn: ManeuverType.arrived.rawValue,
                        dist: "0 m",
                        street: self.destinationName,
                        eta: "--",
                        rem: "0 m",
                        speed: 0,
                        then: "",
                        lat: location.coordinate.latitude,
                        lng: location.coordinate.longitude
                    )
                    self.currentNavData = arrivedData
                    self.bleManager?.sendNavigationData(arrivedData)
                }
            }
        }
    }
    
    // MARK: - BLE Update Timer
    
    /// Starts a timer that sends BLE updates every 5 seconds.
    private func startBLEUpdateTimer() {
        bleUpdateTimer?.invalidate()
        bleUpdateTimer = Timer.scheduledTimer(withTimeInterval: bleUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateAndSendNavigationData()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension NavigationManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out inaccurate locations
        guard location.horizontalAccuracy <= 50 else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        // Check step advancement during active navigation
        if case .navigating = navigationState {
            checkStepAdvancement(location: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] Error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.navigationState = .error("Location permission denied. Enable in Settings.")
            }
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Legacy delegate method for older iOS versions
    }
}
