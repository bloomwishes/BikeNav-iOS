//
//  NavigationOverlayView.swift
//  BikeNav
//
//  Overlay displayed on the map during active navigation.
//  Shows current maneuver, distance, street, ETA, BLE status, and controls.
//

import SwiftUI

struct NavigationOverlayView: View {
    
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Maneuver Card
            maneuverCard
            
            // MARK: - Info Bar
            infoBar
            
            // MARK: - Controls
            controlsBar
        }
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 8)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Maneuver Card
    
    /// Main card showing the current turn direction and distance.
    private var maneuverCard: some View {
        HStack(spacing: 16) {
            // Maneuver icon
            let maneuver = ManeuverType(rawValue: navigationManager.currentNavData.turn) ?? .idle
            
            Image(systemName: maneuver.iconName)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(maneuverBackgroundColor(maneuver))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                // Distance to next turn
                Text(navigationManager.currentNavData.dist)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                // Street name
                Text(navigationManager.currentNavData.street)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                // Then maneuver preview
                if !navigationManager.currentNavData.then.isEmpty {
                    Text(navigationManager.currentNavData.then)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // BLE status indicator
            VStack(spacing: 4) {
                Image(systemName: bleStatusIcon)
                    .font(.title3)
                    .foregroundColor(bleStatusColor)
                
                Text(bleManager.connectionState == .connected ? "BLE" : "No BLE")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Info Bar
    
    /// Bar showing ETA, remaining distance, and speed.
    private var infoBar: some View {
        HStack(spacing: 0) {
            infoItem(icon: "clock.fill", value: navigationManager.currentNavData.eta, label: "ETA")
            
            Divider().frame(height: 30)
            
            infoItem(icon: "arrow.left.arrow.right", value: navigationManager.currentNavData.rem, label: "Remaining")
            
            Divider().frame(height: 30)
            
            infoItem(icon: "speedometer", value: String(format: "%.0f", navigationManager.currentNavData.speed), label: "km/h")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
    }
    
    /// Individual info item in the info bar.
    private func infoItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Controls Bar
    
    /// Navigation control buttons.
    private var controlsBar: some View {
        HStack(spacing: 16) {
            if case .arrived = navigationManager.navigationState {
                Button {
                    navigationManager.stopNavigation()
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    navigationManager.stopNavigation()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - BLE Status Helpers
    
    /// Icon for the current BLE connection state.
    private var bleStatusIcon: String {
        switch bleManager.connectionState {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .scanning, .connecting, .reconnecting: return "antenna.radiowaves.left.and.right.slash"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }
    
    /// Color for the current BLE connection state.
    private var bleStatusColor: Color {
        switch bleManager.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .reconnecting: return .orange
        default: return .red
        }
    }
    
    /// Background color for the maneuver icon based on type.
    private func maneuverBackgroundColor(_ maneuver: ManeuverType) -> Color {
        switch maneuver {
        case .arrived: return .green
        case .uturn: return .red
        case .idle: return .gray
        default: return .blue
        }
    }
}
