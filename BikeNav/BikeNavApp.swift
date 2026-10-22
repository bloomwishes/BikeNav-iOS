//
//  BikeNavApp.swift
//  BikeNav
//
//  Main entry point for the BikeNav application.
//  Initializes Google Maps SDK and sets up the app environment.
//

import SwiftUI
import GoogleMaps

@main
struct BikeNavApp: App {
    
    // MARK: - State Objects
    
    /// BLE manager for ESP32 communication
    @StateObject private var bleManager = BLEManager()
    
    /// Navigation manager for route tracking
    @StateObject private var navigationManager = NavigationManager()
    
    /// Places search manager for destination search
    @StateObject private var placesSearchManager = PlacesSearchManager()
    
    // MARK: - Initialization
    
    init() {
        // Initialize Google Maps SDK with stored API key
        let apiKey = UserDefaults.standard.string(forKey: "googleMapsAPIKey") ?? ""
        if !apiKey.isEmpty {
            GMSServices.provideAPIKey(apiKey)
        }
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(navigationManager)
                .environmentObject(placesSearchManager)
                .onAppear {
                    // Link navigation manager to BLE manager for data forwarding
                    navigationManager.bleManager = bleManager
                }
        }
    }
}
