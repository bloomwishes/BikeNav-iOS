//
//  SearchView.swift
//  BikeNav
//
//  Search bar with autocomplete results list for destination selection.
//  Tapping a result calculates a route to that destination.
//

import SwiftUI

struct SearchView: View {
    
    @EnvironmentObject var placesSearchManager: PlacesSearchManager
    @EnvironmentObject var navigationManager: NavigationManager
    
    /// Controls whether the search results list is visible
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search destination...", text: $placesSearchManager.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onTapGesture {
                        isExpanded = true
                    }
                
                if !placesSearchManager.searchText.isEmpty {
                    Button {
                        placesSearchManager.clearSearch()
                        isExpanded = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                if placesSearchManager.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // MARK: - Error Message
            if let error = placesSearchManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            
            // MARK: - Autocomplete Results
            if isExpanded && !placesSearchManager.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(placesSearchManager.searchResults) { result in
                            Button {
                                selectPlace(result)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text(result.address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.turn.down.right")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Actions
    
    /// Selects a place result and triggers route calculation.
    private func selectPlace(_ place: PlaceResult) {
        placesSearchManager.searchText = place.name
        isExpanded = false
        
        // Calculate route to this destination
        navigationManager.calculateRoute(to: place.coordinate, name: place.name)
    }
}
