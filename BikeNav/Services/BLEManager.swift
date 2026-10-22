//
//  BLEManager.swift
//  BikeNav
//
//  CoreBluetooth central manager for ESP32 BLE communication.
//  Handles scanning, connecting, auto-reconnecting, and writing navigation data.
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Constants

/// BLE service and characteristic UUIDs for the ESP32 BikeNav device.
enum BLEConstants {
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    static let navigationCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")
    static let statusCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABE")
    static let deviceName = "BikeNav-BLE"
}

// MARK: - BLE Connection State

/// Represents the current BLE connection state.
enum BLEConnectionState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected"
    case reconnecting = "Reconnecting..."
    case bluetoothOff = "Bluetooth Off"
    case unauthorized = "Unauthorized"
    
    /// Color name for the connection state indicator.
    var colorName: String {
        switch self {
        case .connected: return "green"
        case .scanning, .connecting, .reconnecting: return "orange"
        case .disconnected, .bluetoothOff, .unauthorized: return "red"
        }
    }
}

// MARK: - BLEManager

/// Manages BLE communication with the ESP32 BikeNav device.
/// Publishes connection state and handles auto-reconnection with exponential backoff.
class BLEManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current BLE connection state
    @Published var connectionState: BLEConnectionState = .disconnected
    
    /// Signal strength (RSSI) of the connected device
    @Published var signalStrength: Int = 0
    
    /// Timestamp of the last data sent to the device
    @Published var lastDataSentTimestamp: Date?
    
    /// Error message for display
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var navigationCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    
    /// Auto-reconnect settings
    private var shouldAutoReconnect = true
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10
    private var reconnectTimer: Timer?
    
    /// RSSI polling timer
    private var rssiTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil,
                                          options: [CBCentralManagerOptionRestoreIdentifierKey: "BikeNavBLECentral"])
    }
    
    // MARK: - Public Methods
    
    /// Starts scanning for the ESP32 BikeNav device.
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionState = .bluetoothOff
            return
        }
        
        connectionState = .scanning
        reconnectAttempt = 0
        
        // Scan for peripherals advertising our service UUID
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Timeout scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, self.connectionState == .scanning else { return }
            self.centralManager.stopScan()
            self.connectionState = .disconnected
            self.errorMessage = "Device not found. Make sure BikeNav-BLE is powered on."
        }
    }
    
    /// Stops scanning for devices.
    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }
    
    /// Disconnects from the current device.
    func disconnect() {
        shouldAutoReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        rssiTimer?.invalidate()
        rssiTimer = nil
        
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        connectedPeripheral = nil
        navigationCharacteristic = nil
        statusCharacteristic = nil
        connectionState = .disconnected
    }
    
    /// Sends navigation data to the ESP32 over BLE.
    /// - Parameter data: The navigation data to send.
    func sendNavigationData(_ data: NavigationData) {
        guard let characteristic = navigationCharacteristic,
              let peripheral = connectedPeripheral,
              connectionState == .connected else {
            return
        }
        
        guard let bleData = data.toBLEData() else {
            errorMessage = "Failed to encode navigation data"
            return
        }
        
        // Write with response to ensure delivery
        peripheral.writeValue(bleData, for: characteristic, type: .withResponse)
        
        DispatchQueue.main.async {
            self.lastDataSentTimestamp = Date()
        }
    }
    
    // MARK: - Private Methods
    
    /// Attempts to reconnect with exponential backoff.
    private func attemptReconnect() {
        guard shouldAutoReconnect, reconnectAttempt < maxReconnectAttempts else {
            connectionState = .disconnected
            errorMessage = "Auto-reconnect failed after \(maxReconnectAttempts) attempts."
            return
        }
        
        connectionState = .reconnecting
        reconnectAttempt += 1
        
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s... capped at 30s
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 30.0)
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Try reconnecting to the known peripheral first
            if let peripheral = self.connectedPeripheral {
                self.centralManager.connect(peripheral, options: nil)
            } else {
                // Fall back to scanning
                self.startScanning()
            }
        }
    }
    
    /// Starts periodic RSSI reading from the connected peripheral.
    private func startRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.connectedPeripheral?.readRSSI()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // If we were previously connected, try to reconnect
            if connectionState == .bluetoothOff || connectionState == .reconnecting {
                startScanning()
            }
        case .poweredOff:
            connectionState = .bluetoothOff
            connectedPeripheral = nil
            navigationCharacteristic = nil
            statusCharacteristic = nil
        case .unauthorized:
            connectionState = .unauthorized
            errorMessage = "Bluetooth permission denied. Enable in Settings."
        case .unsupported:
            connectionState = .disconnected
            errorMessage = "Bluetooth LE is not supported on this device."
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        // Verify device name matches
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name == BLEConstants.deviceName else { return }
        
        // Stop scanning and connect
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        reconnectAttempt = 0
        shouldAutoReconnect = true
        errorMessage = nil
        
        // Discover our service
        peripheral.discoverServices([BLEConstants.serviceUUID])
        
        // Start RSSI monitoring
        startRSSIMonitoring()
        peripheral.readRSSI()
    }
    
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        errorMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        attemptReconnect()
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        navigationCharacteristic = nil
        statusCharacteristic = nil
        rssiTimer?.invalidate()
        
        if shouldAutoReconnect {
            attemptReconnect()
        } else {
            connectionState = .disconnected
        }
    }
    
    /// State restoration for background BLE
    func centralManager(_ central: CBCentralManager,
                        willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            connectedPeripheral = peripheral
            peripheral.delegate = self
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            errorMessage = "Service discovery failed: \(error!.localizedDescription)"
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services where service.uuid == BLEConstants.serviceUUID {
            peripheral.discoverCharacteristics([
                BLEConstants.navigationCharacteristicUUID,
                BLEConstants.statusCharacteristicUUID
            ], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            errorMessage = "Characteristic discovery failed: \(error!.localizedDescription)"
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEConstants.navigationCharacteristicUUID:
                navigationCharacteristic = characteristic
            case BLEConstants.statusCharacteristicUUID:
                statusCharacteristic = characteristic
                // Subscribe to status notifications from ESP32
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        // Handle status updates from ESP32 if needed
        if characteristic.uuid == BLEConstants.statusCharacteristicUUID,
           let data = characteristic.value,
           let status = String(data: data, encoding: .utf8) {
            print("[BLE] Status update from ESP32: \(status)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            print("[BLE] Write error: \(error.localizedDescription)")
            errorMessage = "BLE write failed: \(error.localizedDescription)"
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil {
            DispatchQueue.main.async {
                self.signalStrength = RSSI.intValue
            }
        }
    }
}
