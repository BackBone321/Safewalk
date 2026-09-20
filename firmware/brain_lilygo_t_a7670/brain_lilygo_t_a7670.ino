/*
 * Safewalk IoT Tracker - Board 1 (LILYGO T-A7670 V3 4G)
 * 
 * Hardware Details:
 * - Microcontroller: ESP32-D0WD-V3
 * - Cellular Module: A7670 4G LTE + GPS (connected via UART)
 * - Tactile Button: Connected between GPIO 14 and GND (internal pull-up enabled)
 * 
 * Features:
 * - Controls power state of the A7670 module using PWRKEY.
 * - Powers on GPS and decodes NMEA coordinates.
 * - Connects to the cellular network using APN details.
 * - Monitors a tactile button (debounced).
 * - On button press:
 *   1. Obtains current GPS coordinates.
 *   2. Sends a direct HTTP POST request to the Firebase Firestore REST API.
 *   3. Sends a backup SMS message to a pre-configured parent phone number.
 */

#include <HardwareSerial.h>
#include <driver/i2s.h>
#include <driver/gpio.h>
#include <safewalk-voice-help_inferencing.h>

// Board Pin Definitions (LILYGO T-A7670 V3)
#define BOARD_TXD       26  // ESP32 TX (connects to A7670 RXD)
#define BOARD_RXD       27  // ESP32 RX (connects to A7670 TXD)
#define BOARD_PWRKEY    4
#define BOARD_RESET     5
#define BOARD_POWERON   12  // Enables onboard voltage regulator for cellular module
#define BOARD_PIN_DTR   13
#define BOARD_PIN_RI    15

// Tactile Button Pin
#define BUTTON_PIN      14

// INMP441 I2S Microphone Pin Definitions
#define I2S_WS          25  // Word Select / LRCLK
#define I2S_SD          32  // Serial Data Out (ESP32 Data In)
#define I2S_SCK         33  // Serial Clock / BCLK
#define I2S_PORT        I2S_NUM_0
#define SAMPLE_RATE     EI_CLASSIFIER_FREQUENCY // Matches Edge Impulse trained sample rate (8kHz / 16kHz)

// Serial communication baud rate
#define SERIAL_BAUD     115200
#define MODEM_BAUD      115200

// Cellular Configuration (Will be auto-detected, defaults to Globe)
String activeAPN = "http.globe.com.ph";

// Firebase Configuration (From project setup)
const char FIREBASE_PROJECT_ID[] = "safe-walk1";
const char FIREBASE_API_KEY[] = "AIzaSyDaNNEfa8wqUZbfcsvhThuFo6MDDyTql5k"; // Android API key

// Device Registration Info
const char DEVICE_ID[] = "safewalk_device_001";
const char DEVICE_NAME[] = "LilyGo Tracker 001";
const char DEVICE_PHONE[] = "09568165326"; // Simulated device SIM number

// Alert Details & Parent SMS Fallback Info
// The target parent's phone number to send the SMS to (Philippine format, e.g. "+639xxxxxxxxx")
const char PARENT_PHONE[] = "09129457063"; 
const char PARENT_UID[] = "parent_mock_uid_123"; // Handled in DB linking

// Dynamic variables populated at runtime from SIM (AT+CNUM) and Firestore
String devicePhoneNumber = "";
String dynamicParentPhone = "";
String dynamicParentUid = "";
String dynamicStudentUid = "";

#define TINY_GSM_MODEM_A7672X
#include <TinyGsmClient.h>

// Serial interface for communicating with A7670
HardwareSerial modemSerial(1);

// Serial interface for communicating with the external GPS module (Quectel L76K)
#define BOARD_GPS_TX_PIN    21
#define BOARD_GPS_RX_PIN    22
HardwareSerial gpsSerial(2);

// TinyGSM instance (used for GPRS connection only)
TinyGsm modem(modemSerial);

// Button variables for debouncing
int buttonState = HIGH;
int lastButtonState = HIGH;
unsigned long lastDebounceTime = 0;
const unsigned long DEBOUNCE_DELAY = 50; // milliseconds

// Cooldown timer for voice triggers to avoid continuous alerts
unsigned long lastVoiceTriggerTime = 0;
const unsigned long VOICE_COOLDOWN_MS = 15000; // 15 seconds cooldown
String lastVoiceKeyword = "TABANG";

// Boot grace period: prevents any false triggers during startup while hardware/network stabilizes
unsigned long systemBootReadyTime = 0;
const unsigned long BOOT_GRACE_PERIOD_MS = 5000; // 5-second grace period after boot

// Function Prototypes
void initializeA7670();
bool sendATCommand(const String& cmd, String& response, unsigned long timeout = 1000);
bool setupGPS();
bool getGPSLocation(double& lat, double& lon); 
String getField(const String& data, char separator, int index);
bool setupNetwork();
bool triggerFirebaseAlert(double lat, double lon, const String& triggerType = "sos", const String& audioBase64 = "");
bool sendSMSAlert(double lat, double lon);
void flushModemBuffer();
bool fetchDeviceConfig();
String parseJsonStringField(const String& json, const String& fieldName);
String getNetworkTimeRFC3339();
String detectAPN();

// INMP441 Audio Prototypes
bool initI2SMicrophone();
bool checkVoiceHelpTrigger();
String recordAndEncodeAudioClip(size_t durationSeconds = 3);
String encodeBase64(const uint8_t* input, size_t inputLen);
void createWavHeader(uint8_t* header, uint32_t pcmDataSize, uint32_t sampleRate = 8000, uint16_t numChannels = 1, uint16_t bitsPerSample = 16);
void triggerEmergencyAlertProcess(const String& triggerSource);

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(1000);
  Serial.println("=========================================");
  Serial.println("   Safewalk Tracker starting up...       ");
  Serial.println("=========================================");

  // Set up button pin
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // Initialize hardware serial for modem
  modemSerial.begin(MODEM_BAUD, SERIAL_8N1, BOARD_RXD, BOARD_TXD);

  // Initialize power lines and turn on module
  initializeA7670();

  // Configure GPS
  setupGPS();

  // Connect to Network/APN
  setupNetwork();

  // Initialize INMP441 I2S Microphone
  initI2SMicrophone();

  systemBootReadyTime = millis();
  Serial.println("System Ready. Edge Impulse AI listening for 'HELP' or 'TABANG', or tactile button on GPIO 14.");
}

void loop() {
  // 1. Read state of the tactile button (active LOW)
  int reading = digitalRead(BUTTON_PIN);

  if (reading != lastButtonState) {
    lastDebounceTime = millis();
  }

  if ((millis() - lastDebounceTime) > DEBOUNCE_DELAY) {
    if (reading != buttonState) {
      buttonState = reading;

      // Detect button pressed (transition from HIGH to LOW)
      if (buttonState == LOW) {
        lastVoiceKeyword = "SOS BUTTON";
        Serial.println("\n[ALERT] Tactile Button Pressed! Triggering SOS Alert...");
        triggerEmergencyAlertProcess("sos");
      }
    }
  }

  lastButtonState = reading;

  // 2. Check INMP441 audio for voice 'Help' or 'Tabang' distress trigger
  bool voiceTriggerDetected = checkVoiceHelpTrigger();
  if (voiceTriggerDetected && (millis() - lastVoiceTriggerTime > VOICE_COOLDOWN_MS)) {
    lastVoiceTriggerTime = millis();
    Serial.printf("\n[ALERT] Voice '%s' distress keyword confirmed by Edge Impulse AI!\n", lastVoiceKeyword.c_str());
    triggerEmergencyAlertProcess("voice_help");
  }

  // Periodically read any incoming serial data from the modem to keep buffersz clear
  while (modemSerial.available()) {
    Serial.write(modemSerial.read());
  }
}

// Discards all pending bytes from the modem UART receive buffer.
// Call this between operations to prevent cross-command response contamination.
void flushModemBuffer() {
  unsigned long t = millis();
  while (millis() - t < 500) {
    while (modemSerial.available()) {
      modemSerial.read();
    }
    delay(50);
  }
}

// Initialise board power rails and boot up module
void initializeA7670() {
  Serial.println("[MODEM] Initializing hardware control lines...");

  // Configure pins
  pinMode(BOARD_POWERON, OUTPUT);
  pinMode(BOARD_PWRKEY, OUTPUT);
  pinMode(BOARD_RESET, OUTPUT);
  pinMode(BOARD_PIN_DTR, OUTPUT);

  // 1. Turn on the power regulator/LDO to the cellular modem
  digitalWrite(BOARD_POWERON, HIGH);
  delay(500); // Give the regulator time to stabilize voltage

  // 2. Release reset pin (keep high)
  digitalWrite(BOARD_RESET, HIGH);

  // 3. Deassert sleep pin (DTR low wakes up module)
  digitalWrite(BOARD_PIN_DTR, LOW);

  Serial.println("[MODEM] Checking modem communication...");
  String response;
  bool isResponsive = false;

  // Try pinging modem with wake-up CR/LF
  for (int i = 0; i < 3; i++) {
    modemSerial.println("AT");
    delay(200);
    if (sendATCommand("AT", response, 1000)) {
      isResponsive = true;
      break;
    }
  }

  if (!isResponsive) {
    Serial.println("[MODEM] Modem unresponsive. Pulsing PWRKEY to power on...");
    
    // Pulse PWRKEY HIGH for 1.5s to trigger power on
    digitalWrite(BOARD_PWRKEY, HIGH);
    delay(1500);
    digitalWrite(BOARD_PWRKEY, LOW);
    
    // Wait for boot sequence
    Serial.println("[MODEM] Waiting for boot...");
    delay(6000);
    
    // Check communication
    int retries = 10;
    while (retries > 0) {
      if (sendATCommand("AT", response, 1000)) {
        isResponsive = true;
        Serial.println("[MODEM] Modem is online and responding to AT commands.");
        break;
      }
      delay(1000);
      retries--;
    }
    
    // If still unresponsive, perform a full hardware RESET
    if (!isResponsive) {
      Serial.println("[MODEM] Still unresponsive. Triggering hardware RESET pulse...");
      digitalWrite(BOARD_RESET, LOW);
      delay(300);
      digitalWrite(BOARD_RESET, HIGH);
      delay(5000);

      // Pulse PWRKEY after reset
      digitalWrite(BOARD_PWRKEY, HIGH);
      delay(1500);
      digitalWrite(BOARD_PWRKEY, LOW);
      delay(6000);

      for (int r = 0; r < 10; r++) {
        if (sendATCommand("AT", response, 1000)) {
          isResponsive = true;
          Serial.println("[MODEM] Modem recovered after hardware reset!");
          break;
        }
        delay(1000);
      }
    }
  } else {
    Serial.println("[MODEM] Modem is already powered on.");
  }

  // Turn off local echo for cleaner responses
  sendATCommand("ATE0", response);
  
  // Wait up to 15 seconds for SIM card to become READY
  int simRetries = 15;
  bool simReady = false;
  while (simRetries > 0) {
    sendATCommand("AT+CPIN?", response);
    Serial.printf("[MODEM] Checking SIM status: %s\n", response.c_str());
    if (response.indexOf("READY") != -1) {
      simReady = true;
      break;
    }
    delay(1000);
    simRetries--;
  }

  if (!simReady) {
    Serial.println("[MODEM] WARNING: SIM card not ready or requires PIN!");
  } else {
    Serial.println("[MODEM] SIM card status verification complete: READY.");
  }

  // --- SSL CONFIG DEBUG ---
  String debugResp;
  Serial.println("--- SSL CONFIG DEBUG ---");
  sendATCommand("AT+CSSLCFG=?", debugResp, 3000);
  Serial.println("AT+CSSLCFG=? -> " + debugResp);
  
  sendATCommand("AT+CSSLCFG=\"sslversion\",0,4", debugResp, 3000);
  Serial.println("sslversion -> " + debugResp);
  
  sendATCommand("AT+CSSLCFG=\"authmode\",0,0", debugResp, 3000);
  Serial.println("authmode -> " + debugResp);
  
  sendATCommand("AT+CSSLCFG=\"ignorelocaltime\",0,1", debugResp, 3000);
  Serial.println("ignorelocaltime -> " + debugResp);
  
  sendATCommand("AT+CSSLCFG=\"enableSNI\",0,1", debugResp, 3000);
  Serial.println("enableSNI -> " + debugResp);
  Serial.println("------------------------");
}

// Helper to send AT command and capture response
bool sendATCommand(const String& cmd, String& response, unsigned long timeout) {
  response = "";
  // Clear read buffer
  while (modemSerial.available()) {
    modemSerial.read();
  }

  // Write command
  modemSerial.println(cmd);
  
  unsigned long start = millis();
  while (millis() - start < timeout) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      response += c;
    }
    // Check if the response contains "OK\r\n" or "ERROR\r\n" or "+CME ERROR"
    if (response.indexOf("OK\r\n") != -1 || response.indexOf("ERROR\r\n") != -1) {
      break;
    }
  }
  response.trim();
  return (response.length() > 0 && response.indexOf("ERROR") == -1);
}

// Helper function to extract comma-separated values from NMEA strings
String getField(const String& data, char separator, int index) {
  int found = 0;
  int strIndex[] = { 0, -1 };
  int maxIndex = data.length() - 1;

  for (int i = 0; i <= maxIndex && found <= index; i++) {
    if (data.charAt(i) == separator || i == maxIndex) {
      found++;
      strIndex[0] = strIndex[1] + 1;
      strIndex[1] = (i == maxIndex) ? i + 1 : i;
    }
  }
  return found > index ? data.substring(strIndex[0], strIndex[1]) : "";
}

// Configures and starts GPS session for external Quectel L76K GPS
bool setupGPS() {
  Serial.println("[GPS] Initializing external GPS (Quectel L76K) on Serial2...");
  
  // Note: The BOARD_POWER_ON pin (GPIO 12) is already set HIGH in initializeA7670(), 
  // which provides power to the onboard LDO and powers the L76K GPS module.
  
  // Initialize Serial2 for the GPS module (Baud: 9600, RX: GPIO 22, TX: GPIO 21)
  gpsSerial.begin(9600, SERIAL_8N1, BOARD_GPS_RX_PIN, BOARD_GPS_TX_PIN);
  
  // Give it a moment to boot
  delay(500);
  
  Serial.println("[GPS] External GPS service started successfully at 9600 baud.");
  Serial.println("[GPS] NOTE: First outdoor satellite fix may take 30-60 seconds.");
  return true;
}

// Obtains the current GPS location by reading NMEA sentences from the external module
bool getGPSLocation(double& lat, double& lon) {
  Serial.println("[GPS] Querying external GPS coordinates...");
  
  unsigned long start = millis();
  String buffer = "";
  
  // Try reading serial data from GPS for up to 3 seconds
  while (millis() - start < 3000) {
    while (gpsSerial.available()) {
      char c = gpsSerial.read();
      if (c == '\n') {
        buffer.trim();
        
        // Look for GGA sentence ($GNGGA or $GPGGA) which contains the 3D position fix info
        if (buffer.startsWith("$GNGGA") || buffer.startsWith("$GPGGA")) {
          // Serial.printf("[GPS DEBUG] NMEA: %s\n", buffer.c_str()); // Optional debug line
          
          // Field 6 is the Position Fix Indicator (0 = no fix, 1 = GPS fix, 2 = DGPS fix)
          String fixStr = getField(buffer, ',', 6);
          int fix = fixStr.toInt();
          
          if (fix > 0) {
            String latStr = getField(buffer, ',', 2);
            String latNS  = getField(buffer, ',', 3);
            String lonStr = getField(buffer, ',', 4);
            String lonEW  = getField(buffer, ',', 5);
            
            if (latStr.length() > 0 && lonStr.length() > 0) {
              // Convert Latitude: DDMM.MMMMM to decimal degrees
              double rawLat = latStr.toDouble();
              int latDeg = (int)(rawLat / 100);
              double latMin = rawLat - (latDeg * 100);
              lat = latDeg + (latMin / 60.0);
              if (latNS == "S") lat = -lat;
              
              // Convert Longitude: DDDMM.MMMMM to decimal degrees
              double rawLon = lonStr.toDouble();
              int lonDeg = (int)(rawLon / 100);
              double lonMin = rawLon - (lonDeg * 100);
              lon = lonDeg + (lonMin / 60.0);
              if (lonEW == "W") lon = -lon;
              
              return true;
            }
          }
        }
        buffer = ""; // Clear buffer for next line
      } else if (c != '\r') {
        buffer += c;
      }
    }
  }
  
  return false;
}

// Checks network connection status and registers GPRS data using TinyGSM
bool setupNetwork() {
  String response;
  Serial.println("[NETWORK] Checking network registration...");
  
  // Verify SIM ready state
  sendATCommand("AT+CPIN?", response);
  if (response.indexOf("READY") == -1) {
    Serial.println("[NETWORK] ERROR: SIM is not ready!");
    return false;
  }
  
  // Auto-detect APN based on SIM card IMSI
  activeAPN = detectAPN();

  // Define PDP context 1 with APN
  String setAPNCommand = "AT+CGDCONT=1,\"IP\",\"" + activeAPN + "\"";
  sendATCommand(setAPNCommand, response);
  
  // Wait up to 15 seconds for network registration (CGREG/CREG)
  int retries = 15;
  bool registered = false;
  while (retries > 0) {
    sendATCommand("AT+CGREG?", response);
    Serial.printf("[NETWORK] CGREG Status: %s\n", response.c_str());
    // Look for registration: home (1) or roaming (5)
    if (response.indexOf(",1") != -1 || response.indexOf(",5") != -1) {
      registered = true;
      break;
    }
    delay(1000);
    retries--;
  }
  
  if (!registered) {
    Serial.println("[NETWORK] Failed to register on GPRS/LTE network. Fallback to manual registration check...");
    sendATCommand("AT+CREG?", response);
    Serial.printf("[NETWORK] CREG Status: %s\n", response.c_str());
  }

  Serial.println("[NETWORK] Connecting GPRS using TinyGSM...");
  // TinyGSM handles context activation and GPRS attachment internally
  if (!modem.gprsConnect(activeAPN.c_str())) {
    Serial.println("[NETWORK] GPRS connection failed!");
    return false;
  }

  IPAddress localIP = modem.localIP();
  Serial.print("[NETWORK] GPRS Connected. Local IP: ");
  Serial.println(localIP);
  
  // Give GPRS connection a moment to stabilize
  delay(2000);

  // Activate App Network for internal TCP/IP services (HTTP/HTTPS/DNS)
  // Some A7670 firmware versions use AT+CNACT, while others use AT+NETOPEN.
  Serial.println("[NETWORK] Activating App Network interface...");
  bool netOpen = false;
  
  sendATCommand("AT+CNACT=1,1", response, 6000);
  if (response.indexOf("OK") != -1) {
    Serial.println("[NETWORK] App Network activated via CNACT.");
    netOpen = true;
  } else {
    Serial.println("[NETWORK] CNACT failed or unsupported. Trying NETOPEN fallback...");
    sendATCommand("AT+NETOPEN", response, 6000);
    if (response.indexOf("OK") != -1 || response.indexOf("Already open") != -1) {
      Serial.println("[NETWORK] App Network activated via NETOPEN.");
      netOpen = true;
    }
  }

  // Print network interface status for diagnostics
  if (netOpen) {
    sendATCommand("AT+CNACT?", response, 2000);
    Serial.printf("[NETWORK] CNACT status: %s\n", response.c_str());
    sendATCommand("AT+NETOPEN?", response, 2000);
    Serial.printf("[NETWORK] NETOPEN status: %s\n", response.c_str());

    // Auto-sync real network time via NITZ and NTP (UTC+8 Philippine Time = +32 quarter-hours)
    sendATCommand("AT+CTZU=1", response, 2000);
    sendATCommand("AT+CNTP=\"time.google.com\",32", response, 3000);
    sendATCommand("AT+CNTP", response, 5000);
  } else {
    Serial.println("[NETWORK] WARNING: Failed to activate App Network interface!");
  }

  // Fetch device configuration dynamically from Firestore
  fetchDeviceConfig();

  return true;
}

// Sends the SOS alert metadata directly to Firestore via HTTPS REST API
// Uses the SIMCom A7670 native AT+HTTP stack (correct command set for this modem)
bool triggerFirebaseAlert(double lat, double lon, const String& triggerType, const String& audioBase64) {
  // Refresh configuration dynamically before sending alert to use the latest linking details
  fetchDeviceConfig();

  Serial.println("[FIREBASE] Initiating HTTPS via modem AT+HTTPINIT...");
  String response;

  // Safety flush — clear any leftover UART bytes before starting HTTP commands
  flushModemBuffer();

  // Get timestamp from cellular network
  String rfcTimestamp = getNetworkTimeRFC3339();

  String alertMsg = (triggerType == "voice_help") ? 
                    ("EMERGENCY: Voice distress '" + lastVoiceKeyword + "' call detected by INMP441 mic!") : 
                    "EMERGENCY: SOS tactile button triggered by tracker.";

  // Construct JSON body
  String jsonBody = "{\"fields\":{";
  jsonBody += "\"deviceId\":{\"stringValue\":\"" + String(DEVICE_ID) + "\"},";
  jsonBody += "\"uid\":{\"stringValue\":\"" + (dynamicStudentUid.length() > 0 ? dynamicStudentUid : String(DEVICE_ID)) + "\"},";
  jsonBody += "\"studentUid\":{\"stringValue\":\"" + (dynamicStudentUid.length() > 0 ? dynamicStudentUid : String(DEVICE_ID)) + "\"},";
  jsonBody += "\"fullName\":{\"stringValue\":\"" + String(DEVICE_NAME) + "\"},";
  jsonBody += "\"phoneNumber\":{\"stringValue\":\"" + (devicePhoneNumber.length() > 0 ? devicePhoneNumber : String(DEVICE_PHONE)) + "\"},";
  jsonBody += "\"parentUid\":{\"stringValue\":\"" + (dynamicParentUid.length() > 0 ? dynamicParentUid : String(PARENT_UID)) + "\"},";
  jsonBody += "\"parentPhoneNumber\":{\"stringValue\":\"" + (dynamicParentPhone.length() > 0 ? dynamicParentPhone : String(PARENT_PHONE)) + "\"},";
  String initialStatus = "active";
  jsonBody += "\"type\":{\"stringValue\":\"" + triggerType + "\"},";
  jsonBody += "\"severity\":{\"stringValue\":\"high\"},";
  jsonBody += "\"status\":{\"stringValue\":\"" + initialStatus + "\"},";
  jsonBody += "\"message\":{\"stringValue\":\"" + alertMsg + "\"},";
  if (audioBase64.length() > 0) {
    jsonBody += "\"audioClip\":{\"stringValue\":\"data:audio/wav;base64," + audioBase64 + "\"},";
  }
  jsonBody += "\"location\":{\"stringValue\":\"" + String(lat, 6) + ", " + String(lon, 6) + "\"},";
  jsonBody += "\"coordinates\":{\"geoPointValue\":{";
  jsonBody += "\"latitude\":" + String(lat, 6) + ",";
  jsonBody += "\"longitude\":" + String(lon, 6);
  jsonBody += "}},";
  jsonBody += "\"timestamp\":{\"timestampValue\":\"" + rfcTimestamp + "\"},";
  jsonBody += "\"locationSource\":{\"stringValue\":\"device_gps\"},";
  jsonBody += "\"triggeredBy\":{\"stringValue\":\"iot_device\"}";
  jsonBody += "}}";

  // Build full Firestore URL
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += FIREBASE_PROJECT_ID;
  url += "/databases/(default)/documents/emergency_alerts?key=";
  url += FIREBASE_API_KEY;

  // Step 1: Terminate any previous HTTP session
  sendATCommand("AT+HTTPTERM", response, 3000);
  delay(500);

  // Step 2: Configure SSL context 0 BEFORE enabling SSL on HTTP
  // This is the only reliable way to connect to Google APIs over cellular without a cert store
  sendATCommand("AT+CSSLCFG=\"authmode\",0,0", response, 3000);
  sendATCommand("AT+CSSLCFG=\"sslversion\",0,4", response, 3000);
  sendATCommand("AT+CSSLCFG=\"ignorelocaltime\",0,1", response, 3000);
  sendATCommand("AT+CSSLCFG=\"enableSNI\",0,1", response, 3000);
  Serial.println("[FIREBASE] SSL context configured (no cert verification).");

  // Step 3: Initialize HTTP service
  if (!sendATCommand("AT+HTTPINIT", response, 5000)) {
    Serial.println("[FIREBASE] AT+HTTPINIT failed: " + response);
    return false;
  }
  Serial.println("[FIREBASE] HTTP service initialized.");

  // Step 4: Enable SSL for this HTTP session (REQUIRED for HTTPS on A7670)
  sendATCommand("AT+HTTPSSL=1", response, 3000);
  Serial.println("[FIREBASE] SSL enabled for HTTP session.");

  // Step 5: Set PDP bearer context ID
  sendATCommand("AT+HTTPPARA=\"CID\",1", response, 3000);

  // Step 6: Link SSL context 0 to this HTTP session
  sendATCommand("AT+HTTPPARA=\"SSLCFG\",0", response, 3000);

  // Step 7: Set the target URL
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", response, 3000);

  // Step 8: Set Content-Type header
  sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", response, 3000);


  // Step 6: Send input data size and wait for DOWNLOAD prompt
  modemSerial.println("AT+HTTPDATA=" + String(jsonBody.length()) + ",20000");

  unsigned long t = millis();
  String atResp = "";
  bool gotDownload = false;
  while (millis() - t < 8000) {
    // Read response
    while (modemSerial.available()) {
      char c = modemSerial.read();
      atResp += c;
    }
    if (atResp.indexOf("DOWNLOAD") != -1) {
      gotDownload = true;
      break;
    }
    delay(100);
  }

  if (!gotDownload) {
    Serial.println("[FIREBASE] HTTPDATA prompt failed: " + atResp);
    sendATCommand("AT+HTTPTERM", response, 3000);
    return false;
  }

  // Step 7: Send the JSON body in 512-byte chunks to avoid UART FIFO buffer overflow
  size_t totalLen = jsonBody.length();
  size_t sent = 0;
  while (sent < totalLen) {
    size_t toSend = (totalLen - sent > 512) ? 512 : (totalLen - sent);
    modemSerial.print(jsonBody.substring(sent, sent + toSend));
    sent += toSend;
    delay(5);
  }
  delay(1000);

  // Wait for OK
  atResp = "";
  t = millis();
  while (millis() - t < 5000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      atResp += c;
    }
    if (atResp.indexOf("OK") != -1) break;
    delay(100);
  }
  Serial.println("[FIREBASE] Data staged. Sending POST request...");

  // Step 8: Execute HTTP POST (1 = POST)
  modemSerial.println("AT+HTTPACTION=1");

  // Step 9: Wait for +HTTPACTION URC
  // SSL handshake over cellular can take up to 60 seconds — wait the full window
  atResp = "";
  t = millis();
  bool success = false;
  Serial.println("[FIREBASE] Waiting for server response (up to 60s)...");
  while (millis() - t < 60000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      atResp += c;
    }
    if (atResp.indexOf("+HTTPACTION:") != -1) {
      Serial.println("[FIREBASE] HTTP Response: " + atResp);
      if (atResp.indexOf(",200,") != -1 || atResp.indexOf(",201,") != -1) {
        success = true;
        Serial.println("[FIREBASE] Alert uploaded successfully!");
      } else {
        // Print the SIMCom error code for easier debugging
        Serial.println("[FIREBASE] Error — check SIMCom code in response above.");
      }
      break;
    }
    // Print a dot every 5 seconds so we can see it is still alive
    if ((millis() - t) % 5000 < 200) {
      Serial.print(".");
    }
    delay(200);
  }

  if (!success && atResp.indexOf("+HTTPACTION:") == -1) {
    Serial.println("[FIREBASE] Timeout waiting for server response.");
  }

  // Step 10: Terminate HTTP service
  sendATCommand("AT+HTTPTERM", response, 3000);
  return success;
}



// Sends direct cellular SMS with Google Maps coordinates link to parent
bool sendSMSAlert(double lat, double lon) {
  String response;
  Serial.println("[SMS] Preparing backup SMS alert to parent...");
  
  // Verify modem registered to network first
  sendATCommand("AT+CREG?", response);
  if (response.indexOf(",1") == -1 && response.indexOf(",5") == -1) {
    Serial.println("[SMS] Warning: Modem is not registered to network. SMS may fail.");
  }

  // Set SMS mode to text (1 = text mode, 0 = PDU mode)
  if (!sendATCommand("AT+CMGF=1", response, 2000)) {
    Serial.printf("[SMS] Failed to set text mode. Response: %s. Retrying...\n", response.c_str());
    // Retry once
    delay(1000);
    if (!sendATCommand("AT+CMGF=1", response, 2000)) {
      return false;
    }
  }

  // Configure character set to GSM
  sendATCommand("AT+CSCS=\"GSM\"", response);

  // Construct destination command
  String targetParentPhone = (dynamicParentPhone.length() > 0 ? dynamicParentPhone : String(PARENT_PHONE));
  String sendSmsCmd = "AT+CMGS=\"" + targetParentPhone + "\"";
  
  // Send destination command and wait for prompt (usually '>')
  modemSerial.println(sendSmsCmd);
  
  unsigned long start = millis();
  bool gotPrompt = false;
  while (millis() - start < 3000) {
    if (modemSerial.available()) {
      char c = modemSerial.read();
      if (c == '>') {
        gotPrompt = true;
        break;
      }
    }
  }

  if (gotPrompt) {
    // Construct message body
    String sourceLabel = (lastVoiceKeyword.length() > 0) ? lastVoiceKeyword : "SOS";
    String message = "ALERT: Safewalk (" + sourceLabel + ") emergency triggered! Child Location:\n";
    message += "https://maps.google.com/?q=" + String(lat, 6) + "," + String(lon, 6);
    message += "\nLatitude: " + String(lat, 6) + "\nLongitude: " + String(lon, 6);
    
    // Write message followed by Ctrl+Z character (ASCII 26) to commit SMS
    modemSerial.print(message);
    modemSerial.write(26); 
    
    // Wait for confirmation response
    response = "";
    start = millis();
    while (millis() - start < 15000) {
      while (modemSerial.available()) {
        char c = modemSerial.read();
        response += c;
      }
      if (response.indexOf("+CMGS:") != -1 && response.indexOf("OK\r\n") != -1) {
        return true;
      }
    }
    Serial.printf("[SMS] No send confirmation response: %s\n", response.c_str());
  } else {
    Serial.println("[SMS] Failed to obtain write prompt from modem.");
  }
  
  return false;
}

// Parses a simple string field from a Firestore JSON response
String parseJsonStringField(const String& json, const String& fieldName) {
  int fieldIndex = json.indexOf("\"" + fieldName + "\"");
  if (fieldIndex == -1) return "";
  
  // Look for "stringValue" after the field name
  int stringValueIndex = json.indexOf("\"stringValue\"", fieldIndex);
  if (stringValueIndex == -1) return "";
  
  // Find the colon after "stringValue"
  int colonIndex = json.indexOf(":", stringValueIndex);
  if (colonIndex == -1) return "";
  
  // Find the opening quote of the value
  int openQuoteIndex = json.indexOf("\"", colonIndex);
  if (openQuoteIndex == -1) return "";
  
  // Find the closing quote of the value
  int closeQuoteIndex = json.indexOf("\"", openQuoteIndex + 1);
  if (closeQuoteIndex == -1) return "";
  
  return json.substring(openQuoteIndex + 1, closeQuoteIndex);
}

// Queries cellular network time (AT+CCLK?) and formats it as an ISO 8601/RFC 3339 timestamp
String getNetworkTimeRFC3339() {
  String response;
  if (sendATCommand("AT+CCLK?", response, 1000)) {
    // Response looks like: +CCLK: "26/07/08,13:58:30+32"
    int firstQuote = response.indexOf("\"");
    int lastQuote = response.lastIndexOf("\"");
    if (firstQuote != -1 && lastQuote != -1 && lastQuote > firstQuote) {
      String cclk = response.substring(firstQuote + 1, lastQuote);
      if (cclk.length() >= 17) {
        String yy = cclk.substring(0, 2);
        String mm = cclk.substring(3, 5);
        String dd = cclk.substring(6, 8);
        String hh = cclk.substring(9, 11);
        String min = cclk.substring(12, 14);
        String ss = cclk.substring(15, 17);
        
        // Check for invalid/un-synced year (like "70" un-synced 1970 epoch or out of 2024-2030 range)
        int yVal = yy.toInt();
        String fullYear = (yVal >= 24 && yVal <= 30) ? ("20" + yy) : "2026";
        
        // Build ISO 8601 string: 20yy-mm-ddThh:mm:ss
        String iso = fullYear + "-" + mm + "-" + dd + "T" + hh + ":" + min + ":" + ss;
        
        // Check if there is offset (e.g. +32 or -04)
        if (cclk.length() > 17) {
          char tzSign = cclk.charAt(17);
          if (tzSign == '+' || tzSign == '-') {
            String tzVal = cclk.substring(18);
            int quarters = tzVal.toInt();
            int hours = quarters / 4;
            int mins = (quarters % 4) * 15;
            char tzBuf[10];
            snprintf(tzBuf, sizeof(tzBuf), "%c%02d:%02d", tzSign, hours, mins);
            iso += String(tzBuf);
          } else {
            iso += "+08:00";
          }
        } else {
          iso += "+08:00";
        }
        return iso;
      }
    }
  }
  return "2026-09-17T09:00:00+08:00"; // Fallback to current Philippine timestamp
}

// Dynamically queries Firestore to fetch the student/parent linking config associated with this deviceId
bool fetchDeviceConfig() {
  Serial.println("[CONFIG] Fetching device registration config from Firestore...");
  String response;
  
  // Build URL for the device document
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += FIREBASE_PROJECT_ID;
  url += "/databases/(default)/documents/devices/";
  url += DEVICE_ID;
  url += "?key=";
  url += FIREBASE_API_KEY;

  flushModemBuffer();

  // Terminate previous sessions
  sendATCommand("AT+HTTPTERM", response, 3000);
  delay(500);

  // Configure SSL (authmode=0 to skip certificate check) BEFORE HTTP SSL activation
  sendATCommand("AT+CSSLCFG=\"authmode\",0,0", response, 3000);
  sendATCommand("AT+CSSLCFG=\"sslversion\",0,4", response, 3000);
  sendATCommand("AT+CSSLCFG=\"ignorelocaltime\",0,1", response, 3000);
  sendATCommand("AT+CSSLCFG=\"enableSNI\",0,1", response, 3000);

  // Init HTTP service
  if (!sendATCommand("AT+HTTPINIT", response, 5000)) {
    Serial.println("[CONFIG] AT+HTTPINIT failed: " + response);
    return false;
  }

  // Enable SSL
  sendATCommand("AT+HTTPSSL=1", response, 3000);
  
  // Bearer CID and SSL association
  sendATCommand("AT+HTTPPARA=\"CID\",1", response, 3000);
  sendATCommand("AT+HTTPPARA=\"SSLCFG\",0", response, 3000);

  // Set URL
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", response, 3000);

  // Execute GET (0 = GET)
  modemSerial.println("AT+HTTPACTION=0");

  // Wait for response
  unsigned long start = millis();
  String atResp = "";
  bool gotAction = false;
  int responseCode = -1;
  int dataSize = 0;

  while (millis() - start < 15000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      atResp += c;
    }
    int actionIdx = atResp.indexOf("+HTTPACTION:");
    if (actionIdx != -1) {
      int endLineIdx = atResp.indexOf("\n", actionIdx);
      if (endLineIdx != -1) {
        String urc = atResp.substring(actionIdx, endLineIdx);
        int comma1 = urc.indexOf(",");
        int comma2 = urc.indexOf(",", comma1 + 1);
        if (comma1 != -1 && comma2 != -1) {
          responseCode = urc.substring(comma1 + 1, comma2).toInt();
          dataSize = urc.substring(comma2 + 1).toInt();
        }
        gotAction = true;
        break;
      }
    }
    delay(100);
  }

  if (!gotAction || responseCode != 200 || dataSize <= 0) {
    Serial.printf("[CONFIG] HTTP GET failed. Code: %d, Size: %d. Falling back to default settings.\n", responseCode, dataSize);
    sendATCommand("AT+HTTPTERM", response, 3000);
    return false;
  }

  // Read response buffer using AT+HTTPREAD
  modemSerial.println("AT+HTTPREAD=0," + String(dataSize));
  
  // Read response from serial
  start = millis();
  String httpData = "";
  while (millis() - start < 5000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      httpData += c;
    }
    if (httpData.indexOf("OK") != -1) {
      break;
    }
    delay(50);
  }

  // Terminate HTTP
  sendATCommand("AT+HTTPTERM", response, 3000);

  // Parse fields
  String parsedParentUid = parseJsonStringField(httpData, "parentUid");
  String parsedParentPhone = parseJsonStringField(httpData, "parentPhoneNumber");
  String parsedStudentUid = parseJsonStringField(httpData, "studentUid");

  if (parsedParentUid.length() > 0) {
    dynamicParentUid = parsedParentUid;
  }
  if (parsedParentPhone.length() > 0) {
    dynamicParentPhone = parsedParentPhone;
  }
  if (parsedStudentUid.length() > 0) {
    dynamicStudentUid = parsedStudentUid;
  }
  
  String parsedPhone = parseJsonStringField(httpData, "phoneNumber");
  if (parsedPhone.length() > 0) {
    devicePhoneNumber = parsedPhone;
  }
  
  Serial.printf("[CONFIG] Loaded: Parent Phone: %s, Parent UID: %s, Student UID: %s\n", 
    dynamicParentPhone.c_str(), dynamicParentUid.c_str(), dynamicStudentUid.c_str());

  return true;
}

// Queries the SIM card's IMSI (Mobile Country + Mobile Network Code) and dynamically resolves the APN.
// This allows plug-and-play across different carriers (Globe, Smart, TNT, Dito) without re-coding.
String detectAPN() {
  Serial.println("[NETWORK] Detecting SIM card IMSI to resolve APN...");
  String response;
  if (sendATCommand("AT+CIMI", response, 2000)) {
    // response contains the 15-digit IMSI number
    response.trim();
    
    // Extract the numerical digits of IMSI
    int firstDigitIdx = -1;
    for (int i = 0; i < response.length(); i++) {
      if (isDigit(response.charAt(i))) {
        firstDigitIdx = i;
        break;
      }
    }
    
    if (firstDigitIdx != -1) {
      String imsi = response.substring(firstDigitIdx);
      Serial.println("[NETWORK] IMSI: " + imsi);
      
      // Philippine Country Code (515)
      if (imsi.startsWith("515")) {
        // MNC: 02 = Globe / TM
        if (imsi.substring(3).startsWith("02")) {
          Serial.println("[NETWORK] Auto-Detected: Globe / TM SIM.");
          return "http.globe.com.ph";
        }
        // MNC: 03 = Smart / TNT
        else if (imsi.substring(3).startsWith("03") || imsi.substring(3).startsWith("05")) {
          Serial.println("[NETWORK] Auto-Detected: Smart / TNT SIM.");
          return "internet";
        }
        // MNC: 18 = Dito
        else if (imsi.substring(3).startsWith("18") || imsi.substring(3).startsWith("66")) {
          Serial.println("[NETWORK] Auto-Detected: Dito SIM.");
          return "internet.dito.ph";
        }
      }
    }
  }
  Serial.println("[NETWORK] SIM detection failed or foreign SIM. Falling back to default APN: http.globe.com.ph");
  return "http.globe.com.ph";
}

// ============================================================================
// INMP441 I2S Microphone Driver & Voice Trigger Helper Routines
// ============================================================================

// Detected microphone channel in stereo frame: 0 for Left, 1 for Right
static int i2sActiveChannel = 0;

// DC-blocking high-pass filter state
static float dc_x1 = 0.0f;
static float dc_y1 = 0.0f;

// Process 32-bit raw sample from active I2S channel:
// - Shifts 24-bit MSB-aligned data with gain
// - Clamps to int16 range to prevent overflow / wrap-around distortion
// - Removes DC offset with a high-pass filter (~30 Hz cutoff at 16kHz)
static inline int16_t processMicSample(int32_t raw32) {
  int32_t s32 = raw32 >> 14; // +12 dB digital gain for clear speech pickup
  if (s32 > 32767) s32 = 32767;
  if (s32 < -32768) s32 = -32768;

  // 1-pole DC-blocking filter: y[n] = x[n] - x[n-1] + 0.985 * y[n-1]
  float x = (float)s32;
  float y = x - dc_x1 + 0.985f * dc_y1;
  dc_x1 = x;
  dc_y1 = y;

  if (y > 32767.0f) y = 32767.0f;
  if (y < -32768.0f) y = -32768.0f;
  return (int16_t)y;
}

// Initializes ESP32 I2S Peripheral for INMP441 Microphone
bool initI2SMicrophone() {
  Serial.println("[I2S] Initializing INMP441 digital microphone...");

  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT, // INMP441 REQUIRES 32-bit slot width
    .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT, // Read stereo to cleanly extract active L/R channel
#if defined(I2S_COMM_FORMAT_STAND_I2S)
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
#else
    .communication_format = (i2s_comm_format_t)(I2S_COMM_FORMAT_I2S),
#endif
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 8,
    .dma_buf_len = 64,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  esp_err_t err = i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  if (err != ESP_OK) {
    Serial.printf("[I2S] ERROR: Driver install failed (code: %d)\n", err);
    return false;
  }

  err = i2s_set_pin(I2S_PORT, &pin_config);
  if (err != ESP_OK) {
    Serial.printf("[I2S] ERROR: Set pin failed (code: %d)\n", err);
    return false;
  }

  // Ensure SD pin does not float when microphone is in high-impedance state
  gpio_set_pull_mode((gpio_num_t)I2S_SD, GPIO_PULLDOWN_ONLY);

  // 1. Hardware warm-up: discard initial 400ms to allow MEMS diaphragm & charge-pump to settle
  Serial.println("[I2S] Warming up microphone & discarding power-on transients...");
  unsigned long warmStart = millis();
  while (millis() - warmStart < 400) {
    int32_t dummyBuffer[64];
    size_t dummyBytes = 0;
    i2s_read(I2S_PORT, dummyBuffer, sizeof(dummyBuffer), &dummyBytes, pdMS_TO_TICKS(20));
  }

  // 2. Auto-detect active channel (Left vs Right):
  // INMP441 L/R tied to GND outputs on Left (0); tied to VDD outputs on Right (1).
  uint64_t leftEnergy = 0;
  uint64_t rightEnergy = 0;
  unsigned long calStart = millis();
  while (millis() - calStart < 150) {
    int32_t calBuffer[64];
    size_t calBytes = 0;
    i2s_read(I2S_PORT, calBuffer, sizeof(calBuffer), &calBytes, pdMS_TO_TICKS(20));
    size_t calFrames = (calBytes / sizeof(int32_t)) / 2;
    for (size_t f = 0; f < calFrames; f++) {
      int32_t leftSample = abs(calBuffer[f * 2] >> 14);
      int32_t rightSample = abs(calBuffer[f * 2 + 1] >> 14);
      leftEnergy += leftSample;
      rightEnergy += rightSample;
    }
  }

  if (rightEnergy > leftEnergy * 2) {
    i2sActiveChannel = 1;
    Serial.printf("[I2S] Active Channel: RIGHT (L-Energy: %llu, R-Energy: %llu)\n", leftEnergy, rightEnergy);
  } else {
    i2sActiveChannel = 0;
    Serial.printf("[I2S] Active Channel: LEFT (L-Energy: %llu, R-Energy: %llu)\n", leftEnergy, rightEnergy);
  }

  // Reset filter state & clear DMA buffer
  dc_x1 = 0.0f;
  dc_y1 = 0.0f;
  i2s_zero_dma_buffer(I2S_PORT);
  Serial.println("[I2S] INMP441 Microphone ready (calibrated & DC-filtered).");
  return true;
}

// Static inference buffer for Edge Impulse AI
static int16_t inference_buffer[EI_CLASSIFIER_RAW_SAMPLE_COUNT];

// Callback function for Edge Impulse to read raw audio data
static int microphone_audio_signal_get_data(size_t offset, size_t length, float *out_ptr) {
  for (size_t i = 0; i < length; i++) {
    out_ptr[i] = (float)inference_buffer[offset + i];
  }
  return 0;
}

// Samples INMP441 audio and runs Edge Impulse TinyML Neural Network
// Tuned to recognize genuine 'HELP' (>= 75%) and 'TABANG' (>= 55%)
// Casual chatter and random speech are safely filtered out!
bool checkVoiceHelpTrigger() {
  // Boot grace period: ignore all voice triggers during the first 5 seconds after startup
  if (millis() - systemBootReadyTime < BOOT_GRACE_PERIOD_MS) {
    int32_t discardBuffer[64];
    size_t discarded = 0;
    i2s_read(I2S_PORT, discardBuffer, sizeof(discardBuffer), &discarded, pdMS_TO_TICKS(10));
    return false;
  }

  static unsigned long lastCheck = 0;
  if (millis() - lastCheck < 80) return false;
  lastCheck = millis();

  // 1. Sound energy gate: sample 64 stereo frames (~4ms @ 16kHz)
  int32_t quickBuffer[128]; // 64 stereo frames
  size_t bytesRead = 0;
  esp_err_t err = i2s_read(I2S_PORT, quickBuffer, sizeof(quickBuffer), &bytesRead, pdMS_TO_TICKS(10));
  if (err != ESP_OK || bytesRead == 0) return false;

  size_t framesRead = (bytesRead / sizeof(int32_t)) / 2;
  int32_t peak = 0;
  int32_t sumEnergy = 0;
  int16_t quickMono[64];

  for (size_t f = 0; f < framesRead; f++) {
    int32_t raw = quickBuffer[f * 2 + i2sActiveChannel];
    int16_t sample = processMicSample(raw);
    quickMono[f] = sample;
    int32_t val = abs((int32_t)sample);
    if (val > peak) peak = val;
    sumEnergy += val;
  }

  int32_t avgEnergy = (framesRead > 0) ? (sumEnergy / (int32_t)framesRead) : 0;

  // Dual-condition sound energy gate:
  // In quiet surroundings, baseline noise peaks around 3000-4500, but average energy is < 900.
  // Genuine human voice speech ("TABANG" / "HELP") produces peak >= 5500 AND sustained energy >= 1300.
  if (peak < 5500 || avgEnergy < 1300) {
    return false;
  }

  // 2. Sound/Voice detected! Collect the full audio frame required by Edge Impulse model
  Serial.printf("\n[INMP441] Voice activity detected (Peak: %d, Avg: %d). Feeding audio to Edge Impulse AI...\n", peak, avgEnergy);
  size_t totalSamples = EI_CLASSIFIER_RAW_SAMPLE_COUNT;
  size_t samplesCollected = 0;

  // Preserve the initial samples that triggered the peak so the start of the word is NOT lost!
  for (size_t f = 0; f < framesRead && samplesCollected < totalSamples; f++) {
    inference_buffer[samplesCollected++] = quickMono[f];
  }

  unsigned long startCapture = millis();
  unsigned long maxTimeout = (EI_CLASSIFIER_RAW_SAMPLE_COUNT * 1000 / EI_CLASSIFIER_FREQUENCY) + 400;

  // Capture the remaining samples from the active microphone channel (stereo demuxed)
  while (samplesCollected < totalSamples && (millis() - startCapture < maxTimeout)) {
    int32_t chunk[128]; // 64 stereo frames
    size_t chunkBytes = 0;
    i2s_read(I2S_PORT, chunk, sizeof(chunk), &chunkBytes, pdMS_TO_TICKS(20));
    size_t framesInChunk = (chunkBytes / sizeof(int32_t)) / 2;

    for (size_t f = 0; f < framesInChunk && samplesCollected < totalSamples; f++) {
      int32_t raw = chunk[f * 2 + i2sActiveChannel];
      inference_buffer[samplesCollected++] = processMicSample(raw);
    }
  }

  if (samplesCollected < totalSamples) {
    Serial.println("[INMP441] Audio capture timeout. Skipping inference.");
    return false;
  }

  // 3. Prepare signal for Edge Impulse
  signal_t signal;
  signal.total_length = EI_CLASSIFIER_RAW_SAMPLE_COUNT;
  signal.get_data = &microphone_audio_signal_get_data;

  // 4. Run Edge Impulse Neural Network Inference
  ei_impulse_result_t result = { 0 };
  EI_IMPULSE_ERROR r = run_classifier(&signal, &result, false);
  if (r != EI_IMPULSE_OK) {
    Serial.printf("[EDGE IMPULSE ERROR] run_classifier failed (code: %d)\n", r);
    return false;
  }

  // 5. Inspect AI classification predictions (dynamically reads all labels)
  float helpScore = 0.0f;
  float tabangScore = 0.0f;
  float noiseScore = 0.0f;
  float otherScore = 0.0f;

  Serial.print("[AI PREDICTION] ");
  for (size_t ix = 0; ix < EI_CLASSIFIER_LABEL_COUNT; ix++) {
    const char* label = result.classification[ix].label;
    float score = result.classification[ix].value;
    Serial.printf("%s: %.1f%%  ", label, score * 100.0f);

    if (strcasecmp(label, "tabang") == 0) {
      tabangScore = score;
    } else if (strcasecmp(label, "help") == 0) {
      helpScore = score;
    } else if (strcasecmp(label, "noise") == 0 || strcasecmp(label, "noice") == 0) {
      noiseScore = score;
    } else {
      if (score > otherScore) otherScore = score;
    }
  }
  Serial.println();

  // 6. Tuned Keyword Confirmation:
  // - TABANG: requires >= 50% confidence, must exceed noise, help, and other speech
  // - HELP: requires >= 82% confidence, must exceed noise, tabang, and other speech (82% safely filters casual 'hello')
  bool isTabangConfirmed = (tabangScore >= 0.50f) && (tabangScore > noiseScore) && (tabangScore > helpScore) && (tabangScore > otherScore);
  bool isHelpConfirmed = (helpScore >= 0.82f) && (helpScore > noiseScore) && (helpScore > tabangScore) && (helpScore > otherScore);

  if (isTabangConfirmed || isHelpConfirmed) {
    const char* matchedWord = isTabangConfirmed ? "TABANG" : "HELP";
    lastVoiceKeyword = matchedWord;
    float confidence = isTabangConfirmed ? tabangScore : helpScore;
    Serial.println("\n***************************************************");
    Serial.printf("[EDGE IMPULSE CONFIRMED] Genuine '%s' recognized with %.1f%% confidence!\n", matchedWord, confidence * 100.0f);
    Serial.println("***************************************************");
    return true;
  }

  // Filtered out: Any casual word, chatter, or unconfirmed speech is safely ignored!
  if (helpScore >= 0.35f || tabangScore >= 0.35f) {
    Serial.printf("[FILTERED] Word '%s' ignored (help: %.1f%%, tabang: %.1f%%, noise: %.1f%%). Unconfirmed speech.\n",
                  (helpScore >= tabangScore) ? "help-like" : "tabang-like",
                  helpScore * 100.0f, tabangScore * 100.0f, noiseScore * 100.0f);
  }

  return false;
}

// Constructs standard 44-byte PCM WAV Header
void createWavHeader(uint8_t* header, uint32_t pcmDataSize, uint32_t sampleRate, uint16_t numChannels, uint16_t bitsPerSample) {
  uint32_t totalFileSize = pcmDataSize + 36;
  uint32_t byteRate = sampleRate * numChannels * (bitsPerSample / 8);
  uint16_t blockAlign = numChannels * (bitsPerSample / 8);

  header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
  header[4] = (uint8_t)(totalFileSize & 0xFF);
  header[5] = (uint8_t)((totalFileSize >> 8) & 0xFF);
  header[6] = (uint8_t)((totalFileSize >> 16) & 0xFF);
  header[7] = (uint8_t)((totalFileSize >> 24) & 0xFF);
  header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';

  header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
  header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0;
  header[20] = 1; header[21] = 0;
  header[22] = (uint8_t)numChannels; header[23] = 0;
  header[24] = (uint8_t)(sampleRate & 0xFF);
  header[25] = (uint8_t)((sampleRate >> 8) & 0xFF);
  header[26] = (uint8_t)((sampleRate >> 16) & 0xFF);
  header[27] = (uint8_t)((sampleRate >> 24) & 0xFF);
  header[28] = (uint8_t)(byteRate & 0xFF);
  header[29] = (uint8_t)((byteRate >> 8) & 0xFF);
  header[30] = (uint8_t)((byteRate >> 16) & 0xFF);
  header[31] = (uint8_t)((byteRate >> 24) & 0xFF);
  header[32] = (uint8_t)blockAlign; header[33] = 0;
  header[34] = (uint8_t)bitsPerSample; header[35] = 0;

  header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
  header[40] = (uint8_t)(pcmDataSize & 0xFF);
  header[41] = (uint8_t)((pcmDataSize >> 8) & 0xFF);
  header[42] = (uint8_t)((pcmDataSize >> 16) & 0xFF);
  header[43] = (uint8_t)((pcmDataSize >> 24) & 0xFF);
}

// Encodes raw byte buffer into Base64 String
String encodeBase64(const uint8_t* input, size_t inputLen) {
  static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  String output = "";
  size_t expectedLen = ((inputLen + 2) / 3) * 4;
  if (!output.reserve(expectedLen + 16)) {
    Serial.println("[INMP441] WARNING: Failed to reserve heap memory for Base64 string!");
    return "";
  }

  for (size_t i = 0; i < inputLen; i += 3) {
    uint32_t b0 = input[i];
    uint32_t b1 = (i + 1 < inputLen) ? input[i + 1] : 0;
    uint32_t b2 = (i + 2 < inputLen) ? input[i + 2] : 0;
    uint32_t triple = (b0 << 16) | (b1 << 8) | b2;

    output += b64_table[(triple >> 18) & 0x3F];
    output += b64_table[(triple >> 12) & 0x3F];
    output += (i + 1 < inputLen) ? b64_table[(triple >> 6) & 0x3F] : '=';
    output += (i + 2 < inputLen) ? b64_table[triple & 0x3F] : '=';
  }
  return output;
}

// Records an audio clip from INMP441 and returns Base64 WAV string
// Uses telephony-standard 8000 Hz to prevent ESP32 heap exhaustion & Firebase HTTP 400
String recordAndEncodeAudioClip(size_t durationSeconds) {
  const uint32_t CLIP_RATE = 8000;
  const size_t clipDuration = 1; // 1 second audio @ 8kHz = 8000 samples = 16000 bytes
  size_t pcmDataSize = CLIP_RATE * sizeof(int16_t) * clipDuration;
  size_t totalWavSize = 44 + pcmDataSize;

  Serial.printf("[INMP441] Recording %d-second audio clip at %u Hz...\n", clipDuration, CLIP_RATE);

  uint8_t* wavBuffer = (uint8_t*) malloc(totalWavSize);
  if (!wavBuffer) {
    Serial.println("[INMP441] ERROR: Out of memory for audio clip buffer!");
    return "";
  }

  // Write WAV header for 8000 Hz, Mono, 16-bit
  createWavHeader(wavBuffer, pcmDataSize, CLIP_RATE, 1, 16);

  uint8_t* pcmPtr = wavBuffer + 44;
  size_t bytesReadTotal = 0;
  unsigned long startRec = millis();

  // If SAMPLE_RATE is 16kHz and target is 8kHz, decimate by 2 (take 1 out of 2 frames).
  int frameStep = (SAMPLE_RATE >= 16000) ? 2 : 1;
  int frameCounter = 0;

  i2s_zero_dma_buffer(I2S_PORT);

  while (bytesReadTotal < pcmDataSize && (millis() - startRec < (clipDuration * 1000 + 1000))) {
    int32_t i2sChunk[128]; // 64 stereo frames
    size_t bytesReadThisChunk = 0;
    i2s_read(I2S_PORT, i2sChunk, sizeof(i2sChunk), &bytesReadThisChunk, pdMS_TO_TICKS(50));
    size_t framesRead = (bytesReadThisChunk / sizeof(int32_t)) / 2;

    for (size_t f = 0; f < framesRead; f++) {
      if ((frameCounter % frameStep) == 0) {
        if (bytesReadTotal + sizeof(int16_t) <= pcmDataSize) {
          int32_t raw = i2sChunk[f * 2 + i2sActiveChannel];
          int16_t sampleVal = processMicSample(raw);
          memcpy(pcmPtr + bytesReadTotal, &sampleVal, sizeof(int16_t));
          bytesReadTotal += sizeof(int16_t);
        }
      }
      frameCounter++;
    }
  }

  Serial.printf("[INMP441] Recorded %d bytes of audio data.\n", bytesReadTotal);

  // Encode to Base64
  String base64Wav = encodeBase64(wavBuffer, 44 + bytesReadTotal);
  free(wavBuffer);

  Serial.printf("[INMP441] Audio clip encoded to Base64 (%d chars).\n", base64Wav.length());
  return base64Wav;
}


// Main Emergency Dispatcher Routine (Button Press or Voice 'HELP')
void triggerEmergencyAlertProcess(const String& triggerSource) {
  Serial.printf("\n=========================================\n");
  Serial.printf("[ALERT DISPATCHER] Triggered by: %s\n", triggerSource.c_str());
  Serial.printf("=========================================\n");

  // 1. Record 3-second WAV Audio Clip from INMP441 Mic
  String audioBase64 = recordAndEncodeAudioClip(3);

  // 2. Obtain GPS Location
  double lat = 0.0;
  double lon = 0.0;
  bool hasGPS = getGPSLocation(lat, lon);

  if (!hasGPS) {
    Serial.println("[WARNING] GPS lock pending. Using default fallback coordinates (Manila).");
    lat = 14.5995;
    lon = 120.9842;
  }
  Serial.printf("[INFO] Coordinates: Lat: %.6f, Lon: %.6f\n", lat, lon);

  // 3. Send Backup SMS to Parent
  bool smsSent = sendSMSAlert(lat, lon);
  if (smsSent) {
    Serial.println("[SUCCESS] Backup SMS alert sent to parent."); 
  } else {
    Serial.println("[ERROR] Failed to send backup SMS.");
  }

  delay(3000);
  flushModemBuffer();                                                                                                                                                 

  // 4. Trigger HTTPS alert upload with audio payload to Firebase Firestore                                                                         
  bool firebaseSent = triggerFirebaseAlert(lat, lon, triggerSource, audioBase64);
  if (firebaseSent) {
    Serial.println("[SUCCESS] Emergency alert with audio clip successfully uploaded to Firebase!");
  } else {
    Serial.println("[ERROR] Failed to upload emergency alert to Firebase.");
  }
}
