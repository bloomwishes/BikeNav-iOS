//
//  SettingsView.swift
//  BikeNav
//
//  Settings screen for BLE connection, API key configuration,
//  and distance unit preferences.
//

import SwiftUI

struct SettingsView: View {
    
    @EnvironmentObject var bleManager: BLEManager
    
    /// Google Maps API key stored in UserDefaults
    @AppStorage("googleMapsAPIKey") private var apiKey: String = ""
    
    /// Distance unit preference
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.metric.rawValue
    
    /// Controls API key secure entry visibility
    @State private var showAPIKey: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - BLE Device Section
                Section {
                    BLEStatusView()
                    
                    HStack {
                        Button {
                            if bleManager.connectionState == .connected {
                                bleManager.disconnect()
                            } else {
                                bleManager.startScanning()
                            }
                        } label: {
                            Label(
                                bleManager.connectionState == .connected ? "Disconnect" : "Scan for Device",
                                systemImage: bleManager.connectionState == .connected
                                    ? "antenna.radiowaves.left.and.right.slash"
                                    : "antenna.radiowaves.left.and.right"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(bleManager.connectionState == .connected ? .red : .blue)
                    }
                    
                    if let error = bleManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("ESP32 BikeNav Device")
                } footer: {
                    Text("Make sure your BikeNav-BLE device is powered on and nearby.")
                }
                
                // MARK: - API Key Section
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("Enter Google Maps API Key", text: $apiKey)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Enter Google Maps API Key", text: $apiKey)
                                .textFieldStyle(.plain)
                        }
                        
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if apiKey.isEmpty {
                        Label("API key required for Maps and Directions", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Label("API key saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Google Maps API Key")
                } footer: {
                    Text("Required: Maps SDK for iOS, Places API, and Directions API must be enabled in your Google Cloud Console project.")
                }
                
                // MARK: - Distance Unit Section
                Section {
                    Picker("Distance Unit", selection: $distanceUnit) {
                        ForEach(DistanceUnit.allCases, id: \.rawValue) { unit in
                            Text(unit.rawValue).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Preferences")
                }
                
                // MARK: - About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("BLE Protocol")
                        Spacer()
                        Text("JSON / 512 bytes")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Navigation Mode")
                        Spacer()
                        Text("Bicycling")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About BikeNav")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
