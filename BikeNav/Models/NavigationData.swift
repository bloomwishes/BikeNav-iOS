//
//  NavigationData.swift
//  BikeNav
//
//  Data models for navigation data sent to the ESP32 via BLE.
//  Defines the maneuver types and the JSON payload structure.
//

import Foundation
import CoreLocation

// MARK: - Maneuver Type

/// Represents the type of navigation maneuver, mapped from Google Directions API maneuver strings.
enum ManeuverType: String, Codable, CaseIterable {
    case left = "LEFT"
    case right = "RIGHT"
    case straight = "STRAIGHT"
    case slightLeft = "SLIGHT_LEFT"
    case slightRight = "SLIGHT_RIGHT"
    case sharpLeft = "SHARP_LEFT"
    case sharpRight = "SHARP_RIGHT"
    case uturn = "UTURN"
    case roundabout = "ROUNDABOUT"
    case arrived = "ARRIVED"
    case idle = "IDLE"
    
    /// Maps a Google Directions API maneuver string to a ManeuverType.
    /// - Parameter googleManeuver: The maneuver string from the Google Directions API response.
    /// - Returns: The corresponding ManeuverType.
    static func from(googleManeuver: String) -> ManeuverType {
        switch googleManeuver.lowercased() {
        case "turn-left":
            return .left
        case "turn-right":
            return .right
        case "turn-slight-left":
            return .slightLeft
        case "turn-slight-right":
            return .slightRight
        case "turn-sharp-left":
            return .sharpLeft
        case "turn-sharp-right":
            return .sharpRight
        case "uturn-left", "uturn-right":
            return .uturn
        case "roundabout-left", "roundabout-right":
            return .roundabout
        case "straight", "merge", "fork-left", "fork-right":
            return .straight
        case "":
            return .arrived
        default:
            return .straight
        }
    }
    
    /// SF Symbol name for displaying maneuver icons in the UI.
    var iconName: String {
        switch self {
        case .left:
            return "arrow.turn.up.left"
        case .right:
            return "arrow.turn.up.right"
        case .straight:
            return "arrow.up"
        case .slightLeft:
            return "arrow.up.left"
        case .slightRight:
            return "arrow.up.right"
        case .sharpLeft:
            return "arrow.turn.down.left"
        case .sharpRight:
            return "arrow.turn.down.right"
        case .uturn:
            return "arrow.uturn.down"
        case .roundabout:
            return "arrow.triangle.turnup.right.circle"
        case .arrived:
            return "flag.checkered"
        case .idle:
            return "location.circle"
        }
    }
}

// MARK: - Navigation Data

/// The navigation data payload sent to the ESP32 over BLE.
/// Encoded as a JSON string, max 512 bytes.
struct NavigationData: Codable, Equatable {
    /// Current maneuver type
    let turn: String
    /// Distance to the next turn (e.g., "200 m" or "0.5 mi")
    let dist: String
    /// Name of the upcoming street
    let street: String
    /// Estimated time of arrival (e.g., "12:30")
    let eta: String
    /// Remaining distance to destination (e.g., "5.2 km")
    let rem: String
    /// Current speed in km/h
    let speed: Double
    /// Preview of the maneuver after the next one (e.g., "THEN: RIGHT")
    let then: String
    /// Current latitude
    let lat: Double
    /// Current longitude
    let lng: Double
    
    /// Creates idle navigation data with no active route.
    static var idle: NavigationData {
        NavigationData(
            turn: ManeuverType.idle.rawValue,
            dist: "--",
            street: "--",
            eta: "--",
            rem: "--",
            speed: 0.0,
            then: "",
            lat: 0.0,
            lng: 0.0
        )
    }
    
    /// Encodes the navigation data to a JSON string suitable for BLE transmission.
    /// Truncates to 512 bytes if necessary.
    /// - Returns: A UTF-8 JSON string, or nil if encoding fails.
    func toBLEData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // Compact JSON
        guard let jsonData = try? encoder.encode(self) else { return nil }
        
        // Enforce 512-byte BLE limit
        if jsonData.count > 512 {
            // Truncate street name to fit within the limit
            var truncated = self
            let overflow = jsonData.count - 512
            let currentStreet = truncated.street
            let maxStreetLen = max(0, currentStreet.count - overflow - 10)
            truncated = NavigationData(
                turn: turn,
                dist: dist,
                street: String(currentStreet.prefix(maxStreetLen)) + "...",
                eta: eta,
                rem: rem,
                speed: speed,
                then: then,
                lat: lat,
                lng: lng
            )
            return try? encoder.encode(truncated)
        }
        
        return jsonData
    }
}

// MARK: - Route Step

/// Represents a single step in a navigation route, parsed from Google Directions API.
struct RouteStep {
    /// The maneuver type for this step
    let maneuver: ManeuverType
    /// Human-readable distance text (e.g., "200 m")
    let distanceText: String
    /// Distance in meters
    let distanceValue: Int
    /// Human-readable duration text (e.g., "2 mins")
    let durationText: String
    /// Duration in seconds
    let durationValue: Int
    /// HTML instructions from Google Directions API
    let htmlInstructions: String
    /// Street name extracted from instructions
    let streetName: String
    /// Start coordinate of this step
    let startLocation: CLLocationCoordinate2D
    /// End coordinate of this step
    let endLocation: CLLocationCoordinate2D
    /// Encoded polyline for this step
    let polyline: String
}

// MARK: - Distance Unit Preference

/// User preference for distance units.
enum DistanceUnit: String, CaseIterable {
    case metric = "Metric (km)"
    case imperial = "Imperial (mi)"
    
    /// Formats a distance in meters to the preferred unit.
    /// - Parameter meters: Distance in meters.
    /// - Returns: Formatted distance string.
    func format(meters: Double) -> String {
        switch self {
        case .metric:
            if meters < 1000 {
                return "\(Int(meters)) m"
            } else {
                return String(format: "%.1f km", meters / 1000.0)
            }
        case .imperial:
            let feet = meters * 3.28084
            if feet < 5280 {
                return "\(Int(feet)) ft"
            } else {
                return String(format: "%.1f mi", feet / 5280.0)
            }
        }
    }
}
