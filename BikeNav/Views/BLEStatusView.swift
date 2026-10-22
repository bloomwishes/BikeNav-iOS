//
//  BLEStatusView.swift
//  BikeNav
//
//  Displays the ESP32 BLE connection state, signal strength,
//  and last data sent timestamp.
//

import SwiftUI

struct BLEStatusView: View {
    
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Connection State
            HStack {
                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 3)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("BikeNav-BLE")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(bleManager.connectionState.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Scanning animation
                if bleManager.connectionState == .scanning ||
                   bleManager.connectionState == .reconnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // MARK: - Signal Strength
            if bleManager.connectionState == .connected {
                HStack(spacing: 16) {
                    // Signal bars
                    HStack(spacing: 2) {
                        signalBar(height: 6, filled: bleManager.signalStrength > -90)
                        signalBar(height: 10, filled: bleManager.signalStrength > -80)
                        signalBar(height: 14, filled: bleManager.signalStrength > -70)
                        signalBar(height: 18, filled: bleManager.signalStrength > -60)
                    }
                    
                    Text("\(bleManager.signalStrength) dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Signal quality label
                    Text(signalQualityLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(signalQualityColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(signalQualityColor.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            
            // MARK: - Last Data Sent
            if let lastSent = bleManager.lastDataSentTimestamp {
                HStack {
                    Image(systemName: "arrow.up.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Last sent: \(lastSent, formatter: timestampFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Signal Bar
    
    /// Individual signal strength bar.
    private func signalBar(height: CGFloat, filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(filled ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 4, height: height)
    }
    
    // MARK: - Computed Properties
    
    /// Color for the connection status indicator.
    private var statusColor: Color {
        switch bleManager.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .reconnecting: return .orange
        default: return .red
        }
    }
    
    /// Human-readable signal quality label.
    private var signalQualityLabel: String {
        let rssi = bleManager.signalStrength
        if rssi > -60 { return "Excellent" }
        if rssi > -70 { return "Good" }
        if rssi > -80 { return "Fair" }
        return "Weak"
    }
    
    /// Color for the signal quality label.
    private var signalQualityColor: Color {
        let rssi = bleManager.signalStrength
        if rssi > -60 { return .green }
        if rssi > -70 { return .blue }
        if rssi > -80 { return .orange }
        return .red
    }
    
    /// Formatter for the last sent timestamp.
    private var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}
