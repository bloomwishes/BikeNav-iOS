//
//  ContentView.swift
//  BikeNav
//
//  Tab-based main view containing the Map and Settings tabs.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var placesSearchManager: PlacesSearchManager
    
    var body: some View {
        TabView {
            // MARK: - Map Tab
            ZStack {
                MapView()
                    .edgesIgnoringSafeArea(.top)
                
                VStack(spacing: 0) {
                    // Search bar at the top
                    SearchView()
                    
                    Spacer()
                    
                    // Navigation overlay at the bottom
                    if case .navigating = navigationManager.navigationState {
                        NavigationOverlayView()
                    } else if case .arrived = navigationManager.navigationState {
                        NavigationOverlayView()
                    } else if !navigationManager.routeSteps.isEmpty {
                        // Route calculated, show start button
                        startNavigationCard
                    }
                }
            }
            .tabItem {
                Label("Navigate", systemImage: "map.fill")
            }
            
            // MARK: - Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.blue)
    }
    
    // MARK: - Start Navigation Card
    
    /// Card shown after route is calculated, before navigation starts.
    private var startNavigationCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(navigationManager.destinationName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 16) {
                        Label(navigationManager.totalDistanceText, systemImage: "arrow.left.arrow.right")
                        Label(navigationManager.totalDurationText, systemImage: "clock")
                        Label("ETA \(navigationManager.estimatedArrival)", systemImage: "flag")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // BLE connection indicator
                Circle()
                    .fill(bleManager.connectionState == .connected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    navigationManager.stopNavigation()
                }
                .buttonStyle(.bordered)
                
                Button("Start Navigation") {
                    navigationManager.startNavigation()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 8)
        .padding()
    }
}
