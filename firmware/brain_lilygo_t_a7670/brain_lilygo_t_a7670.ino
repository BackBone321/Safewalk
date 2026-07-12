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

// Function Prototypes
void initializeA7670();
bool sendATCommand(const String& cmd, String& response, unsigned long timeout = 1000);
bool setupGPS();
bool getGPSLocation(double& lat, double& lon); 
String getField(const String& data, char separator, int index);
bool setupNetwork();
bool triggerFirebaseAlert(double lat, double lon);
bool sendSMSAlert(double lat, double lon);
void flushModemBuffer();
bool fetchDeviceConfig();
String parseJsonStringField(const String& json, const String& fieldName);
String getNetworkTimeRFC3339();
String detectAPN();

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

  Serial.println("System Ready. Press button on GPIO 14 to send SOS alert.");
}

void loop() {
  // Read state of the tactile button (active LOW)
  int reading = digitalRead(BUTTON_PIN);

  if (reading != lastButtonState) {
    lastDebounceTime = millis();
  }

  if ((millis() - lastDebounceTime) > DEBOUNCE_DELAY) {
    if (reading != buttonState) {
      buttonState = reading;

      // Detect button pressed (transition from HIGH to LOW)
      if (buttonState == LOW) {
        Serial.println("\n[ALERT] Tactile Button Pressed! Triggering SOS Alert...");
        
        double lat = 0.0;
        double lon = 0.0;
        bool hasGPS = getGPSLocation(lat, lon);

        if (!hasGPS) {
          Serial.println("[WARNING] No GPS signal yet. Sending alert with default placeholder coordinates.");
          // Default to Manila coordinates if GPS is not locked for demo/fallback
          lat = 14.5995;
          lon = 120.9842;
        }

        Serial.printf("[INFO] Location Coordinates: Lat: %.6f, Lon: %.6f\n", lat, lon);

        // 1. Send SMS fallback alert
        bool smsSent = sendSMSAlert(lat, lon);
        if (smsSent) {
          Serial.println("[SUCCESS] Backup SMS alert sent to parent.");
        } else {
          Serial.println("[ERROR] Failed to send backup SMS.");
        }

        // Give modem 3 seconds to finish SMS processing, then flush all
        // leftover bytes so they don't contaminate the AT+HTTPINIT response
        delay(3000);
        flushModemBuffer();

        // 2. Trigger Firebase alert using cellular data
        bool firebaseSent = triggerFirebaseAlert(lat, lon);
        if (firebaseSent) {
          Serial.println("[SUCCESS] Live alert stored in Firebase Firestore.");
        } else {
          Serial.println("[ERROR] Failed to upload alert to Firestore.");
        }
      }
    }
  }

  lastButtonState = reading;

  // Periodically read any incoming serial data from the modem to keep buffers clear
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
  bool isResponsive = sendATCommand("AT", response, 500);

  if (!isResponsive) {
    Serial.println("[MODEM] Modem is unresponsive. Pulsing PWRKEY to power on...");
    
    // To trigger power-on: pulse PWRKEY HIGH (transistor ON, pulling A7670 PWRKEY low)
    // for 2 seconds, then pull LOW (transistor OFF).
    digitalWrite(BOARD_PWRKEY, HIGH);
    delay(2000);
    digitalWrite(BOARD_PWRKEY, LOW);
    
    // Wait for boot sequence (approx 8-10 seconds)
    Serial.println("[MODEM] Waiting for boot...");
    delay(8000);
    
    // Check communication again
    int retries = 10;
    while (retries > 0) {
      if (sendATCommand("AT", response, 500)) {
        Serial.println("[MODEM] Modem is online and responding to AT commands.");
        break;
      }
      delay(1000);
      retries--;
    }
    
    if (retries == 0) {
      Serial.println("[FATAL] Modem failed to power on. Please check battery/power connections.");
      return;
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
  } else {
    Serial.println("[NETWORK] WARNING: Failed to activate App Network interface!");
  }

  // Fetch device configuration dynamically from Firestore
  fetchDeviceConfig();

  return true;
}

// Sends the SOS alert metadata directly to Firestore via HTTPS REST API
// Uses the SIMCom A7670 native AT+HTTP stack (correct command set for this modem)
bool triggerFirebaseAlert(double lat, double lon) {
  // Refresh configuration dynamically before sending alert to use the latest linking details
  fetchDeviceConfig();

  Serial.println("[FIREBASE] Initiating HTTPS via modem AT+HTTPINIT...");
  String response;

  // Safety flush — clear any leftover UART bytes before starting HTTP commands
  flushModemBuffer();

  // Get timestamp from cellular network
  String rfcTimestamp = getNetworkTimeRFC3339();

  // Construct JSON body
  String jsonBody = "{\"fields\":{";
  jsonBody += "\"deviceId\":{\"stringValue\":\"" + String(DEVICE_ID) + "\"},";
  jsonBody += "\"uid\":{\"stringValue\":\"" + (dynamicStudentUid.length() > 0 ? dynamicStudentUid : String(DEVICE_ID)) + "\"},";
  jsonBody += "\"studentUid\":{\"stringValue\":\"" + (dynamicStudentUid.length() > 0 ? dynamicStudentUid : String(DEVICE_ID)) + "\"},";
  jsonBody += "\"fullName\":{\"stringValue\":\"" + String(DEVICE_NAME) + "\"},";
  jsonBody += "\"phoneNumber\":{\"stringValue\":\"" + (devicePhoneNumber.length() > 0 ? devicePhoneNumber : String(DEVICE_PHONE)) + "\"},";
  jsonBody += "\"parentUid\":{\"stringValue\":\"" + (dynamicParentUid.length() > 0 ? dynamicParentUid : String(PARENT_UID)) + "\"},";
  jsonBody += "\"parentPhoneNumber\":{\"stringValue\":\"" + (dynamicParentPhone.length() > 0 ? dynamicParentPhone : String(PARENT_PHONE)) + "\"},";
  jsonBody += "\"type\":{\"stringValue\":\"sos\"},";
  jsonBody += "\"severity\":{\"stringValue\":\"high\"},";
  jsonBody += "\"status\":{\"stringValue\":\"active\"},";
  jsonBody += "\"message\":{\"stringValue\":\"EMERGENCY: SOS tactile button triggered by tracker.\"},";
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
  modemSerial.println("AT+HTTPDATA=" + String(jsonBody.length()) + ",10000");

  unsigned long t = millis();
  String atResp = "";
  bool gotDownload = false;
  while (millis() - t < 6000) {
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

  // Step 7: Send the JSON body
  modemSerial.print(jsonBody);
  delay(1000);

  // Wait for OK
  atResp = "";
  t = millis();
  while (millis() - t < 3000) {
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
    String message = "ALERT: Safewalk SOS emergency triggered! Child Location:\n";
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
        
        // Build ISO 8601 string: 20yy-mm-ddThh:mm:ss
        String iso = "20" + yy + "-" + mm + "-" + dd + "T" + hh + ":" + min + ":" + ss;
        
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
            iso += "Z";
          }
        } else {
          iso += "Z";
        }
        return iso;
      }
    }
  }
  return "2026-07-08T12:00:00Z"; // Fallback to current conversation date
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
