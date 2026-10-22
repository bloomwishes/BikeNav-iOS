# ESP32 BLE BikeNav Display

Standalone BLE receiver for turn-by-turn bike navigation. Receives real-time navigation data from the **BikeNav iOS app** via Bluetooth Low Energy and renders it on a GC9A01 240×240 round TFT display.

**No WiFi · No WebServer · No ANCS · Pure BLE only** — minimal, clean, and battery-friendly.

---

## Hardware Wiring

| GC9A01 Pin | ESP32 GPIO | Label |
|------------|------------|-------|
| SCL        | GPIO 15    | D15   |
| SDA        | GPIO 2     | D2    |
| DC         | GPIO 4     | D4    |
| CS         | GPIO 16    | D16   |
| RST        | GPIO 17    | D17   |
| VCC        | 3.3V       | —     |
| GND        | GND        | —     |

---

## Required Libraries

Install these via the Arduino Library Manager:

| Library       | Version | Purpose                           |
|---------------|---------|-----------------------------------|
| **LovyanGFX** | ≥ 1.1   | High-performance GC9A01 driver    |
| **ArduinoJson**| ≥ 7.0  | JSON parsing for nav data         |

> **ESP32 BLE** is built-in with the ESP32 Arduino board package (no extra install needed).

### Board Setup

1. In Arduino IDE → **Tools → Board**, select **ESP32 Dev Module** (or your specific board)
2. Partition Scheme: **Default 4MB with spiffs** or **Huge APP (3MB)**
3. Upload Speed: **921600**

---

## How It Works

```
┌─────────────┐     BLE JSON      ┌──────────────────┐
│  BikeNav    │ ──────────────────>│   ESP32          │
│  iOS App    │                    │   BLE Server     │
│             │<───── Status ──────│   "BikeNav-BLE"  │
└─────────────┘                    │                  │
                                   │   ┌──────────┐   │
                                   │   │ GC9A01   │   │
                                   │   │ 240x240  │   │
                                   │   │ Round TFT│   │
                                   │   └──────────┘   │
                                   └──────────────────┘
```

### Pairing with BikeNav iOS App

1. **Power on** the ESP32 — the display shows `BIKENAV BLE` with `BLE ADVERTISING...`
2. Open the **BikeNav iOS app**
3. The app scans for BLE devices and connects to **"BikeNav-BLE"**
4. Once connected, the display shows `BLE CONNECTED` and `START NAVIGATION`
5. Start navigation in the app — turn-by-turn directions appear on the display in real time

---

## BLE Protocol Specification

### Service & Characteristics

| Item                       | UUID                                     |
|----------------------------|------------------------------------------|
| **Service**                | `12345678-1234-1234-1234-123456789ABC`   |
| **Navigation Characteristic** | `12345678-1234-1234-1234-123456789ABD` |
| **Status Characteristic**  | `12345678-1234-1234-1234-123456789ABE`   |

### Navigation Characteristic (Write + Notify)

The iOS app writes JSON data to this characteristic:

```json
{
  "turn": "LEFT",
  "dist": "200 m",
  "street": "Main Street",
  "eta": "12:30",
  "rem": "5.2 km",
  "speed": 45.0,
  "then": "THEN: RIGHT",
  "lat": 10.1234,
  "lng": 76.5678
}
```

#### Supported `turn` Values

| Value           | Icon         |
|-----------------|--------------|
| `STRAIGHT`      | ↑ Straight   |
| `LEFT`          | ← Left       |
| `RIGHT`         | → Right      |
| `SLIGHT_LEFT`   | ↖ Slight Left|
| `SLIGHT_RIGHT`  | ↗ Slight Right|
| `SHARP_LEFT`    | ⬰ Sharp Left |
| `SHARP_RIGHT`   | ⬱ Sharp Right|
| `UTURN`         | ↩ U-Turn     |
| `ROUNDABOUT`    | ⟳ Roundabout |
| `ARRIVED`       | ✓ Arrived    |
| `IDLE`          | Returns to idle screen |

### Status Characteristic (Read + Notify)

Returns the ESP32's current state:

```json
{
  "connected": true,
  "navActive": true,
  "maneuver": 2,
  "heap": 180000
}
```

---

## Display Layout

### Idle Screen
```
    ┌──────────────────┐
    │   BIKENAV BLE    │  (Green, large)
    │                  │
    │  BLE ADVERTISING │  (Amber/Green)
    │  OPEN BIKENAV APP│  (White)
    │                  │
    │   BikeNav-BLE    │  (Cyan, large)
    │                  │
    │ ──────────────── │
    │ WAITING FOR APP  │  (Gray)
    │ START NAVIGATION │  (Cyan)
    └──────────────────┘
```

### Navigation Screen
```
    ┌──────────────────┐
    │      ← ←         │  (Arrow icon, 64x64)
    │                  │
    │     200 m        │  (Distance, large white)
    │ ──────────────── │
    │   Main Street    │  (Street, cyan)
    │                  │
    │  THEN: RIGHT     │  (Next turn, amber)
    └──────────────────┘
```

---

## Project Files

```
ESP32_BLE_BikeNav/
├── ESP32_BLE_BikeNav.ino   # Main sketch (BLE + display logic)
├── nav_icons.h             # Anti-aliased 64x64 navigation icon alpha masks
└── README.md               # This file
```

---

## License

This project is for personal use with the BikeNav system.
