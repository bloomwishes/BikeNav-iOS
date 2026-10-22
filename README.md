# BikeNav iOS — Turn-by-Turn Navigation & BLE Transmitter

BikeNav is a dedicated SwiftUI iOS app that calculates bicycle routes using the **Google Maps SDK** and **Google Directions API**, tracks real-time progress using CoreLocation, and transmits turn-by-turn navigation data directly to an ESP32 handlebar display over **Bluetooth Low Energy (BLE)**.

---

## 🌟 Key Features

- **Google Maps & Directions**:
  - Live vector map with route polyline overlay
  - Dynamic camera tracking following user heading & location
  - Destination marker and bounds auto-framing
  - Bicycling navigation route mode
- **Google Places Autocomplete**:
  - Search destinations as you type with debounced queries
  - Location coordinates and structured address extraction
- **Real-Time Step Tracking**:
  - GPS-based step advancement (within 30m of step waypoint)
  - Turn maneuver extraction (Left, Right, Slight/Sharp, U-Turn, Roundabout, etc.)
  - Next maneuver preview (`"THEN: RIGHT"`)
  - Distance to next turn, dynamic ETA, remaining distance, and current speed
- **CoreBluetooth BLE Transmitter**:
  - Auto-discovers and connects to `BikeNav-BLE` ESP32 device
  - Automatic reconnection with exponential backoff
  - Background BLE central execution support
  - 512-byte compact JSON payload transmission

---

## 📁 Project Structure

```
BikeNav_iOS/
├── Podfile                          # CocoaPods dependencies (GoogleMaps, GooglePlaces)
├── README.md                        # Documentation and setup guide
└── BikeNav/
    ├── BikeNavApp.swift             # App entry point & GMSServices initialization
    ├── Info.plist                   # Permissions (Location, Bluetooth, Background modes)
    ├── Models/
    │   └── NavigationData.swift     # Codable models, ManeuverType, RouteStep
    ├── Services/
    │   ├── BLEManager.swift         # CoreBluetooth CBCentralManager & CBPeripheralDelegate
    │   ├── NavigationManager.swift  # Route calculation, CLLocationManager, step tracker
    │   └── PlacesSearchManager.swift# Google Places Autocomplete search engine
    └── Views/
        ├── ContentView.swift        # Main TabView (Navigate, Settings)
        ├── MapView.swift            # GMSMapView UIViewRepresentable with polyline & marker
        ├── SearchView.swift         # Search bar and autocomplete results dropdown
        ├── NavigationOverlayView.swift # Live turn cards, ETA, distance, speed & controls
        ├── SettingsView.swift       # API Key entry, BLE scan controls, distance unit
        └── BLEStatusView.swift      # Signal strength RSSI bars and connection status
```

---

## 🛰 BLE Communication Protocol

### Service & Characteristics UUIDs

| Name | UUID | Type | Properties |
| :--- | :--- | :--- | :--- |
| **Service** | `12345678-1234-1234-1234-123456789ABC` | Primary | - |
| **Navigation** | `12345678-1234-1234-1234-123456789ABD` | Characteristic | Write / Write Without Response / Notify |
| **Status** | `12345678-1234-1234-1234-123456789ABE` | Characteristic | Read / Notify |

### JSON Payload Sent to ESP32

```json
{
  "turn": "LEFT",
  "dist": "200 m",
  "street": "Palakkad Main Rd",
  "eta": "14:45",
  "rem": "4.8 km",
  "speed": 22.5,
  "then": "THEN: RIGHT",
  "lat": 10.7867,
  "lng": 76.6548
}
```

### Maneuver Types Supported

| `turn` String | Display Icon on ESP32 | Description |
| :--- | :--- | :--- |
| `LEFT` | ⬅️ Left Arrow | Turn left |
| `RIGHT` | ➡️ Right Arrow | Turn right |
| `SLIGHT_LEFT` | ↖️ Slight Left | Bear / keep left |
| `SLIGHT_RIGHT`| ↗️ Slight Right | Bear / keep right |
| `SHARP_LEFT`  | ↙️ Sharp Left | Sharp turn left |
| `SHARP_RIGHT` | ↘️ Sharp Right | Sharp turn right |
| `STRAIGHT`    | ⬆️ Straight Arrow | Continue straight |
| `UTURN`       | ↩️ U-Turn Arrow | Make a U-turn |
| `ROUNDABOUT`  | 🔄 Roundabout | Enter/navigate roundabout |
| `ARRIVED`     | 🏁 Checkered Flag | Destination reached |
| `IDLE`        | ℹ️ Logo / Idle | Waiting for navigation |

---

## ⚙️ Prerequisites & Setup

### 1. Google Cloud Console API Keys
1. Go to [Google Cloud Console](https://console.cloud.google.com/).
2. Create or select a project.
3. Enable the following APIs:
   - **Maps SDK for iOS**
   - **Places API**
   - **Directions API**
4. Create an API Key in **Credentials**.
5. (Optional but recommended) Restrict the API key to iOS apps with your Bundle Identifier (e.g., `com.bikenav.app`).

### 2. Opening in Xcode

You can set up the Xcode project in 2 minutes:

1. Open **Xcode** on your Mac.
2. Select **File > New > Project...** -> Choose **iOS > App**.
3. Name it **BikeNav**, Interface: **SwiftUI**, Language: **Swift**, Bundle Identifier: e.g. `com.yourname.BikeNav`.
4. Save the project inside `BikeNav_iOS/` (or drag the provided `BikeNav` source folder into your new Xcode project).
5. Close Xcode.
6. In Terminal, navigate to `BikeNav_iOS/`:
   ```bash
   cd BikeNav_iOS
   pod install
   ```
7. Open the generated workspace:
   ```bash
   open BikeNav.xcworkspace
   ```

### 3. Configure App in Xcode
- In the project target's **Signing & Capabilities**:
  - Select your Apple Developer Team.
  - Add **Background Modes**: Check **Location updates** and **Uses Bluetooth LE accessories**.
- The provided `Info.plist` already includes the required permission keys:
  - `NSLocationWhenInUseUsageDescription`
  - `NSLocationAlwaysAndWhenInUseUsageDescription`
  - `NSBluetoothAlwaysUsageDescription`
  - `NSBluetoothPeripheralUsageDescription`

### 4. Running the App
1. Build and run on a physical iPhone (CoreBluetooth peripheral scanning requires a real device, not simulator).
2. On first launch, open the **Settings** tab.
3. Paste your **Google Maps API Key**.
4. Power on your ESP32 running `ESP32_BLE_BikeNav`.
5. Tap **Scan for Device** — the app will pair with `BikeNav-BLE` automatically.
6. Switch to the **Navigate** tab, search for a destination, tap **Start Navigation**, and watch turn-by-turn guidance update live on both your iPhone and the round ESP32 display!
