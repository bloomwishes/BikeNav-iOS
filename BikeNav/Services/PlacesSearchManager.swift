//
//  PlacesSearchManager.swift
//  BikeNav
//
//  Google Places Autocomplete integration for destination search.
//  Provides debounced search-as-you-type with place details.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Place Result

/// Represents a place autocomplete result.
struct PlaceResult: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    
    static func == (lhs: PlaceResult, rhs: PlaceResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Autocomplete Prediction

/// Intermediate model for autocomplete predictions (before coordinate lookup).
private struct AutocompletePrediction: Decodable {
    let placeId: String
    let description: String
    let structuredFormatting: StructuredFormatting?
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case description
        case structuredFormatting = "structured_formatting"
    }
    
    struct StructuredFormatting: Decodable {
        let mainText: String
        let secondaryText: String?
        
        enum CodingKeys: String, CodingKey {
            case mainText = "main_text"
            case secondaryText = "secondary_text"
        }
    }
}

// MARK: - PlacesSearchManager

/// Manages Google Places Autocomplete searches with debounced input.
class PlacesSearchManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current search query text
    @Published var searchText: String = ""
    
    /// Autocomplete search results
    @Published var searchResults: [PlaceResult] = []
    
    /// Whether a search is in progress
    @Published var isSearching: Bool = false
    
    /// Error message for display
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let session = URLSession.shared
    
    /// Google Maps API key from UserDefaults
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "googleMapsAPIKey") ?? ""
    }
    
    // MARK: - Initialization
    
    init() {
        setupDebouncing()
    }
    
    // MARK: - Debounced Search Setup
    
    /// Sets up a debounced publisher on searchText to avoid excessive API calls.
    private func setupDebouncing() {
        $searchText
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.count >= 2 {
                    self.performAutocomplete(query: query)
                } else {
                    self.searchResults = []
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Autocomplete Search
    
    /// Performs a Google Places Autocomplete search.
    /// - Parameter query: The search query string.
    private func performAutocomplete(query: String) {
        guard !apiKey.isEmpty else {
            errorMessage = "Google Maps API key not set. Go to Settings to add it."
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
            + "?input=\(encodedQuery)"
            + "&types=geocode|establishment"
            + "&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            isSearching = false
            errorMessage = "Invalid search URL"
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSearching = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Search failed: \(error.localizedDescription)"
                }
                return
            }
            
            guard let data = data else { return }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let status = json?["status"] as? String
                
                guard status == "OK" || status == "ZERO_RESULTS" else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Places API error: \(status ?? "Unknown")"
                    }
                    return
                }
                
                let predictions = json?["predictions"] as? [[String: Any]] ?? []
                
                // Fetch details for each prediction to get coordinates
                let group = DispatchGroup()
                var results: [PlaceResult] = []
                
                for prediction in predictions.prefix(5) {
                    guard let placeId = prediction["place_id"] as? String,
                          let description = prediction["description"] as? String else { continue }
                    
                    let structuredFormatting = prediction["structured_formatting"] as? [String: Any]
                    let name = structuredFormatting?["main_text"] as? String ?? description
                    
                    group.enter()
                    self?.fetchPlaceDetails(placeId: placeId) { coordinate in
                        if let coordinate = coordinate {
                            results.append(PlaceResult(
                                id: placeId,
                                name: name,
                                address: description,
                                coordinate: coordinate
                            ))
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    self?.searchResults = results
                }
                
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse search results"
                }
            }
        }.resume()
    }
    
    // MARK: - Place Details
    
    /// Fetches coordinate details for a place ID.
    /// - Parameters:
    ///   - placeId: The Google Place ID.
    ///   - completion: Callback with the coordinate, or nil on failure.
    private func fetchPlaceDetails(placeId: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let urlString = "https://maps.googleapis.com/maps/api/place/details/json"
            + "?place_id=\(placeId)"
            + "&fields=geometry"
            + "&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let result = json?["result"] as? [String: Any]
                let geometry = result?["geometry"] as? [String: Any]
                let location = geometry?["location"] as? [String: Any]
                
                if let lat = location?["lat"] as? Double,
                   let lng = location?["lng"] as? Double {
                    completion(CLLocationCoordinate2D(latitude: lat, longitude: lng))
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - Clear Results
    
    /// Clears the search results and query text.
    func clearSearch() {
        searchText = ""
        searchResults = []
        errorMessage = nil
    }
}
