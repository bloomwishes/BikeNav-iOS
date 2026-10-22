/*
 * ESP32 BLE Bike Navigation Display (GC9A01 240x240)
 * ---------------------------------------------------
 * Standalone BLE receiver for turn-by-turn navigation.
 * Receives JSON navigation data from the BikeNav iOS app
 * via BLE and renders it on a GC9A01 round TFT display.
 *
 * NO WiFi · NO WebServer · NO ANCS · Pure BLE only
 *
 * Pin Configuration:
 *   - SCL -> ESP32 GPIO 15 (D15)
 *   - SDA -> ESP32 GPIO 2  (D2)
 *   - DC  -> ESP32 GPIO 4  (D4)
 *   - CS  -> ESP32 GPIO 16 (D16)
 *   - RST -> ESP32 GPIO 17 (D17)
 *   - VCC -> 3.3V
 *   - GND -> GND
 *
 * Required Libraries:
 *   - LovyanGFX
 *   - ArduinoJson (v7)
 *   - ESP32 BLE Arduino (built-in with ESP32 board package)
 */

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "nav_icons.h"

// --- Pin Definitions for GC9A01 ---
#define TFT_SCLK  15  // D15 to SCL
#define TFT_MOSI  2   // D2 to SDA
#define TFT_DC    4   // D4 to DC
#define TFT_CS    16  // D16 to CS
#define TFT_RST   17  // D17 to RST

// --- BLE UUIDs ---
#define SERVICE_UUID           "12345678-1234-1234-1234-123456789ABC"
#define NAV_CHARACTERISTIC_UUID "12345678-1234-1234-1234-123456789ABD"
#define STATUS_CHARACTERISTIC_UUID "12345678-1234-1234-1234-123456789ABE"

// Hardware-accelerated GC9A01 configuration for ESP32
class LGFX_GC9A01 : public lgfx::LGFX_Device {
  lgfx::Panel_GC9A01 _panel_instance;
  lgfx::Bus_SPI      _bus_instance;
public:
  LGFX_GC9A01(void) {
    {
      auto cfg = _bus_instance.config();
      cfg.spi_host = SPI2_HOST; // Hardware HSPI on ESP32
      cfg.spi_mode = 0;
      cfg.freq_write = 27000000; // 27 MHz
      cfg.freq_read  = 16000000;
      cfg.spi_3wire  = true;
      cfg.use_lock   = true;
      cfg.dma_channel = SPI_DMA_CH_AUTO;
      cfg.pin_sclk = TFT_SCLK;
      cfg.pin_mosi = TFT_MOSI;
      cfg.pin_miso = -1;
      cfg.pin_dc   = TFT_DC;
      _bus_instance.config(cfg);
      _panel_instance.setBus(&_bus_instance);
    }
    {
      auto cfg = _panel_instance.config();
      cfg.pin_cs           = TFT_CS;
      cfg.pin_rst          = TFT_RST;
      cfg.pin_busy         = -1;
      cfg.panel_width      = 240;
      cfg.panel_height     = 240;
      cfg.offset_x         = 0;
      cfg.offset_y         = 0;
      cfg.offset_rotation  = 0;
      cfg.readable         = false;
      cfg.invert           = true; // GC9A01 IPS panel invert
      cfg.rgb_order        = false;
      cfg.dlen_16bit       = false;
      cfg.bus_shared       = false;
      _panel_instance.config(cfg);
    }
    setPanel(&_panel_instance);
  }
};

LGFX_GC9A01 tft;

// --- BLE State ---
BLEServer* pServer = nullptr;
BLECharacteristic* pNavCharacteristic = nullptr;
BLECharacteristic* pStatusCharacteristic = nullptr;
bool bleConnected = false;
bool prevBleConnected = false;
volatile bool newNavDataReceived = false;
String receivedJsonData = "";

// Navigation Maneuver State
enum ManeuverType {
  NAV_IDLE,
  NAV_STRAIGHT,
  NAV_LEFT,
  NAV_RIGHT,
  NAV_SLIGHT_LEFT,
  NAV_SLIGHT_RIGHT,
  NAV_SHARP_LEFT,
  NAV_SHARP_RIGHT,
  NAV_UTURN,
  NAV_ROUNDABOUT,
  NAV_ARRIVED
};

ManeuverType currentManeuver = NAV_IDLE;
String currentDistStr = "---";
String currentStreet = "Open BikeNav App";
String currentEta = "--:--";
String currentRemDist = "";
String currentThenTurn = "";
float currentSpeed = 0.0;
bool isNavActive = false;
unsigned long lastNavPacketTime = 0;

// Color Palette (RGB565)
#define COLOR_BG       0x0000 // Black
#define COLOR_CARD     0x18E3 // Deep Slate
#define COLOR_GREEN    0x07E0 // Bright Emerald Green
#define COLOR_CYAN     0x07FF // Cyan
#define COLOR_WHITE    0xFFFF // White
#define COLOR_GRAY     0x7BEF // Gray
#define COLOR_AMBER    0xFDA0 // Amber
#define COLOR_RED      0xF800 // Red
#define COLOR_BLUE     0x34DF // Tech Blue

// Forward declarations
void drawIdleScreen();
void drawNavScreen();
void drawStreetDescription(const String& rawText);
void drawArrow(ManeuverType m, int cx, int cy, int size, uint16_t color);
ManeuverType parseManeuver(String turn);
void processNavJson(const String& jsonString);
void updateStatusCharacteristic();

// --- BLE Server Callbacks ---
class BikeNavServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    Serial.println("[BLE] Client connected!");
    bleConnected = true;
  }

  void onDisconnect(BLEServer* pServer) {
    Serial.println("[BLE] Client disconnected.");
    bleConnected = false;
  }
};

// --- BLE Navigation Characteristic Callbacks ---
class NavCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    if (value.length() > 0) {
      Serial.printf("[BLE] Nav data received (%d bytes): %s\n", value.length(), value.c_str());
      receivedJsonData = value;
      newNavDataReceived = true;
    }
  }
};

// --- Maneuver String Parser ---
ManeuverType parseManeuver(String turn) {
  turn.toUpperCase();
  turn.trim();

  if (turn == "LEFT")         return NAV_LEFT;
  if (turn == "RIGHT")        return NAV_RIGHT;
  if (turn == "SLIGHT_LEFT")  return NAV_SLIGHT_LEFT;
  if (turn == "SLIGHT_RIGHT") return NAV_SLIGHT_RIGHT;
  if (turn == "SHARP_LEFT")   return NAV_SHARP_LEFT;
  if (turn == "SHARP_RIGHT")  return NAV_SHARP_RIGHT;
  if (turn == "UTURN")        return NAV_UTURN;
  if (turn == "ROUNDABOUT")   return NAV_ROUNDABOUT;
  if (turn == "ARRIVED")      return NAV_ARRIVED;
  if (turn == "STRAIGHT")     return NAV_STRAIGHT;
  if (turn == "IDLE")         return NAV_IDLE;

  return NAV_STRAIGHT; // Default to straight for unknown directions
}

// --- JSON Navigation Data Processor ---
void processNavJson(const String& jsonString) {
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, jsonString);

  if (error) {
    Serial.printf("[JSON] Parse error: %s\n", error.c_str());
    return;
  }

  // Extract fields with defaults
  String turn   = doc["turn"]   | "IDLE";
  String dist   = doc["dist"]   | "---";
  String street = doc["street"] | "";
  String eta    = doc["eta"]    | "--:--";
  String rem    = doc["rem"]    | "";
  float  speed  = doc["speed"]  | 0.0f;
  String then_  = doc["then"]   | "";

  Serial.printf("[NAV] Turn=%s, Dist=%s, Street=%s, ETA=%s, Rem=%s, Speed=%.1f\n",
                turn.c_str(), dist.c_str(), street.c_str(), eta.c_str(), rem.c_str(), speed);

  // Update navigation state
  currentManeuver = parseManeuver(turn);

  if (dist.length() > 0)   currentDistStr = dist;
  if (street.length() > 0) currentStreet  = street;
  if (eta.length() > 0)    currentEta     = eta;
  if (rem.length() > 0)    currentRemDist = rem;
  currentSpeed = speed;

  if (then_.length() > 0) {
    currentThenTurn = then_;
  } else if (currentManeuver == NAV_IDLE) {
    currentThenTurn = "";
  }

  isNavActive = (currentManeuver != NAV_IDLE);
  lastNavPacketTime = millis();

  drawNavScreen();
}

// --- Update BLE Status Characteristic ---
void updateStatusCharacteristic() {
  if (pStatusCharacteristic == nullptr) return;

  String status = "{";
  status += "\"connected\":" + String(bleConnected ? "true" : "false") + ",";
  status += "\"navActive\":" + String(isNavActive ? "true" : "false") + ",";
  status += "\"maneuver\":" + String((int)currentManeuver) + ",";
  status += "\"heap\":" + String(ESP.getFreeHeap());
  status += "}";

  pStatusCharacteristic->setValue(status.c_str());
  if (bleConnected) {
    pStatusCharacteristic->notify();
  }
}

// =============================================================
// setup()
// =============================================================
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n[SYSTEM] ESP32 BLE BikeNav starting...");
  Serial.printf("[SYSTEM] Free heap: %d bytes\n", ESP.getFreeHeap());

  // --- 1. Hardware reset pulse for GC9A01 ---
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, HIGH);
  delay(10);
  digitalWrite(TFT_RST, LOW);
  delay(50);
  digitalWrite(TFT_RST, HIGH);
  delay(120);

  // --- 2. Initialize GC9A01 Round Display with LovyanGFX ---
  tft.init();
  tft.setRotation(2); // 180° rotation for correct orientation
  Serial.println("[DISPLAY] GC9A01 initialized (240x240 round TFT)");

  // --- 3. Power-on flash sequence ---
  tft.fillScreen(COLOR_RED);
  delay(100);
  tft.fillScreen(COLOR_GREEN);
  delay(100);
  tft.fillScreen(COLOR_BLUE);
  delay(100);
  tft.fillScreen(COLOR_BG);

  // --- 4. Draw idle screen ---
  drawIdleScreen();

  // --- 5. Initialize BLE Server ---
  Serial.println("[BLE] Initializing BLE Server...");
  BLEDevice::init("BikeNav-BLE");

  // Create BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BikeNavServerCallbacks());

  // Create BLE Service
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // Create Navigation Characteristic (Write + Notify)
  pNavCharacteristic = pService->createCharacteristic(
    NAV_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pNavCharacteristic->addDescriptor(new BLE2902());
  pNavCharacteristic->setCallbacks(new NavCharacteristicCallbacks());

  // Create Status Characteristic (Read + Notify)
  pStatusCharacteristic = pService->createCharacteristic(
    STATUS_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusCharacteristic->addDescriptor(new BLE2902());
  pStatusCharacteristic->setValue("{\"connected\":false,\"navActive\":false}");

  // Start the service
  pService->start();

  // --- 6. Start BLE Advertising ---
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); // Helps with iPhone connection
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising as 'BikeNav-BLE'");
  Serial.printf("[SYSTEM] Setup complete. Free heap: %d bytes\n", ESP.getFreeHeap());
}

// =============================================================
// loop()
// =============================================================
void loop() {
  // --- Handle BLE connection state changes ---
  if (bleConnected != prevBleConnected) {
    if (bleConnected) {
      Serial.println("[LOOP] BLE client connected - updating display");
      updateStatusCharacteristic();
      drawIdleScreen();
    } else {
      Serial.println("[LOOP] BLE client disconnected - restarting advertising");
      delay(500); // Give BLE stack time to settle
      BLEDevice::startAdvertising();
      Serial.println("[BLE] Re-advertising...");

      if (isNavActive) {
        // Keep showing last nav screen for 5 min timeout
        Serial.println("[NAV] Keeping nav screen active during disconnect...");
      } else {
        drawIdleScreen();
      }
      updateStatusCharacteristic();
    }
    prevBleConnected = bleConnected;
  }

  // --- Process incoming navigation JSON data ---
  if (newNavDataReceived) {
    newNavDataReceived = false;
    processNavJson(receivedJsonData);
    updateStatusCharacteristic();
  }

  // --- Navigation timeout: return to idle after 5 minutes of no data ---
  if (isNavActive && (millis() - lastNavPacketTime > 300000)) {
    Serial.println("[NAV] 5-minute timeout reached. Returning to idle.");
    isNavActive = false;
    currentManeuver = NAV_IDLE;
    currentDistStr = "---";
    currentStreet = "Open BikeNav App";
    currentThenTurn = "";
    drawIdleScreen();
    updateStatusCharacteristic();
  }

  yield();
}

// =============================================================
// Display Drawing Functions
// =============================================================

void drawIdleScreen() {
  tft.fillScreen(COLOR_BG);

  // Decorative outer rings
  tft.drawCircle(120, 120, 118, COLOR_GRAY);
  tft.drawCircle(120, 120, 117, COLOR_CARD);

  // Title
  tft.setTextSize(2);
  tft.setTextColor(COLOR_GREEN, COLOR_BG);
  tft.setCursor(42, 30);
  tft.print("BIKENAV BLE");

  // Status icon / text
  tft.setTextSize(1);
  if (bleConnected) {
    tft.setTextColor(COLOR_GREEN, COLOR_BG);
    tft.setCursor(65, 60);
    tft.print("BLE CONNECTED");

    tft.setTextColor(COLOR_WHITE, COLOR_BG);
    tft.setCursor(50, 85);
    tft.print("OPEN BIKENAV APP");

    tft.setTextSize(2);
    tft.setTextColor(COLOR_CYAN, COLOR_BG);
    tft.setCursor(78, 110);
    tft.print("START");
    tft.setCursor(30, 135);
    tft.print("NAVIGATION");

  } else {
    tft.setTextColor(COLOR_AMBER, COLOR_BG);
    tft.setCursor(55, 60);
    tft.print("BLE ADVERTISING...");

    tft.setTextColor(COLOR_WHITE, COLOR_BG);
    tft.setCursor(55, 85);
    tft.print("OPEN BIKENAV APP");
    tft.setCursor(60, 100);
    tft.print("TO CONNECT BLE");

    tft.setTextSize(2);
    tft.setTextColor(COLOR_CYAN, COLOR_BG);
    tft.setCursor(30, 125);
    tft.print("BikeNav-BLE");
  }

  // Bottom status line
  tft.drawFastHLine(40, 176, 160, COLOR_CARD);
  tft.setTextSize(1);
  tft.setTextColor(COLOR_GRAY, COLOR_BG);
  tft.setCursor(52, 185);
  tft.print("WAITING FOR APP");

  tft.setTextColor(COLOR_CYAN, COLOR_BG);
  tft.setCursor(42, 204);
  tft.print("START NAVIGATION");
}

// Smart word-wrapping street description renderer for circular GC9A01 display
void drawStreetDescription(const String& rawText) {
  String text = rawText;
  text.trim();
  if (text.length() == 0 || text == "Open BikeNav App") {
    text = "FOLLOW ROUTE";
  }

  // Tokenize into words
  std::vector<String> words;
  int startIdx = 0;
  for (int i = 0; i <= text.length(); i++) {
    if (i == text.length() || text.charAt(i) == ' ' || text.charAt(i) == '\t') {
      if (i > startIdx) {
        words.push_back(text.substring(startIdx, i));
      }
      startIdx = i + 1;
    }
  }
  if (words.empty()) {
    words.push_back(text);
  }

  // Check if text is short enough for large Size 2 font (12px per char)
  // Inside the 240x240 circle at Y=150-185, safe max width for Size 2 is 12 chars per line (144px).
  // If words fit in 1 or 2 lines of max 12 chars, we use Size 2.
  bool useSize2 = true;
  std::vector<String> lines;
  String curLine = "";

  for (size_t i = 0; i < words.size(); i++) {
    String testLine = (curLine.length() == 0) ? words[i] : (curLine + " " + words[i]);
    if (testLine.length() <= 12) {
      curLine = testLine;
    } else {
      if (curLine.length() > 0) {
        lines.push_back(curLine);
        curLine = words[i];
      } else {
        // A single word is longer than 12 chars, Size 2 cannot fit it cleanly
        useSize2 = false;
        break;
      }
    }
  }
  if (curLine.length() > 0) {
    lines.push_back(curLine);
  }

  // If Size 2 resulted in more than 2 lines, or a word was too long, switch to Size 1
  if (!useSize2 || lines.size() > 2) {
    lines.clear();
    curLine = "";
    // Size 1: 6px per char. Safe circle width allows up to 24 chars per line (144px).
    for (size_t i = 0; i < words.size(); i++) {
      String testLine = (curLine.length() == 0) ? words[i] : (curLine + " " + words[i]);
      if (testLine.length() <= 24) {
        curLine = testLine;
      } else {
        if (curLine.length() > 0) {
          lines.push_back(curLine);
          curLine = words[i];
        } else {
          // Extremely long single word > 24 chars, wrap it safely
          lines.push_back(words[i].substring(0, 24));
          curLine = words[i].substring(24);
        }
      }
    }
    if (curLine.length() > 0) {
      lines.push_back(curLine);
    }

    // Limit to max 3 lines for Size 1
    if (lines.size() > 3) {
      lines.resize(3);
      if (lines[2].length() > 21) lines[2] = lines[2].substring(0, 21) + "...";
    }

    tft.setTextSize(1);
    tft.setTextColor(COLOR_CYAN, COLOR_BG);

    int startY = 166;
    if (lines.size() == 1) startY = 168;
    else if (lines.size() == 2) startY = 160;
    else if (lines.size() == 3) startY = 153;

    for (size_t i = 0; i < lines.size(); i++) {
      int pxWidth = lines[i].length() * 6;
      int x = max(15, 120 - (pxWidth / 2));
      tft.setCursor(x, startY + (i * 13));
      tft.print(lines[i]);
    }
  } else {
    // Render in large, bold Size 2
    tft.setTextSize(2);
    tft.setTextColor(COLOR_CYAN, COLOR_BG);

    int startY = (lines.size() == 1) ? 168 : 158;
    for (size_t i = 0; i < lines.size(); i++) {
      int pxWidth = lines[i].length() * 12;
      int x = max(15, 120 - (pxWidth / 2));
      tft.setCursor(x, startY + (i * 20));
      tft.print(lines[i]);
    }
  }
}

void drawNavScreen() {
  // Clear circular active area
  tft.fillCircle(120, 120, 116, COLOR_BG);

  // Outer Circular Ring with subtle depth
  uint16_t ringColor = (currentManeuver == NAV_ARRIVED) ? COLOR_GREEN : COLOR_CYAN;
  tft.drawCircle(120, 120, 119, ringColor);
  tft.drawCircle(120, 120, 118, ringColor);
  tft.drawCircle(120, 120, 115, COLOR_CARD);

  // Determine maneuver arrow color: Emerald Green for turning/maneuvers, Cyan for straight, Amber for U-turn
  uint16_t arrowColor = COLOR_GREEN;
  if (currentManeuver == NAV_STRAIGHT) arrowColor = COLOR_CYAN;
  else if (currentManeuver == NAV_UTURN) arrowColor = COLOR_AMBER;
  else if (currentManeuver == NAV_ARRIVED) arrowColor = COLOR_GREEN;

  // 1. Giant Bold Directional Arrow: Center at (120, 58)
  drawArrow(currentManeuver, 120, 58, 34, arrowColor);

  // 2. High-Visibility Next Turn Distance: Y: 104
  String distText = currentDistStr;
  if (distText.length() == 0 || distText == "---") {
    distText = "NOW";
  }
  
  // Choose optimal text size: size 4 for short distance ("200m", "1km"), size 3 for longer ("1.5 km")
  int distTextSize = (distText.length() <= 5) ? 4 : 3;
  int charWidth = (distTextSize == 4) ? 24 : 18;
  tft.setTextSize(distTextSize);
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  int distPxWidth = distText.length() * charWidth;
  int distStartX = max(15, 120 - (distPxWidth / 2));
  tft.setCursor(distStartX, 104);
  tft.print(distText);

  // Divider Line
  tft.drawFastHLine(45, 142, 150, COLOR_CARD);

  // 3. Road / Street Name: Y: 152 - 188 (Smart word-wrapped, never breaks words)
  drawStreetDescription(currentStreet);

  // 4. Bottom Subtle Status or Next "THEN" Turn: Y: 204
  tft.setTextSize(1);
  if (currentThenTurn.length() > 0) {
    tft.setTextColor(COLOR_AMBER, COLOR_BG);
    int thenX = max(15, 120 - ((int)currentThenTurn.length() * 6 / 2));
    tft.setCursor(thenX, 204);
    tft.print(currentThenTurn);
  } else if (currentRemDist.length() > 0) {
    tft.setTextColor(COLOR_GRAY, COLOR_BG);
    int remX = max(30, 120 - (((int)currentRemDist.length() + 5) * 6 / 2));
    tft.setCursor(remX, 204);
    tft.printf("REM: %s", currentRemDist.c_str());
  } else {
    tft.setTextColor(COLOR_GRAY, COLOR_BG);
    tft.setCursor(85, 204);
    tft.print("LIVE ROUTE");
  }
}

// Renders high-definition, anti-aliased navigation vectors with subpixel edge blending
void drawArrow(ManeuverType m, int cx, int cy, int size, uint16_t color) {
  const uint8_t* alphaMask = nullptr;
  switch (m) {
    case NAV_STRAIGHT:     alphaMask = NAV_ICON_STRAIGHT_ALPHA; break;
    case NAV_LEFT:         alphaMask = NAV_ICON_LEFT_ALPHA; break;
    case NAV_RIGHT:        alphaMask = NAV_ICON_RIGHT_ALPHA; break;
    case NAV_SLIGHT_LEFT:  alphaMask = NAV_ICON_SLIGHT_LEFT_ALPHA; break;
    case NAV_SLIGHT_RIGHT: alphaMask = NAV_ICON_SLIGHT_RIGHT_ALPHA; break;
    case NAV_SHARP_LEFT:   alphaMask = NAV_ICON_SHARP_LEFT_ALPHA; break;
    case NAV_SHARP_RIGHT:  alphaMask = NAV_ICON_SHARP_RIGHT_ALPHA; break;
    case NAV_UTURN:        alphaMask = NAV_ICON_UTURN_ALPHA; break;
    case NAV_ROUNDABOUT:   alphaMask = NAV_ICON_ROUNDABOUT_ALPHA; break;
    case NAV_ARRIVED:      alphaMask = NAV_ICON_ARRIVED_ALPHA; break;
    default:               alphaMask = NAV_ICON_IDLE_ALPHA; break;
  }

  // Decompose target color into 5-6-5 channels
  uint32_t r_target = (color >> 11) & 0x1F;
  uint32_t g_target = (color >> 5) & 0x3F;
  uint32_t b_target = color & 0x1F;

  // Single static image buffer for ultra-fast SPI DMA push
  static uint16_t iconBuf[NAV_ICON_WIDTH * NAV_ICON_HEIGHT];

  for (int i = 0; i < NAV_ICON_WIDTH * NAV_ICON_HEIGHT; i++) {
    uint8_t a = pgm_read_byte(&alphaMask[i]);
    if (a == 0) {
      iconBuf[i] = COLOR_BG; // 0x0000 (Pure Black background)
    } else if (a == 255) {
      iconBuf[i] = color;
    } else {
      // Subpixel smooth anti-aliased edge blending with black background
      uint16_t r = (r_target * a + 128) >> 8;
      uint16_t g = (g_target * a + 128) >> 8;
      uint16_t b = (b_target * a + 128) >> 8;
      iconBuf[i] = (r << 11) | (g << 5) | b;
    }
  }

  // Blit the anti-aliased 64x64 icon centered at (cx, cy)
  int startX = cx - (NAV_ICON_WIDTH / 2);
  int startY = cy - (NAV_ICON_HEIGHT / 2);
  tft.pushImage(startX, startY, NAV_ICON_WIDTH, NAV_ICON_HEIGHT, iconBuf);
}
