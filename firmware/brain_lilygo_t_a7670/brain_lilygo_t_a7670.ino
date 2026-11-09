/*
 * Safewalk IoT Tracker - LILYGO T-A7670 V3
 * Button SOS + Edge Impulse "help"/"Tabang" keyword SOS + GPS/SMS/Firestore.
 */

// Saves ~10KB RAM for the Edge Impulse MFCC path (required on ESP32 + modem stack).
#define EIDSP_QUANTIZE_FILTERBANK 0

#include <HardwareSerial.h>
#include <driver/i2s.h>
#include <driver/gpio.h>
#include <string.h>
#include <safewalk-voice-help_inferencing.h>

// Board Pin Definitions (LILYGO T-A7670 V3)
#define BOARD_TXD       26  // ESP32 TX (connects to A7670 RXD)
#define BOARD_RXD       27  // ESP32 RX (connects to A7670 TXD)
#define BOARD_PWRKEY    4
#define BOARD_RESET     5
#define BOARD_POWERON   12  // Enables onboard voltage regulator for cellular module
#define BOARD_PIN_DTR   25  // Modem DTR. Held LOW until the microphone takes this pin as I2S WS.
#define BOARD_PIN_RI    33  // Modem RING. Microphone SCK uses this same header pin after boot.

// Tactile Button Pin (header IO14 to GND). GPIO 32 is the microphone data pin.
#define BUTTON_PIN      14

// INMP441 I2S — matches the soldered wiring on this board.
#define I2S_WS          25  // Word Select / LRCLK  -> header IO25
#define I2S_SD          32  // Serial Data          -> header IO32
#define I2S_SCK         33  // Bit Clock / BCLK     -> header IO33
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

// Dynamic variables populated at runtime from SIM (AT+CNUM) and Firestore
String devicePhoneNumber = "";
String dynamicParentPhone = "";
String dynamicGuardianPhonesCsv = "";
String dynamicStudentName = "";
String dynamicParentUid = "";
String dynamicStudentUid = "";
bool pendingEmergencySMSCoordinateUpdate = false;
String pendingUpdateTriggerType = "sos";

#define TINY_GSM_MODEM_A7672X
#include <TinyGsmClient.h>

// Serial interface for communicating with A7670
HardwareSerial modemSerial(1);

// Serial interface for communicating with the external GPS module (Quectel L76K)
#define BOARD_GPS_TX_PIN    21
#define BOARD_GPS_RX_PIN    22
HardwareSerial gpsSerial(2);

// Real-time continuous GPS tracking state
double globalCurrentLat = 0.0;
double globalCurrentLon = 0.0;
bool globalHasGPSFix = false;
unsigned long globalLastFixTime = 0;
String gpsNmeaLineBuffer = "";

// TinyGSM instance (used for GPRS connection only)
TinyGsm modem(modemSerial);

// SOS buttons. serviceSosButtons() latches one press; loop() sends the alert.
static bool sosPressPending = false;

// Duplicate-alert prevention: cooldown starts AFTER the alert finishes, then quiet audio is required.
unsigned long lastVoiceTriggerTime = 0;
const unsigned long VOICE_COOLDOWN_MS = 30000;
bool voiceDetectorArmed = true;
bool voiceKeywordCurrentlyActive = false;
bool voiceSliceWasQuiet = true;               // Last classified slice was silence / Noise
String lastVoiceKeyword = "TABANG";
String lastSmsSubmissionStatus = "none";      // "submitted" | "failed" | "none" (modem accept, not delivery)

// Edge Impulse continuous keyword spotting (official slice API).
// Model window = 2.0s @ 16 kHz (32000 samples). Each slice = 0.5s (8000 samples).
// Labels in the deployed model: "Noise", "Tabang", "help"
const float HELP_SCORE_MIN = 0.70f;            // Previous working firmware used ~0.75
const float TABANG_SCORE_MIN = 0.55f;          // Previous working firmware used ~0.55
const float KEYWORD_OVER_NOISE = 0.15f;        // Keyword must beat Noise, not merely match it
const int32_t VOICE_SLICE_PEAK_MIN = 2200;     // INMP441 must actually hear speech
const int32_t VOICE_SLICE_AVG_MIN = 500;
const uint8_t VOICE_HITS_REQUIRED = 2;         // Two consecutive 0.5s slices before SOS

// Boot grace period: prevents any false triggers during startup while hardware/network stabilizes
unsigned long systemBootReadyTime = 0;
const unsigned long BOOT_GRACE_PERIOD_MS = 5000; // 5-second grace period after boot

// Function Prototypes
void initializeA7670();
bool sendATCommand(const String& cmd, String& response, unsigned long timeout = 1000);
bool setupGPS();
void processGPSStream();
void parseNMEASentence(const String& sentence);
bool queryA7670InternalGNSS(double& lat, double& lon);
bool queryA7670CGPSINFO(double& lat, double& lon);
bool queryA7670CellularLBS(double& lat, double& lon);
bool syncDeviceCoordinatesToFirestore(double lat, double lon);
bool getGPSLocation(double& lat, double& lon); 
String getField(const String& data, char separator, int index);
bool setupNetwork();
bool triggerFirebaseAlert(double lat, double lon, const String& triggerType = "sos");
bool setupSMS();
void logSmsDiagnostics();
bool sendSMSAlert(double lat, double lon, const String& triggerType = "sos");
bool sendSMSViaModem(const String& recipient, const String& message, int smsServiceDomain);
bool sendSMSViaModemWithFallbacks(const String& recipientIntl, const String& message);
String formatPhoneNumberForSMS(const String& inputRaw);
String formatPhoneNumberLocalPH(const String& intlOrLocal);
void abortPendingSmsPrompt();
void checkIncomingModemData();
void handleIncomingSMS(int smsIndex);
void flushModemBuffer();
bool fetchDeviceConfig();
bool autoRegisterDeviceInFirestore();
String parseJsonStringField(const String& json, const String& fieldName);
double parseJsonDoubleField(const String& json, const String& fieldName);
String getNetworkTimeRFC3339();
String detectAPN();

// INMP441 Audio Prototypes
bool initI2SMicrophone();
void recoverMicrophoneListening();
bool checkVoiceHelpTrigger();
void serviceSosButtons();
void triggerEmergencyAlertProcess(const String& triggerSource);

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(1000);
  Serial.println("=========================================");
  Serial.println("   Safewalk Tracker starting up...       ");
  Serial.println("=========================================");

  // GPIO 14 is the wired help switch to GND.
  // GPIO 0 (BOOT) is not an alert button. On this board it sits low beside the modem
  // and was sending a new alert on every twitch.
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // Initialize hardware serial for modem
  modemSerial.begin(MODEM_BAUD, SERIAL_8N1, BOARD_RXD, BOARD_TXD);

  // Initialize power lines and turn on module
  initializeA7670();

  // Configure GPS
  setupGPS();

  // Connect to Network/APN
  setupNetwork();

  // Initialize Cellular SMS Subsystem (Text mode, GSM charset, SMS parameters)
  setupSMS();

  // Initialize INMP441 I2S Microphone + Edge Impulse continuous classifier
  initI2SMicrophone();
  recoverMicrophoneListening();

  systemBootReadyTime = millis();
  Serial.println("System Ready. Button SOS + voice HELP/TABANG active.");
  Serial.printf("[VOICE] Model %s v%d @ %d Hz | labels:",
                EI_CLASSIFIER_PROJECT_NAME,
                EI_CLASSIFIER_PROJECT_DEPLOY_VERSION,
                EI_CLASSIFIER_FREQUENCY);
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
    Serial.printf(" [%s]", ei_classifier_inferencing_categories[i]);
  }
  Serial.println();
}

// One alert per press of GPIO 14. The pin must be released before the next press counts.
void serviceSosButtons() {
  static int lastRaw = HIGH;
  static unsigned long changeMs = 0;
  static bool pressed = false;
  static bool armed = false;
  static bool inited = false;

  if (sosPressPending) return;

  unsigned long now = millis();
  if (!inited) {
    lastRaw = digitalRead(BUTTON_PIN);
    changeMs = now;
    pressed = (lastRaw == LOW);
    armed = !pressed;
    inited = true;
  }

  int raw = digitalRead(BUTTON_PIN);
  if (raw != lastRaw) {
    lastRaw = raw;
    changeMs = now;
  }
  if ((now - changeMs) < 80) return;

  if (raw == LOW) {
    if (!pressed && armed) {
      pressed = true;
      armed = false;
      sosPressPending = true;
      lastVoiceKeyword = "SOS BUTTON";
      Serial.println("\n[BUTTON] Pressed once. Sending location and SMS.");
      return;
    }
    pressed = true;
  } else {
    if (pressed) {
      Serial.println("[BUTTON] Released. Press again for one new alert.");
    }
    pressed = false;
    armed = true;
  }
}

void loop() {
  // Button is sampled here and also inside the microphone capture, so a press
  // is not lost while a keyword recording is in progress.
  serviceSosButtons();
  if (sosPressPending) {
    sosPressPending = false;
    triggerEmergencyAlertProcess("sos");
    return;
  }

  // Continuous Help/Tabang listening. SOS only after a confirmed keyword while armed.
  bool voiceTriggerDetected = checkVoiceHelpTrigger();
  if (voiceTriggerDetected) {
    voiceKeywordCurrentlyActive = true;
    if (voiceDetectorArmed && (millis() - lastVoiceTriggerTime > VOICE_COOLDOWN_MS)) {
      voiceDetectorArmed = false;
      lastVoiceTriggerTime = millis();
      Serial.printf("[VOICE] DETECTED: %s\n", lastVoiceKeyword.c_str());
      triggerEmergencyAlertProcess("voice_help");
    }
  } else {
    if (voiceKeywordCurrentlyActive) {
      voiceKeywordCurrentlyActive = false;
    }
    if (!voiceDetectorArmed &&
        !voiceKeywordCurrentlyActive &&
        voiceSliceWasQuiet &&
        (millis() - lastVoiceTriggerTime > VOICE_COOLDOWN_MS)) {
      voiceDetectorArmed = true;
      Serial.println("[VOICE] Re-armed. Say HELP or TABANG.");
    }
  }

  serviceSosButtons();
  if (sosPressPending) {
    sosPressPending = false;
    triggerEmergencyAlertProcess("sos");
    return;
  }

  // 3. Process continuous GPS serial stream to maintain exact real-time coordinates
  processGPSStream();

  // 4. Periodic background telemetry: every 60s, query onboard GNSS and sync exact coordinates to Firestore
  static unsigned long lastLocationSyncTime = 0;
  if (millis() - lastLocationSyncTime > 60000) {
    lastLocationSyncTime = millis();
    double currentLat = 0.0;
    double currentLon = 0.0;
    if (queryA7670InternalGNSS(currentLat, currentLon) ||
        queryA7670CGPSINFO(currentLat, currentLon) ||
        (globalHasGPSFix && (millis() - globalLastFixTime < 120000))) {
      if (currentLat == 0.0) {
        currentLat = globalCurrentLat;
        currentLon = globalCurrentLon;
      }
      syncDeviceCoordinatesToFirestore(currentLat, currentLon);
    }
  }

  // 5. Follow-up SMS if satellite lock was acquired after emergency trigger
  if (pendingEmergencySMSCoordinateUpdate && globalHasGPSFix && (millis() - globalLastFixTime < 30000)) {
    if (globalCurrentLat != 0.0 && globalCurrentLon != 0.0) {
      pendingEmergencySMSCoordinateUpdate = false;
      Serial.println("\n[SMS] Live GPS lock established after SOS! Transmitting coordinate update SMS...");
      sendSMSAlert(globalCurrentLat, globalCurrentLon, pendingUpdateTriggerType + "_update");
    }
  }

  // 6. Periodically monitor incoming serial data and SMS notifications (+CMTI) from modem
  checkIncomingModemData();
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
  pinMode(BOARD_PIN_RI, INPUT);

  // 1. Turn on the power regulator/LDO to the cellular modem
  digitalWrite(BOARD_POWERON, HIGH);
  delay(500); // Give the regulator time to stabilize voltage

  // 2. Release reset pin (keep high)
  digitalWrite(BOARD_RESET, HIGH);

  // 3. Hold DTR low so the modem stays awake through startup.
  //    GPIO 25 is then handed to the INMP441 word-select in initI2SMicrophone().
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

// Configures and starts GPS session for external Quectel L76K GPS and internal SIMCom GNSS
bool setupGPS() {
  Serial.println("[GPS] Initializing GPS systems...");

  // 1. Initialize Serial2 for external GPS module (Quectel L76K) on RX: GPIO 22, TX: GPIO 21
  gpsSerial.begin(9600, SERIAL_8N1, BOARD_GPS_RX_PIN, BOARD_GPS_TX_PIN);

  // 2. Power on internal GNSS on the SIMCom A7670 module itself
  String resp;
  Serial.println("[GPS] Powering on SIMCom A7670 onboard GNSS (AT+CGNSSPWR=1)...");
  sendATCommand("AT+CGNSSPWR=1", resp, 3000);
  Serial.println("[GPS] AT+CGNSSPWR response: " + resp);
  sendATCommand("AT+CGPS=1", resp, 2000);
  sendATCommand("AT+CGNSSMODE=1", resp, 2000);
  sendATCommand("AT+CGNSSPORTSWITCH=1,1", resp, 2000);

  Serial.println("[GPS] External & Onboard GPS services initiated.");
  return true;
}

// Parses standard NMEA sentences ($GNGGA, $GPGGA, $GNRMC, $GPRMC) to extract exact lat/lon
void parseNMEASentence(const String& sentence) {
  // 1. Check GGA sentence for 3D fix
  if (sentence.startsWith("$GNGGA") || sentence.startsWith("$GPGGA")) {
    String fixStr = getField(sentence, ',', 6);
    int fix = fixStr.toInt();
    if (fix > 0) {
      String latStr = getField(sentence, ',', 2);
      String latNS  = getField(sentence, ',', 3);
      String lonStr = getField(sentence, ',', 4);
      String lonEW  = getField(sentence, ',', 5);

      if (latStr.length() > 0 && lonStr.length() > 0) {
        double rawLat = latStr.toDouble();
        int latDeg = (int)(rawLat / 100);
        double latMin = rawLat - (latDeg * 100);
        double calcLat = latDeg + (latMin / 60.0);
        if (latNS == "S") calcLat = -calcLat;

        double rawLon = lonStr.toDouble();
        int lonDeg = (int)(rawLon / 100);
        double lonMin = rawLon - (lonDeg * 100);
        double calcLon = lonDeg + (lonMin / 60.0);
        if (lonEW == "W") calcLon = -calcLon;

        if (calcLat != 0.0 && calcLon != 0.0) {
          globalCurrentLat = calcLat;
          globalCurrentLon = calcLon;
          globalHasGPSFix = true;
          globalLastFixTime = millis();
        }
      }
    }
  }
  // 2. Check RMC sentence for navigation fix
  else if (sentence.startsWith("$GNRMC") || sentence.startsWith("$GPRMC")) {
    String status = getField(sentence, ',', 2);
    if (status == "A") { // 'A' = Active / Valid fix
      String latStr = getField(sentence, ',', 3);
      String latNS  = getField(sentence, ',', 4);
      String lonStr = getField(sentence, ',', 5);
      String lonEW  = getField(sentence, ',', 6);

      if (latStr.length() > 0 && lonStr.length() > 0) {
        double rawLat = latStr.toDouble();
        int latDeg = (int)(rawLat / 100);
        double latMin = rawLat - (latDeg * 100);
        double calcLat = latDeg + (latMin / 60.0);
        if (latNS == "S") calcLat = -calcLat;

        double rawLon = lonStr.toDouble();
        int lonDeg = (int)(rawLon / 100);
        double lonMin = rawLon - (lonDeg * 100);
        double calcLon = lonDeg + (lonMin / 60.0);
        if (lonEW == "W") calcLon = -calcLon;

        if (calcLat != 0.0 && calcLon != 0.0) {
          globalCurrentLat = calcLat;
          globalCurrentLon = calcLon;
          globalHasGPSFix = true;
          globalLastFixTime = millis();
        }
      }
    }
  }
}

// Continuously reads and buffers NMEA data from the GPS UART
void processGPSStream() {
  while (gpsSerial.available()) {
    char c = gpsSerial.read();
    if (c == '\n') {
      gpsNmeaLineBuffer.trim();
      if (gpsNmeaLineBuffer.length() > 0) {
        if (gpsNmeaLineBuffer.startsWith("$GNGGA") || gpsNmeaLineBuffer.startsWith("$GPGGA") ||
            gpsNmeaLineBuffer.startsWith("$GNRMC") || gpsNmeaLineBuffer.startsWith("$GPRMC")) {
          parseNMEASentence(gpsNmeaLineBuffer);
        }
      }
      gpsNmeaLineBuffer = "";
    } else if (c != '\r') {
      if (gpsNmeaLineBuffer.length() < 128) {
        gpsNmeaLineBuffer += c;
      }
    }
  }
}

// Queries A7670 internal GNSS engine via AT+CGNSSINFO
bool queryA7670InternalGNSS(double& lat, double& lon) {
  String resp;
  if (!sendATCommand("AT+CGNSSINFO", resp, 2000)) {
    return false;
  }
  int idx = resp.indexOf("+CGNSSINFO:");
  if (idx == -1) return false;
  String line = resp.substring(idx);
  int endL = line.indexOf("\n");
  if (endL != -1) line = line.substring(0, endL);
  line.trim();

  // If response has empty fields like "+CGNSSINFO: ,,,,,,,,", no satellite 3D fix yet
  if (line.indexOf(",,,,") != -1) {
    String sats = getField(line, ',', 14);
    if (sats.length() > 0 && sats != "0") {
      Serial.printf("[GNSS] Satellites in view: %s (Acquiring lock... move outdoors if indoors)\n", sats.c_str());
    }
    return false;
  }

  Serial.println("[GNSS] Live AT+CGNSSINFO line: " + line);

  for (int offset = 1; offset <= 4; offset++) {
    String pLat = getField(line, ',', offset);
    String pNS  = getField(line, ',', offset + 1);
    String pLon = getField(line, ',', offset + 2);
    String pEW  = getField(line, ',', offset + 3);

    if ((pNS == "N" || pNS == "S") && (pEW == "E" || pEW == "W") && pLat.length() >= 4 && pLon.length() >= 4) {
      double rawLat = pLat.toDouble();
      int latDeg = (int)(rawLat / 100);
      double latMin = rawLat - (latDeg * 100);
      lat = latDeg + (latMin / 60.0);
      if (pNS == "S") lat = -lat;

      double rawLon = pLon.toDouble();
      int lonDeg = (int)(rawLon / 100);
      double lonMin = rawLon - (lonDeg * 100);
      lon = lonDeg + (lonMin / 60.0);
      if (pEW == "W") lon = -lon;

      if (lat != 0.0 && lon != 0.0) {
        globalCurrentLat = lat;
        globalCurrentLon = lon;
        globalHasGPSFix = true;
        globalLastFixTime = millis();
        Serial.printf("[GNSS] A7670 Internal GNSS exact satellite fix: Lat: %.6f, Lon: %.6f\n", lat, lon);
        return true;
      }
    }
  }
  return false;
}

// Queries A7670 GPS engine via AT+CGPSINFO
bool queryA7670CGPSINFO(double& lat, double& lon) {
  String resp;
  if (!sendATCommand("AT+CGPSINFO", resp, 2000)) {
    return false;
  }
  int idx = resp.indexOf("+CGPSINFO:");
  if (idx == -1) return false;
  String line = resp.substring(idx);
  int endL = line.indexOf("\n");
  if (endL != -1) line = line.substring(0, endL);
  line.trim();

  String latStr = getField(line, ',', 1);
  String latNS  = getField(line, ',', 2);
  String lonStr = getField(line, ',', 3);
  String lonEW  = getField(line, ',', 4);

  if ((latNS == "N" || latNS == "S") && (lonEW == "E" || lonEW == "W") && latStr.length() >= 4 && lonStr.length() >= 4) {
    double rawLat = latStr.toDouble();
    int latDeg = (int)(rawLat / 100);
    double latMin = rawLat - (latDeg * 100);
    lat = latDeg + (latMin / 60.0);
    if (latNS == "S") lat = -lat;

    double rawLon = lonStr.toDouble();
    int lonDeg = (int)(rawLon / 100);
    double lonMin = rawLon - (lonDeg * 100);
    lon = lonDeg + (lonMin / 60.0);
    if (lonEW == "W") lon = -lon;

    if (lat != 0.0 && lon != 0.0) {
      globalCurrentLat = lat;
      globalCurrentLon = lon;
      globalHasGPSFix = true;
      globalLastFixTime = millis();
      Serial.printf("[CGPS] A7670 CGPSINFO exact fix: Lat: %.6f, Lon: %.6f\n", lat, lon);
      return true;
    }
  }
  return false;
}

// Queries A7670 cellular base station location (works indoors when satellites are blocked)
bool queryA7670CellularLBS(double& lat, double& lon) {
  Serial.println("[LBS] Querying A7670 cellular base station location (AT+CLBS=1,1)...");

  // Clear pending characters from serial buffer
  while (modemSerial.available()) modemSerial.read();

  // Send AT+CLBS=1,1 to query location from network
  modemSerial.println("AT+CLBS=1,1");

  unsigned long start = millis();
  String lbsResponse = "";
  // Wait up to 10 seconds specifically for +CLBS: to arrive from cellular network
  while (millis() - start < 10000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      lbsResponse += c;
    }
    // Check if +CLBS: result line arrived
    if (lbsResponse.indexOf("+CLBS:") != -1 && lbsResponse.indexOf("\n", lbsResponse.indexOf("+CLBS:")) != -1) {
      break;
    }
    if (lbsResponse.indexOf("ERROR") != -1 && lbsResponse.indexOf("+CLBS:") == -1) {
      break;
    }
    delay(50);
  }

  Serial.println("[LBS] Raw modem response: " + lbsResponse);

  // If AT+CLBS=1,1 was rejected or didn't return coordinates, try fallback AT+CLBS=1
  if (lbsResponse.indexOf("+CLBS: 0") == -1) {
    while (modemSerial.available()) modemSerial.read();
    Serial.println("[LBS] Trying AT+CLBS=1 fallback...");
    modemSerial.println("AT+CLBS=1");
    start = millis();
    lbsResponse = "";
    while (millis() - start < 8000) {
      while (modemSerial.available()) {
        char c = modemSerial.read();
        lbsResponse += c;
      }
      if (lbsResponse.indexOf("+CLBS:") != -1 && lbsResponse.indexOf("\n", lbsResponse.indexOf("+CLBS:")) != -1) {
        break;
      }
      delay(50);
    }
    Serial.println("[LBS] Fallback response: " + lbsResponse);
  }

  int idx = lbsResponse.indexOf("+CLBS: 0");
  if (idx != -1) {
    String line = lbsResponse.substring(idx);
    int endL = line.indexOf("\n");
    if (endL != -1) line = line.substring(0, endL);
    line.trim();

    String f1 = getField(line, ',', 1);
    String f2 = getField(line, ',', 2);
    double val1 = f1.toDouble();
    double val2 = f2.toDouble();

    double cLat = 0.0, cLon = 0.0;
    // Auto-detect which is lat and lon based on geographic bounds of Philippines (Lat 4-22, Lon 115-130)
    if (val1 >= 4.0 && val1 <= 22.0 && val2 >= 115.0 && val2 <= 130.0) {
      cLat = val1;
      cLon = val2;
    } else if (val2 >= 4.0 && val2 <= 22.0 && val1 >= 115.0 && val1 <= 130.0) {
      cLat = val2;
      cLon = val1;
    } else if (val1 != 0.0 && val2 != 0.0) {
      cLat = val1;
      cLon = val2;
    }

    if (cLat != 0.0 && cLon != 0.0) {
      lat = cLat;
      lon = cLon;
      if (!globalHasGPSFix && globalCurrentLat == 0.0 && globalCurrentLon == 0.0) {
        globalCurrentLat = cLat;
        globalCurrentLon = cLon;
      }
      Serial.printf("[LBS] SUCCESS! Cellular tower location acquired: Lat: %.6f, Lon: %.6f\n", lat, lon);
      return true;
    }
  } else {
    int errIdx = lbsResponse.indexOf("+CLBS:");
    if (errIdx != -1) {
      Serial.printf("[LBS] Cellular location service returned error: %s\n", lbsResponse.substring(errIdx).c_str());
    }
  }
  return false;
}

// Syncs real coordinates directly to Firestore devices/safewalk_device_001 document
bool syncDeviceCoordinatesToFirestore(double lat, double lon) {
  if (lat == 0.0 || lon == 0.0) return false;
  // If it's Manila (14.5995, 120.9842), do NOT sync Manila!
  if (abs(lat - 14.5995) < 0.005 && abs(lon - 120.9842) < 0.005) return false;

  Serial.printf("[DEVICE SYNC] Updating live coordinates in Firestore: Lat: %.7f, Lon: %.7f\n", lat, lon);
  String response;
  flushModemBuffer();

  String rfcTimestamp = getNetworkTimeRFC3339();
  String jsonBody = "{\"fields\":{";
  jsonBody += "\"location\":{\"stringValue\":\"" + String(lat, 7) + ", " + String(lon, 7) + "\"},";
  jsonBody += "\"coordinates\":{\"geoPointValue\":{\"latitude\":" + String(lat, 7) + ",\"longitude\":" + String(lon, 7) + "}},";
  jsonBody += "\"latitude\":{\"doubleValue\":" + String(lat, 7) + "},";
  jsonBody += "\"longitude\":{\"doubleValue\":" + String(lon, 7) + "},";
  jsonBody += "\"locationSource\":{\"stringValue\":\"device_gps\"},";
  jsonBody += "\"status\":{\"stringValue\":\"active\"},";
  jsonBody += "\"lastSeen\":{\"timestampValue\":\"" + rfcTimestamp + "\"},";
  jsonBody += "\"updatedAt\":{\"timestampValue\":\"" + rfcTimestamp + "\"}";
  jsonBody += "}}";

  String url = "https://firestore.googleapis.com/v1/projects/";
  url += FIREBASE_PROJECT_ID;
  url += "/databases/(default)/documents/devices/";
  url += DEVICE_ID;
  url += "?updateMask.fieldPaths=location&updateMask.fieldPaths=coordinates&updateMask.fieldPaths=latitude&updateMask.fieldPaths=longitude&updateMask.fieldPaths=locationSource&updateMask.fieldPaths=status&updateMask.fieldPaths=lastSeen&updateMask.fieldPaths=updatedAt&key=";
  url += FIREBASE_API_KEY;

  sendATCommand("AT+HTTPTERM", response, 2000);
  delay(300);
  sendATCommand("AT+CSSLCFG=\"authmode\",0,0", response, 2000);
  sendATCommand("AT+CSSLCFG=\"sslversion\",0,4", response, 2000);
  sendATCommand("AT+CSSLCFG=\"ignorelocaltime\",0,1", response, 2000);
  sendATCommand("AT+CSSLCFG=\"enableSNI\",0,1", response, 2000);

  if (!sendATCommand("AT+HTTPINIT", response, 4000)) return false;
  sendATCommand("AT+HTTPSSL=1", response, 2000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", response, 2000);
  sendATCommand("AT+HTTPPARA=\"SSLCFG\",0", response, 2000);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", response, 2000);
  sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", response, 2000);

  modemSerial.println("AT+HTTPDATA=" + String(jsonBody.length()) + ",10000");
  delay(200);
  modemSerial.print(jsonBody);
  delay(500);

  // Send PATCH (HTTP method 2 in A7670)
  modemSerial.println("AT+HTTPACTION=2");
  delay(1500);
  sendATCommand("AT+HTTPTERM", response, 2000);
  return true;
}

// Obtains the current GPS location with high reliability (continuous background fix, active wait, last-known, and LBS fallback)
bool getGPSLocation(double& lat, double& lon) {
  Serial.println("[GPS] Querying exact GPS coordinates...");

  // 1. If we already have a recent background fix (< 60 seconds old), use it immediately!
  if (globalHasGPSFix && (millis() - globalLastFixTime < 60000)) {
    lat = globalCurrentLat;
    lon = globalCurrentLon;
    Serial.printf("[GPS] Immediate exact fix acquired: Lat: %.6f, Lon: %.6f (age: %lu ms)\n",
                  lat, lon, millis() - globalLastFixTime);
    return true;
  }

  // 2. Active listening window: read serial data from GPS and modem for up to 10 seconds
  unsigned long start = millis();
  while (millis() - start < 10000) {
    processGPSStream();
    if (globalHasGPSFix && (millis() - globalLastFixTime < 5000)) {
      lat = globalCurrentLat;
      lon = globalCurrentLon;
      Serial.printf("[GPS] Live exact satellite lock established: Lat: %.6f, Lon: %.6f\n", lat, lon);
      return true;
    }

    if (queryA7670InternalGNSS(lat, lon) || queryA7670CGPSINFO(lat, lon)) {
      return true;
    }

    delay(200);
  }

  // 3. Try cellular tower LBS (Location Based Service) query via A7670 modem (works indoors!)
  if (queryA7670CellularLBS(lat, lon)) {
    return true;
  }

  // 4. If recent active lock failed but we have a valid historical fix, use last known exact position
  if (globalCurrentLat != 0.0 && globalCurrentLon != 0.0) {
    lat = globalCurrentLat;
    lon = globalCurrentLon;
    Serial.printf("[GPS] Using last known exact coordinates: Lat: %.6f, Lon: %.6f (age: %lu ms)\n",
                  lat, lon, millis() - globalLastFixTime);
    return true;
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
bool triggerFirebaseAlert(double lat, double lon, const String& triggerType) {
  // Refresh configuration dynamically before sending alert to use the latest linking details
  fetchDeviceConfig();

  Serial.println("[FIREBASE] Initiating HTTPS via modem AT+HTTPINIT...");
  String response;

  // Safety flush — clear any leftover UART bytes before starting HTTP commands
  flushModemBuffer();

  // Get timestamp from cellular network
  String rfcTimestamp = getNetworkTimeRFC3339();

  String alertMsg = (triggerType == "voice_help") ? 
                    ("EMERGENCY: Your child is in danger! Voice distress '" + lastVoiceKeyword + "' detected by microphone.") : 
                    "EMERGENCY: Your child is in danger! SOS tactile button pressed.";

  // Construct JSON body
  String jsonBody = "{\"fields\":{";
  jsonBody += "\"deviceId\":{\"stringValue\":\"" + String(DEVICE_ID) + "\"},";
  jsonBody += "\"uid\":{\"stringValue\":\"" + (dynamicStudentUid.length() > 0 ? dynamicStudentUid : String(DEVICE_ID)) + "\"},";
  jsonBody += "\"studentUid\":{\"stringValue\":\"" + (dynamicStudentUid.length() > 0 ? dynamicStudentUid : String(DEVICE_ID)) + "\"},";
  jsonBody += "\"fullName\":{\"stringValue\":\"" + String(DEVICE_NAME) + "\"},";
  if (devicePhoneNumber.length() > 0) {
    jsonBody += "\"phoneNumber\":{\"stringValue\":\"" + devicePhoneNumber + "\"},";
  }
  if (dynamicParentUid.length() > 0) {
    jsonBody += "\"parentUid\":{\"stringValue\":\"" + dynamicParentUid + "\"},";
  }
  if (dynamicParentPhone.length() > 0) {
    jsonBody += "\"parentPhoneNumber\":{\"stringValue\":\"" + dynamicParentPhone + "\"},";
  }
  if (dynamicGuardianPhonesCsv.length() > 0) {
    jsonBody += "\"guardianPhonesCsv\":{\"stringValue\":\"" + dynamicGuardianPhonesCsv + "\"},";
  }
  String initialStatus = "active";
  jsonBody += "\"type\":{\"stringValue\":\"" + triggerType + "\"},";
  jsonBody += "\"severity\":{\"stringValue\":\"high\"},";
  jsonBody += "\"status\":{\"stringValue\":\"" + initialStatus + "\"},";
  jsonBody += "\"message\":{\"stringValue\":\"" + alertMsg + "\"},";
  jsonBody += "\"location\":{\"stringValue\":\"" + String(lat, 7) + ", " + String(lon, 7) + "\"},";
  jsonBody += "\"coordinates\":{\"geoPointValue\":{";
  jsonBody += "\"latitude\":" + String(lat, 7) + ",";
  jsonBody += "\"longitude\":" + String(lon, 7);
  jsonBody += "}},";
  jsonBody += "\"timestamp\":{\"timestampValue\":\"" + rfcTimestamp + "\"},";
  jsonBody += "\"locationSource\":{\"stringValue\":\"device_gps\"},";
  jsonBody += "\"triggeredBy\":{\"stringValue\":\"iot_device\"},";
  jsonBody += "\"voiceKeyword\":{\"stringValue\":\"" + lastVoiceKeyword + "\"},";
  jsonBody += "\"smsSubmissionStatus\":{\"stringValue\":\"" + lastSmsSubmissionStatus + "\"},";
  jsonBody += "\"smsDeliveryNote\":{\"stringValue\":\"submitted_means_carrier_accepted_not_handset_delivery\"}";
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



// Configures modem SMS subsystem (Text mode, GSM charset, SMS parameters, URC notifications)
bool setupSMS() {
  Serial.println("[SMS] Initializing SMS subsystem on A7670 modem...");
  String response;

  sendATCommand("AT+CMEE=2", response, 2000);
  sendATCommand("AT+CMGF=1", response, 2000);
  sendATCommand("AT+CSCS=\"GSM\"", response, 2000);
  sendATCommand("AT+CSMP=17,167,0,0", response, 2000);

  // Prefer Circuit-Switched SMS. Packet-domain SMS (CGSMS=2) commonly returns
  // "+CMS ERROR: unknown error" on PH LTE SIMs even when HTTPS data works.
  sendATCommand("AT+CGSMS=1", response, 2000);
  Serial.printf("[SMS] CGSMS (1=CS preferred): %s\n", response.c_str());

  sendATCommand("AT+CSCA?", response, 2000);
  Serial.printf("[SMS] SMSC: %s\n", response.c_str());
  if (response.indexOf("+CSCA:") == -1 || response.indexOf("\"\"") != -1) {
    Serial.println("[SMS] WARNING: SMSC empty/unknown. Put this SIM in a phone, send any SMS, reinsert.");
  }

  sendATCommand("AT+CNMI=2,1,0,0,0", response, 2000);
  logSmsDiagnostics();
  Serial.println("[SMS] SMS subsystem configured (CS preferred).");
  return true;
}

void logSmsDiagnostics() {
  String response;
  Serial.println("[SMS] ----- diagnostics -----");
  sendATCommand("AT+CPIN?", response, 2000);
  Serial.printf("[SMS] CPIN: %s\n", response.c_str());
  sendATCommand("AT+CSQ", response, 2000);
  Serial.printf("[SMS] CSQ: %s\n", response.c_str());
  sendATCommand("AT+CREG?", response, 2000);
  Serial.printf("[SMS] CREG: %s\n", response.c_str());
  sendATCommand("AT+CEREG?", response, 2000);
  Serial.printf("[SMS] CEREG: %s\n", response.c_str());
  sendATCommand("AT+CGSMS?", response, 2000);
  Serial.printf("[SMS] CGSMS?: %s\n", response.c_str());
  sendATCommand("AT+CSCA?", response, 2000);
  Serial.printf("[SMS] CSCA?: %s\n", response.c_str());
  sendATCommand("AT+CPSI?", response, 3000);
  Serial.printf("[SMS] CPSI: %s\n", response.c_str());
  sendATCommand("ATI", response, 2000);
  Serial.printf("[SMS] ATI: %s\n", response.c_str());
  Serial.println("[SMS] ----- end diagnostics -----");
}

void abortPendingSmsPrompt() {
  // ESC cancels an open CMGS '>' prompt so the modem is not left half-open
  modemSerial.write(27);
  delay(300);
  flushModemBuffer();
}

// Cleanses, validates, and converts any raw phone number into standard international format (+639XXXXXXXXX)
String formatPhoneNumberForSMS(const String& inputRaw) {
  String clean = "";
  for (int i = 0; i < inputRaw.length(); i++) {
    char c = inputRaw.charAt(i);
    if (isDigit(c) || (c == '+' && clean.length() == 0)) {
      clean += c;
    }
  }
  if (clean.startsWith("+63") && clean.length() == 13) {
    return clean;
  }
  if (clean.startsWith("63") && clean.length() == 12) {
    return "+" + clean;
  }
  if (clean.startsWith("09") && clean.length() == 11) {
    return "+63" + clean.substring(1);
  }
  if (clean.startsWith("9") && clean.length() == 10) {
    return "+63" + clean;
  }
  return clean;
}

// Convert +639XXXXXXXXX (or already-local) to 09XXXXXXXXX for carrier variants that prefer local MSISDN
String formatPhoneNumberLocalPH(const String& intlOrLocal) {
  String intl = formatPhoneNumberForSMS(intlOrLocal);
  if (intl.startsWith("+63") && intl.length() == 13) {
    return "0" + intl.substring(3);
  }
  return intlOrLocal;
}

// Low-level AT+CMGS. smsServiceDomain: 1=CS preferred, 0=CS only, 2=PS preferred, 3=PS only
bool sendSMSViaModem(const String& recipient, const String& message, int smsServiceDomain) {
  String response;
  flushModemBuffer();
  abortPendingSmsPrompt();

  String safeMsg = message;
  if (safeMsg.length() > 150) {
    Serial.printf("[SMS] Warning: Message length (%d) trimmed to 150 chars.\n", safeMsg.length());
    safeMsg = safeMsg.substring(0, 150);
  }

  sendATCommand("AT+CMEE=2", response, 1000);
  sendATCommand("AT+CEREG?", response, 1500);
  bool isRegistered = (response.indexOf(",1") != -1 || response.indexOf(",5") != -1);
  if (!isRegistered) {
    sendATCommand("AT+CREG?", response, 1500);
    isRegistered = (response.indexOf(",1") != -1 || response.indexOf(",5") != -1);
  }
  if (!isRegistered) {
    Serial.println("[SMS] Warning: not registered on CS/EPS. SMS may fail.");
  }

  if (!sendATCommand("AT+CMGF=1", response, 2000)) {
    Serial.printf("[SMS] AT+CMGF=1 failed: %s\n", response.c_str());
    Serial.println("[SMS] If CMGF always errors, this A7670 variant may not support SMS.");
    return false;
  }

  sendATCommand("AT+CSCS=\"GSM\"", response, 1000);
  sendATCommand("AT+CSMP=17,167,0,0", response, 1000);

  String cgsmsCmd = "AT+CGSMS=" + String(smsServiceDomain);
  sendATCommand(cgsmsCmd, response, 2000);
  Serial.printf("[SMS] Using %s -> %s\n", cgsmsCmd.c_str(), response.c_str());

  while (modemSerial.available()) modemSerial.read();

  String sendSmsCmd = "AT+CMGS=\"" + recipient + "\"";
  Serial.printf("[SMS] Issuing command: %s\n", sendSmsCmd.c_str());
  modemSerial.println(sendSmsCmd);

  unsigned long start = millis();
  bool gotPrompt = false;
  String promptResponse = "";
  while (millis() - start < 8000) {
    if (modemSerial.available()) {
      char c = modemSerial.read();
      promptResponse += c;
      if (c == '>') {
        gotPrompt = true;
        break;
      }
      if (promptResponse.indexOf("ERROR") != -1) {
        Serial.printf("[SMS] Modem rejected CMGS: %s\n", promptResponse.c_str());
        abortPendingSmsPrompt();
        return false;
      }
    }
    delay(10);
  }

  if (!gotPrompt) {
    Serial.printf("[SMS] No '>' prompt. Modem: %s\n", promptResponse.c_str());
    abortPendingSmsPrompt();
    return false;
  }

  delay(200);
  modemSerial.print(safeMsg);
  delay(200);
  modemSerial.write(26); // Ctrl+Z

  response = "";
  start = millis();
  unsigned long sawCmgsAt = 0;
  while (millis() - start < 45000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      response += c;
    }
    if (response.indexOf("+CMS ERROR") != -1) {
      Serial.printf("[SMS] Rejected by network/modem: %s\n", response.c_str());
      abortPendingSmsPrompt();
      return false;
    }
    if (response.indexOf("+CMGS:") != -1) {
      if (sawCmgsAt == 0) sawCmgsAt = millis();
      if (response.indexOf("OK") != -1) {
        Serial.printf("[SMS] Carrier accepted SMS: %s\n", response.c_str());
        return true;
      }
      // Some A7670 builds emit +CMGS:<mr> then delay OK; accept if no ERROR for 4s
      if (response.indexOf("ERROR") == -1 && (millis() - sawCmgsAt > 4000)) {
        Serial.printf("[SMS] Accepting +CMGS without delayed OK: %s\n", response.c_str());
        return true;
      }
    } else if (response.indexOf("ERROR") != -1) {
      Serial.printf("[SMS] Rejected by network/modem: %s\n", response.c_str());
      abortPendingSmsPrompt();
      return false;
    }
    delay(50);
  }

  Serial.printf("[SMS] Timed out waiting for CMGS. Raw: %s\n", response.c_str());
  abortPendingSmsPrompt();
  return false;
}

bool sendSMSViaModemWithFallbacks(const String& recipientIntl, const String& message) {
  // Strategy order addresses common A7670 "+CMS ERROR: unknown error" on LTE:
  // 1) CS preferred + international MSISDN
  // 2) CS only + international
  // 3) CS preferred + local 09… format
  // 4) PS preferred + international (last resort)
  struct Attempt {
    const char* label;
    int domain;
    bool useLocal;
  };
  const Attempt attempts[] = {
    {"CS preferred / +63", 1, false},
    {"CS only / +63", 0, false},
    {"CS preferred / 09", 1, true},
    {"PS preferred / +63", 2, false},
  };

  for (size_t i = 0; i < sizeof(attempts) / sizeof(attempts[0]); i++) {
    String dest = attempts[i].useLocal ? formatPhoneNumberLocalPH(recipientIntl) : recipientIntl;
    Serial.printf("\n[SMS] Attempt %d/%d: %s -> %s\n",
                  (int)(i + 1), (int)(sizeof(attempts) / sizeof(attempts[0])),
                  attempts[i].label, dest.c_str());
    if (sendSMSViaModem(dest, message, attempts[i].domain)) {
      return true;
    }
    delay(1500);
    flushModemBuffer();
  }
  return false;
}

// Main high-level emergency SMS function: formats concise message with coordinates link and sends to all linked/added guardians
bool sendSMSAlert(double lat, double lon, const String& triggerType) {
  Serial.println("\n[SMS] =========================================");
  Serial.println("[SMS] Preparing emergency SMS alert to guardian(s)...");
  Serial.println("[SMS] =========================================");

  logSmsDiagnostics();

  // Build deduplicated list of guardian phone numbers (supports up to 12 dynamic guardian numbers)
  String recipients[12];
  int recipientCount = 0;

  auto addUniqueRecipient = [&](const String& rawNum) {
    if (recipientCount >= 12) return;
    String formatted = formatPhoneNumberForSMS(rawNum);
    formatted.trim();
    if (formatted.length() < 7) return;
    for (int i = 0; i < recipientCount; i++) {
      if (recipients[i] == formatted) return;
    }
    recipients[recipientCount++] = formatted;
  };

  if (dynamicParentPhone.length() > 0) {
    addUniqueRecipient(dynamicParentPhone);
  }

  if (dynamicGuardianPhonesCsv.length() > 0) {
    int startIdx = 0;
    int len = dynamicGuardianPhonesCsv.length();
    while (startIdx < len) {
      int commaIdx = dynamicGuardianPhonesCsv.indexOf(',', startIdx);
      int semiIdx = dynamicGuardianPhonesCsv.indexOf(';', startIdx);
      int splitIdx = -1;
      if (commaIdx != -1 && semiIdx != -1) {
        splitIdx = (commaIdx < semiIdx) ? commaIdx : semiIdx;
      } else if (commaIdx != -1) {
        splitIdx = commaIdx;
      } else if (semiIdx != -1) {
        splitIdx = semiIdx;
      }

      if (splitIdx == -1) {
        addUniqueRecipient(dynamicGuardianPhonesCsv.substring(startIdx));
        break;
      } else {
        addUniqueRecipient(dynamicGuardianPhonesCsv.substring(startIdx, splitIdx));
        startIdx = splitIdx + 1;
      }
    }
  }

  if (recipientCount == 0) {
    Serial.println("[SMS] WARNING: No parent or guardian numbers found in Firebase. SMS not sent.");
    Serial.println("[SMS] Add devices/{id}.parentPhoneNumber and guardianPhonesCsv (or guardianPhones / additionalGuardians).");
    return false;
  }

  String triggerDesc = "SOS";
  if (triggerType == "voice_help") {
    triggerDesc = (lastVoiceKeyword.length() > 0 ? lastVoiceKeyword : "HELP");
  } else if (triggerType.endsWith("_update")) {
    triggerDesc = "GPS";
  }

  // Keep first attempt short/plain GSM-7 (long URLs often trip CMS ERROR on some SIMs)
  String shortMsg = "EMERGENCY ALERT: A request for help has been detected. Please check immediately.";
  shortMsg += " [";
  shortMsg += triggerDesc;
  shortMsg += "]";
  if (lat != 0.0 && lon != 0.0) {
    shortMsg += " Loc:";
    shortMsg += String(lat, 5);
    shortMsg += ",";
    shortMsg += String(lon, 5);
  }

  Serial.printf("[SMS] Total Guardian Recipients: %d\n", recipientCount);
  Serial.println("[SMS] Message (" + String(shortMsg.length()) + " chars):\n" + shortMsg);

  bool anySuccess = false;
  for (int r = 0; r < recipientCount; r++) {
    Serial.printf("\n[SMS] Dispatching to Guardian %d/%d: %s\n", r + 1, recipientCount, recipients[r].c_str());
    if (sendSMSViaModemWithFallbacks(recipients[r], shortMsg)) {
      anySuccess = true;
      Serial.printf("[SMS] [SUCCESS] Guardian %d (%s) SMS submitted to carrier.\n", r + 1, recipients[r].c_str());
    } else {
      Serial.printf("[SMS] [WARNING] Failed to submit SMS to Guardian %d (%s).\n", r + 1, recipients[r].c_str());
    }
    if (r + 1 < recipientCount) {
      delay(1500);
      flushModemBuffer();
    }
  }

  if (anySuccess) {
    lastSmsSubmissionStatus = "submitted";
    Serial.println("[SMS] [SUCCESS] Emergency SMS submitted to carrier (+CMGS). Not a handset delivery receipt.");
  } else {
    lastSmsSubmissionStatus = "failed";
    Serial.println("[SMS] [FAILED] All SMS strategies failed.");
    Serial.println("[SMS] Checklist:");
    Serial.println("  1) SIM can send SMS from a phone (same SIM)");
    Serial.println("  2) Prepaid has SMS load / SMS not blocked");
    Serial.println("  3) SMSC present in AT+CSCA? (send SMS once from a phone to populate)");
    Serial.println("  4) Antenna connected; AT+CSQ rssi ideally >= 12");
    Serial.println("  5) Module is not A7670E-LNXY-UBL (no SMS hardware support)");
  }

  return anySuccess;
}

// Monitors modem serial UART stream for unsolicited result codes (URCs), such as incoming SMS (+CMTI)
void checkIncomingModemData() {
  static String modemLineBuffer = "";
  while (modemSerial.available()) {
    char c = modemSerial.read();
    Serial.write(c); // Echo to debug console
    if (c == '\n') {
      modemLineBuffer.trim();
      if (modemLineBuffer.startsWith("+CMTI:")) {
        // e.g. +CMTI: "SM",1
        int commaIdx = modemLineBuffer.indexOf(",");
        if (commaIdx != -1) {
          int smsIndex = modemLineBuffer.substring(commaIdx + 1).toInt();
          if (smsIndex > 0) {
            handleIncomingSMS(smsIndex);
          }
        }
      }
      modemLineBuffer = "";
    } else if (c != '\r') {
      if (modemLineBuffer.length() < 128) {
        modemLineBuffer += c;
      }
    }
  }
}

// Reads incoming SMS, processes parent location queries (LOC/HELP/STATUS), and replies with coordinates
void handleIncomingSMS(int smsIndex) {
  Serial.printf("\n[SMS] Handling incoming SMS notification at SIM memory index %d...\n", smsIndex);
  String response;
  
  // Ensure text mode is active
  sendATCommand("AT+CMGF=1", response, 1000);
  
  // Read message at SIM index
  String readCmd = "AT+CMGR=" + String(smsIndex);
  if (!sendATCommand(readCmd, response, 3000)) {
    Serial.printf("[SMS] Failed to read SMS index %d.\n", smsIndex);
    return;
  }

  // Parse sender phone number from +CMGR header:
  // e.g. +CMGR: "REC UNREAD","+639568165326",,"26/10/19,21:55:00+32"
  int firstQuote = response.indexOf("\",\"");
  String senderPhone = "";
  if (firstQuote != -1) {
    int secondQuote = response.indexOf("\"", firstQuote + 3);
    if (secondQuote != -1) {
      senderPhone = response.substring(firstQuote + 3, secondQuote);
    }
  }

  String upperResponse = response;
  upperResponse.toUpperCase();

  Serial.printf("[SMS] Incoming SMS from: %s\n", senderPhone.c_str());

  // Check if sender requested child location or status
  if (upperResponse.indexOf("LOC") != -1 || 
      upperResponse.indexOf("LOCATION") != -1 || 
      upperResponse.indexOf("WHERE") != -1 || 
      upperResponse.indexOf("STATUS") != -1 || 
      upperResponse.indexOf("HELP") != -1 || 
      upperResponse.indexOf("COORDINATES") != -1) {

    Serial.println("[SMS] Location query keyword recognized! Acquiring GPS coordinates...");
    double lat = 0.0;
    double lon = 0.0;
    getGPSLocation(lat, lon);

    String childName = (dynamicStudentName.length() > 0) ? dynamicStudentName : "Child";
    String reply = "[SAFEWALK STATUS]\n";
    reply += childName + " Location:\n";
    if (lat != 0.0 && lon != 0.0) {
      reply += "https://maps.google.com/?q=" + String(lat, 6) + "," + String(lon, 6) + "\n";
      reply += "Lat:" + String(lat, 6) + " Lon:" + String(lon, 6);
    } else {
      reply += "GPS: Acquiring fix (indoors)";
    }

    String destination = senderPhone.length() > 0 ? senderPhone : dynamicParentPhone;
    destination = formatPhoneNumberForSMS(destination);
    if (destination.length() < 7) {
      Serial.println("[SMS] WARNING: No Firestore parent number to reply to. Status SMS skipped.");
    } else {
      Serial.printf("[SMS] Replying to %s with coordinates (%d chars)...\n", destination.c_str(), reply.length());
      sendSMSViaModemWithFallbacks(destination, reply);
    }
  }

  // Delete message from SIM card storage to prevent memory overflow (SIM holds ~25-30 messages)
  String deleteCmd = "AT+CMGD=" + String(smsIndex);
  sendATCommand(deleteCmd, response, 2000);
  Serial.printf("[SMS] Cleared SIM storage slot %d.\n", smsIndex);
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

// Parses a numeric double field from a Firestore JSON response
double parseJsonDoubleField(const String& json, const String& fieldName) {
  int fieldIndex = json.indexOf("\"" + fieldName + "\"");
  if (fieldIndex == -1) return 0.0;

  // Search for doubleValue or integerValue
  int valIdx = json.indexOf("Value\":", fieldIndex);
  if (valIdx != -1 && valIdx - fieldIndex < 50) {
    int start = valIdx + 7;
    while (start < json.length() && (json.charAt(start) == ' ' || json.charAt(start) == '\"')) {
      start++;
    }
    int end = start;
    while (end < json.length() && (isDigit(json.charAt(end)) || json.charAt(end) == '.' || json.charAt(end) == '-')) {
      end++;
    }
    if (end > start) {
      return json.substring(start, end).toDouble();
    }
  }

  // Also check plain "fieldName": 12.34
  int colon = json.indexOf(":", fieldIndex);
  if (colon != -1 && colon - fieldIndex < 30) {
    int start = colon + 1;
    while (start < json.length() && (json.charAt(start) == ' ' || json.charAt(start) == '\"')) {
      start++;
    }
    int end = start;
    while (end < json.length() && (isDigit(json.charAt(end)) || json.charAt(end) == '.' || json.charAt(end) == '-')) {
      end++;
    }
    if (end > start) {
      return json.substring(start, end).toDouble();
    }
  }
  return 0.0;
}

// Returns the stringValue, or every stringValue inside an arrayValue, for one Firestore field.
// Accepts a CSV string or a list such as guardianPhones / additionalGuardians.
String parseFirestorePhoneList(const String& json, const String& fieldName) {
  String key = "\"" + fieldName + "\"";
  int keyIndex = -1;
  int searchFrom = 0;
  while (searchFrom < json.length()) {
    int found = json.indexOf(key, searchFrom);
    if (found == -1) break;
    int after = found + key.length();
    while (after < json.length() && (json.charAt(after) == ' ' || json.charAt(after) == '\r' || json.charAt(after) == '\n' || json.charAt(after) == '\t')) {
      after++;
    }
    if (after < json.length() && json.charAt(after) == ':') {
      keyIndex = found;
      break;
    }
    searchFrom = found + key.length();
  }
  if (keyIndex == -1) return "";
  int openBrace = json.indexOf("{", keyIndex);
  if (openBrace == -1) return "";

  int depth = 0;
  bool inString = false;
  int endBrace = -1;
  for (int i = openBrace; i < json.length(); i++) {
    char c = json.charAt(i);
    if (c == '\\' && inString) {
      i++;
      continue;
    }
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c == '{') depth++;
    else if (c == '}') {
      depth--;
      if (depth == 0) {
        endBrace = i;
        break;
      }
    }
  }
  if (endBrace == -1) return "";
  String region = json.substring(openBrace, endBrace + 1);

  String csv = "";
  int search = 0;
  while (search < region.length()) {
    int marker = region.indexOf("\"stringValue\"", search);
    if (marker == -1) break;
    int colon = region.indexOf(":", marker);
    if (colon == -1) break;
    int openQuote = region.indexOf("\"", colon);
    if (openQuote == -1) break;
    int closeQuote = region.indexOf("\"", openQuote + 1);
    if (closeQuote == -1) break;
    String value = region.substring(openQuote + 1, closeQuote);
    value.trim();
    if (value.length() > 0) {
      if (csv.length() > 0) csv += ",";
      csv += value;
    }
    search = closeQuote + 1;
  }
  return csv;
}

String resolveGuardianPhonesCsv(const String& httpData) {
  const char* fields[] = {
    "guardianPhonesCsv",
    "guardianPhones",
    "additionalGuardians"
  };
  String merged = "";
  for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++) {
    String part = parseFirestorePhoneList(httpData, fields[i]);
    part.trim();
    if (part.length() == 0) continue;
    if (merged.length() > 0) merged += ",";
    merged += part;
  }
  return merged;
}

// Automatically creates/registers devices/safewalk_device_001 if it doesn't exist in Firestore (404 fix)
bool autoRegisterDeviceInFirestore() {
  Serial.println("[CONFIG] Auto-registering safewalk_device_001 in Firestore...");
  String response;
  flushModemBuffer();

  String rfcTimestamp = getNetworkTimeRFC3339();
  String jsonBody = "{\"fields\":{";
  jsonBody += "\"deviceId\":{\"stringValue\":\"" + String(DEVICE_ID) + "\"},";
  jsonBody += "\"deviceName\":{\"stringValue\":\"" + String(DEVICE_NAME) + "\"},";
  jsonBody += "\"status\":{\"stringValue\":\"online\"},";
  jsonBody += "\"updatedAt\":{\"timestampValue\":\"" + rfcTimestamp + "\"}";
  jsonBody += "}}";

  String url = "https://firestore.googleapis.com/v1/projects/";
  url += FIREBASE_PROJECT_ID;
  url += "/databases/(default)/documents/devices/";
  url += DEVICE_ID;
  url += "?key=";
  url += FIREBASE_API_KEY;

  sendATCommand("AT+HTTPTERM", response, 2000);
  sendATCommand("AT+CSSLCFG=\"authmode\",0,0", response, 2000);
  sendATCommand("AT+CSSLCFG=\"sslversion\",0,4", response, 2000);
  sendATCommand("AT+CSSLCFG=\"ignorelocaltime\",0,1", response, 2000);
  sendATCommand("AT+CSSLCFG=\"enableSNI\",0,1", response, 2000);

  if (!sendATCommand("AT+HTTPINIT", response, 3000)) return false;
  sendATCommand("AT+HTTPSSL=1", response, 2000);
  sendATCommand("AT+HTTPPARA=\"CID\",1", response, 2000);
  sendATCommand("AT+HTTPPARA=\"SSLCFG\",0", response, 2000);
  sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", response, 2000);
  sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", response, 2000);

  modemSerial.println("AT+HTTPDATA=" + String(jsonBody.length()) + ",10000");
  delay(200);
  modemSerial.print(jsonBody);
  delay(500);

  // Send PATCH (method 2)
  modemSerial.println("AT+HTTPACTION=2");
  delay(2000);
  sendATCommand("AT+HTTPTERM", response, 2000);
  Serial.println("[CONFIG] Auto-registration uploaded to Firestore.");
  return true;
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

  // Parentheses in "(default)" make the A7670 reject AT+HTTPPARA. Percent-encoding is valid for this API.
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += FIREBASE_PROJECT_ID;
  url += "/databases/%28default%29/documents/devices/";
  url += DEVICE_ID;
  url += "?key=";
  url += FIREBASE_API_KEY;

  for (int attempt = 1; attempt <= 2; attempt++) {
    flushModemBuffer();
    sendATCommand("AT+HTTPTERM", response, 3000);
    delay(300);

    sendATCommand("AT+CSSLCFG=\"authmode\",0,0", response, 3000);
    sendATCommand("AT+CSSLCFG=\"sslversion\",0,4", response, 3000);
    sendATCommand("AT+CSSLCFG=\"ignorelocaltime\",0,1", response, 3000);
    sendATCommand("AT+CSSLCFG=\"enableSNI\",0,1", response, 3000);

    if (!sendATCommand("AT+HTTPINIT", response, 5000)) {
      Serial.println("[CONFIG] AT+HTTPINIT failed: " + response);
      continue;
    }

    sendATCommand("AT+HTTPSSL=1", response, 3000);
    sendATCommand("AT+HTTPPARA=\"CID\",1", response, 3000);
    sendATCommand("AT+HTTPPARA=\"SSLCFG\",0", response, 3000);

    if (!sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", response, 5000)) {
      Serial.println("[CONFIG] Modem rejected Firestore URL: " + response);
      sendATCommand("AT+HTTPTERM", response, 2000);
      continue;
    }

    modemSerial.println("AT+HTTPACTION=0");

    unsigned long start = millis();
    String atResp = "";
    bool gotAction = false;
    int responseCode = -1;
    int dataSize = 0;

    while (millis() - start < 45000) {
      while (modemSerial.available()) {
        char c = modemSerial.read();
        atResp += c;
      }
      int actionIdx = atResp.indexOf("+HTTPACTION:");
      if (actionIdx != -1) {
        int comma1 = atResp.indexOf(",", actionIdx);
        int comma2 = comma1 == -1 ? -1 : atResp.indexOf(",", comma1 + 1);
        if (comma1 != -1 && comma2 != -1) {
          responseCode = atResp.substring(comma1 + 1, comma2).toInt();
          int endNum = comma2 + 1;
          while (endNum < atResp.length() && isDigit(atResp.charAt(endNum))) endNum++;
          dataSize = atResp.substring(comma2 + 1, endNum).toInt();
          gotAction = true;
          break;
        }
      }
      bool commandError = atResp.indexOf("+CME ERROR") != -1 || atResp.indexOf("\r\nERROR") != -1 || atResp.indexOf("\nERROR") != -1;
      if (commandError && (millis() - start) > 1500) {
        break;
      }
      delay(50);
    }

    if (!gotAction || responseCode != 200 || dataSize <= 0) {
      String preview = atResp;
      preview.replace("\r", " ");
      preview.replace("\n", " ");
      if (preview.length() > 180) preview = preview.substring(0, 180);
      Serial.printf("[CONFIG] HTTP GET failed (attempt %d). Code: %d, Size: %d. Modem: %s\n",
                    attempt, responseCode, dataSize, preview.c_str());
      sendATCommand("AT+HTTPTERM", response, 3000);
      if (responseCode == 404) {
        autoRegisterDeviceInFirestore();
        return false;
      }
      continue;
    }

    modemSerial.println("AT+HTTPREAD=0," + String(dataSize));

    start = millis();
    String httpData = "";
    while (millis() - start < 12000) {
      while (modemSerial.available()) {
        char c = modemSerial.read();
        httpData += c;
      }
      int readIdx = httpData.indexOf("+HTTPREAD:");
      if (readIdx != -1) {
        int payloadStart = httpData.indexOf('\n', readIdx);
        if (payloadStart != -1 && (httpData.length() - (payloadStart + 1)) >= dataSize) {
          break;
        }
      }
      if (httpData.indexOf("+CME ERROR") != -1 || httpData.indexOf("\r\nERROR") != -1) break;
      delay(20);
    }

    int payloadIdx = httpData.indexOf("+HTTPREAD:");
    if (payloadIdx != -1) {
      int payloadStart = httpData.indexOf('\n', payloadIdx);
      if (payloadStart != -1 && (httpData.length() - (payloadStart + 1)) < dataSize) {
        Serial.printf("[CONFIG] Firestore body was cut off (%d of %d bytes). Retrying.\n",
                      httpData.length() - (payloadStart + 1), dataSize);
        sendATCommand("AT+HTTPTERM", response, 3000);
        continue;
      }
    }

    sendATCommand("AT+HTTPTERM", response, 3000);

    String parsedParentUid = parseJsonStringField(httpData, "parentUid");
    String parsedParentPhone = parseFirestorePhoneList(httpData, "parentPhoneNumber");
    if (parsedParentPhone.length() == 0) {
      parsedParentPhone = parseFirestorePhoneList(httpData, "parentPhone");
    }
    String parsedGuardianCsv = resolveGuardianPhonesCsv(httpData);
    String parsedStudentUid = parseJsonStringField(httpData, "studentUid");
    String parsedStudentName = parseJsonStringField(httpData, "studentName");

    if (parsedParentUid.length() > 0) {
      dynamicParentUid = parsedParentUid;
    }
    // A short body can contain parentUid and omit the phone fields. Do not wipe numbers we already have.
    bool sawParentPhone = httpData.indexOf("\"parentPhoneNumber\"") != -1 || httpData.indexOf("\"parentPhone\"") != -1;
    bool sawGuardians = httpData.indexOf("\"guardianPhonesCsv\"") != -1 || httpData.indexOf("\"guardianPhones\"") != -1 || httpData.indexOf("\"additionalGuardians\"") != -1;
    if (parsedParentPhone.length() > 0 || sawParentPhone) {
      dynamicParentPhone = parsedParentPhone;
    }
    if (parsedGuardianCsv.length() > 0 || sawGuardians) {
      dynamicGuardianPhonesCsv = parsedGuardianCsv;
    }
    if (parsedStudentUid.length() > 0) {
      dynamicStudentUid = parsedStudentUid;
    }
    if (parsedStudentName.length() > 0) {
      dynamicStudentName = parsedStudentName;
    }

    String parsedPhone = parseJsonStringField(httpData, "phoneNumber");
    if (parsedPhone.length() > 0) {
      devicePhoneNumber = parsedPhone;
    }

    double storedLat = parseJsonDoubleField(httpData, "latitude");
    double storedLon = parseJsonDoubleField(httpData, "longitude");
    if ((storedLat == 0.0 || storedLon == 0.0) && httpData.indexOf("\"geoPointValue\"") != -1) {
      int geoIdx = httpData.indexOf("\"geoPointValue\"");
      int latIdx = httpData.indexOf("\"latitude\"", geoIdx);
      int lonIdx = httpData.indexOf("\"longitude\"", geoIdx);
      if (latIdx != -1 && lonIdx != -1) {
        int latCol = httpData.indexOf(":", latIdx);
        int lonCol = httpData.indexOf(":", lonIdx);
        if (latCol != -1 && lonCol != -1) {
          storedLat = httpData.substring(latCol + 1, httpData.indexOf(",", latCol)).toDouble();
          storedLon = httpData.substring(lonCol + 1, httpData.indexOf("}", lonCol)).toDouble();
        }
      }
    }
    if (!globalHasGPSFix && globalCurrentLat == 0.0 && globalCurrentLon == 0.0 &&
        storedLat != 0.0 && storedLon != 0.0) {
      if (!((abs(storedLat - 14.5995) < 0.005) && (abs(storedLon - 120.9842) < 0.005))) {
        globalCurrentLat = storedLat;
        globalCurrentLon = storedLon;
        Serial.printf("[CONFIG] Stored fallback location loaded from Firestore: Lat: %.6f, Lon: %.6f\n",
                      storedLat, storedLon);
      }
    }

    Serial.printf("[CONFIG] Loaded: Parent Phone: %s, Guardian Phones CSV: %s, Parent UID: %s, Student UID: %s\n",
      dynamicParentPhone.c_str(), dynamicGuardianPhonesCsv.c_str(), dynamicParentUid.c_str(), dynamicStudentUid.c_str());
    if (dynamicParentPhone.length() == 0 && dynamicGuardianPhonesCsv.length() == 0) {
      Serial.println("[CONFIG] WARNING: Firestore document has no parentPhoneNumber or guardian phones.");
    }
    return true;
  }

  Serial.println("[CONFIG] Firestore config unavailable. SOS will have no SMS recipients until the document can be read.");
  return false;
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

// DC-blocking high-pass filter state
static float dc_x1 = 0.0f;
static float dc_y1 = 0.0f;

// Locked once at boot. Per-sample "louder slot" hops onto I2S garbage and
// makes Edge Impulse classify silence as HELP.
static int i2sActiveChannel = 0; // 0 = left, 1 = right
static bool i2sPausedForAlert = false;

// INMP441 puts audio on one slot. The other slot stays near zero.
// L/R to GND fills the left slot; L/R to 3V3 fills the right slot.
static inline int32_t selectedMicRaw(int32_t left, int32_t right) {
  return (i2sActiveChannel == 0) ? left : right;
}

// Process 32-bit raw sample from active I2S channel:
// - Shifts 24-bit MSB-aligned data with gain
// - Clamps to int16 range to prevent overflow / wrap-around distortion
// - Removes DC offset with a high-pass filter (~30 Hz cutoff at 16kHz)
static inline int16_t processMicSample(int32_t raw32) {
  int32_t s32 = raw32 >> 14; // level that produced real HELP/TABANG scores on this mic
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

  i2sActiveChannel = (rightEnergy > leftEnergy) ? 1 : 0;
  if (rightEnergy > leftEnergy * 2) {
    Serial.printf("[I2S] Locked RIGHT slot (L-Energy: %llu, R-Energy: %llu). L/R pin looks tied high.\n", leftEnergy, rightEnergy);
  } else if (leftEnergy > rightEnergy * 2) {
    Serial.printf("[I2S] Locked LEFT slot (L-Energy: %llu, R-Energy: %llu). L/R pin looks tied to GND.\n", leftEnergy, rightEnergy);
  } else {
    Serial.printf("[I2S] Slots similar; locked %s (L-Energy: %llu, R-Energy: %llu).\n",
                  i2sActiveChannel ? "RIGHT" : "LEFT", leftEnergy, rightEnergy);
  }

  if (leftEnergy < 8000 && rightEnergy < 8000) {
    Serial.println("[I2S] WARNING: Microphone looks silent.");
    Serial.println("[I2S] Soldered wiring is VDD->3V3, GND->GND, SCK->IO33, WS->IO25, SD->IO32, L/R->GND.");
    Serial.println("[I2S] Check those six joints. A peak that stays 0 means one of them is open.");
  } else {
    Serial.println("[I2S] Microphone is producing audio.");
  }

  // Reset filter state & clear DMA buffer
  dc_x1 = 0.0f;
  dc_y1 = 0.0f;
  i2s_zero_dma_buffer(I2S_PORT);
  Serial.println("[I2S] INMP441 Microphone ready (calibrated & DC-filtered).");
  return true;
}

// Edge Impulse continuous classifier state.
// IMPORTANT: do NOT allocate EI_CLASSIFIER_RAW_SAMPLE_COUNT (32000) here — that is 64KB
// and can starve the ESP32 when TinyGSM/HTTP are also loaded. Use slice buffers only.
static int16_t ei_slice_buffer[EI_CLASSIFIER_SLICE_SIZE];
static size_t ei_slice_fill = 0;
static bool ei_classifier_ready = false;
static uint8_t ei_consecutive_i2s_fails = 0;
static uint8_t ei_warmup_slices = 0;
static uint8_t ei_keyword_hits = 0;
static int32_t ei_slice_peak = 0;
static int32_t ei_slice_avg = 0;
static float voiceAmbientAvg = 400.0f;

static bool labelMentions(const char* label, const char* needle) {
  if (label == nullptr || needle == nullptr) return false;
  size_t nLen = strlen(needle);
  if (nLen == 0) return false;
  for (const char* p = label; *p; ++p) {
    size_t i = 0;
    while (i < nLen) {
      char a = p[i];
      char b = needle[i];
      if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
      if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
      if (a != b) break;
      i++;
    }
    if (i == nLen) return true;
  }
  return false;
}

// Callback used by run_classifier_continuous() — one slice of raw audio.
static int microphone_audio_signal_get_data(size_t offset, size_t length, float *out_ptr) {
  numpy::int16_to_float(&ei_slice_buffer[offset], out_ptr, length);
  return 0;
}

static void pauseMicrophoneForAlert() {
  if (!i2sPausedForAlert) {
    i2s_stop(I2S_PORT);
    i2sPausedForAlert = true;
  }
  ei_classifier_ready = false;
  ei_slice_fill = 0;
  ei_keyword_hits = 0;
}

// Clear DMA / classifier state so listening never stays stuck after SOS or a failed classify.
void recoverMicrophoneListening() {
  dc_x1 = 0.0f;
  dc_y1 = 0.0f;
  ei_slice_fill = 0;
  ei_consecutive_i2s_fails = 0;
  ei_warmup_slices = 0;
  ei_keyword_hits = 0;
  ei_slice_peak = 0;
  ei_slice_avg = 0;
  voiceSliceWasQuiet = true;

  if (i2sPausedForAlert) {
    i2s_start(I2S_PORT);
    i2sPausedForAlert = false;
  }

  i2s_zero_dma_buffer(I2S_PORT);

  // Drain stale DMA so Edge Impulse does not classify leftover SOS-period garbage.
  for (int i = 0; i < 24; i++) {
    int32_t dump[128];
    size_t dumped = 0;
    i2s_read(I2S_PORT, dump, sizeof(dump), &dumped, pdMS_TO_TICKS(10));
  }

  run_classifier_init();
  ei_classifier_ready = true;
}

// Official Edge Impulse continuous path:
// fill EI_CLASSIFIER_SLICE_SIZE samples -> run_classifier_continuous() -> check Help/Tabang.
bool checkVoiceHelpTrigger() {
  serviceSosButtons();
  if (sosPressPending) return false;

  if (!ei_classifier_ready) {
    recoverMicrophoneListening();
  }

  if (ei_consecutive_i2s_fails >= 12) {
    recoverMicrophoneListening();
  }

  // Drain I2S into the current 0.5s slice. Cap time so GPS/modem still get CPU,
  // but read enough each pass that the DMA buffers do not overrun.
  {
    unsigned long fillStart = millis();
    while (ei_slice_fill < EI_CLASSIFIER_SLICE_SIZE && (millis() - fillStart) < 45) {
      serviceSosButtons();
      if (sosPressPending) return false;

      int32_t quickBuffer[256]; // 128 stereo frames
      size_t bytesRead = 0;
      esp_err_t err = i2s_read(I2S_PORT, quickBuffer, sizeof(quickBuffer), &bytesRead, pdMS_TO_TICKS(15));
      if (err != ESP_OK || bytesRead == 0) {
        ei_consecutive_i2s_fails++;
        break;
      }

      ei_consecutive_i2s_fails = 0;
      size_t framesRead = (bytesRead / sizeof(int32_t)) / 2;
      for (size_t f = 0; f < framesRead && ei_slice_fill < EI_CLASSIFIER_SLICE_SIZE; f++) {
        int32_t raw = selectedMicRaw(quickBuffer[f * 2], quickBuffer[f * 2 + 1]);
        ei_slice_buffer[ei_slice_fill++] = processMicSample(raw);
      }
    }
  }

  if (ei_slice_fill < EI_CLASSIFIER_SLICE_SIZE) {
    return false;
  }

  int64_t absSum = 0;
  int32_t peak = 0;
  for (size_t i = 0; i < EI_CLASSIFIER_SLICE_SIZE; i++) {
    int32_t v = ei_slice_buffer[i];
    if (v < 0) v = -v;
    if (v > peak) peak = v;
    absSum += v;
  }
  ei_slice_peak = peak;
  ei_slice_avg = (int32_t)(absSum / (int64_t)EI_CLASSIFIER_SLICE_SIZE);

  // Slice complete — classify continuously (model keeps a rolling 2s feature window).
  signal_t signal;
  signal.total_length = EI_CLASSIFIER_SLICE_SIZE;
  signal.get_data = &microphone_audio_signal_get_data;

  ei_impulse_result_t result = { 0 };
  EI_IMPULSE_ERROR r = run_classifier_continuous(&signal, &result, false);
  ei_slice_fill = 0; // start collecting the next slice immediately

  if (r != EI_IMPULSE_OK) {
    Serial.printf("[VOICE] run_classifier_continuous failed (%d). Recovering.\n", r);
    recoverMicrophoneListening();
    return false;
  }

  // First full window needs ~4 slices (~2s). Extra slices after SOS flush stale DMA.
  const uint8_t warmupNeeded = (uint8_t)(EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW + 2);
  if (ei_warmup_slices < warmupNeeded) {
    ei_warmup_slices++;
    voiceSliceWasQuiet = true;
    ei_keyword_hits = 0;
    return false;
  }

  if (millis() - systemBootReadyTime < BOOT_GRACE_PERIOD_MS) {
    voiceSliceWasQuiet = true;
    return false;
  }

  float helpScore = 0.0f;
  float tabangScore = 0.0f;
  float noiseScore = 0.0f;

  for (size_t ix = 0; ix < EI_CLASSIFIER_LABEL_COUNT; ix++) {
    const char* label = result.classification[ix].label;
    float score = result.classification[ix].value;

    if (labelMentions(label, "tabang")) {
      tabangScore = score;
    } else if (labelMentions(label, "help")) {
      helpScore = score;
    } else if (labelMentions(label, "noise") || labelMentions(label, "unknown") ||
               labelMentions(label, "silence")) {
      noiseScore = score;
    }
  }

  const int32_t energyFloor = (int32_t)(voiceAmbientAvg * 2.4f);
  const bool energyOk =
      (ei_slice_peak >= VOICE_SLICE_PEAK_MIN) &&
      (ei_slice_avg >= VOICE_SLICE_AVG_MIN) &&
      (ei_slice_avg >= energyFloor);

  if (!energyOk) {
    voiceAmbientAvg = (voiceAmbientAvg * 0.90f) + ((float)ei_slice_avg * 0.10f);
    voiceSliceWasQuiet = true;
    ei_keyword_hits = 0;

    static unsigned long lastQuietLog = 0;
    if (millis() - lastQuietLog > 4000) {
      lastQuietLog = millis();
      Serial.printf("[VOICE] Silence (peak=%d avg=%d floor=%.0f help=%.2f Tabang=%.2f Noise=%.2f)\n",
                    ei_slice_peak, ei_slice_avg, voiceAmbientAvg,
                    helpScore, tabangScore, noiseScore);
    }
    return false;
  }

  const bool tabangOk =
      (tabangScore >= TABANG_SCORE_MIN) &&
      (tabangScore > (noiseScore + KEYWORD_OVER_NOISE));
  const bool helpOk =
      (helpScore >= HELP_SCORE_MIN) &&
      (helpScore > (noiseScore + KEYWORD_OVER_NOISE));

  if (!tabangOk && !helpOk) {
    voiceSliceWasQuiet = (noiseScore >= helpScore) && (noiseScore >= tabangScore);
    ei_keyword_hits = 0;
    static unsigned long lastIgnoredLog = 0;
    if (millis() - lastIgnoredLog > 2000) {
      lastIgnoredLog = millis();
      Serial.printf("[VOICE] Sound ignored (peak=%d avg=%d help=%.2f Tabang=%.2f Noise=%.2f)\n",
                    ei_slice_peak, ei_slice_avg, helpScore, tabangScore, noiseScore);
    }
    return false;
  }

  if (tabangOk && (!helpOk || tabangScore >= helpScore)) {
    lastVoiceKeyword = "TABANG";
  } else {
    lastVoiceKeyword = "HELP";
  }

  voiceSliceWasQuiet = false;
  ei_keyword_hits++;
  Serial.printf("[VOICE] Candidate %s %u/%u (help=%.2f Tabang=%.2f Noise=%.2f peak=%d avg=%d)\n",
                lastVoiceKeyword.c_str(), ei_keyword_hits, VOICE_HITS_REQUIRED,
                helpScore, tabangScore, noiseScore, ei_slice_peak, ei_slice_avg);

  if (ei_keyword_hits < VOICE_HITS_REQUIRED) {
    return false;
  }

  ei_keyword_hits = 0;
  Serial.printf("[VOICE] Locked %s (help=%.2f Tabang=%.2f Noise=%.2f)\n",
                lastVoiceKeyword.c_str(), helpScore, tabangScore, noiseScore);
  return true;
}


// Main Emergency Dispatcher Routine (Button Press or Voice 'HELP'/'TABANG')
void triggerEmergencyAlertProcess(const String& triggerSource) {
  Serial.printf("\n[ALERT] Triggered by: %s\n", triggerSource.c_str());

  pauseMicrophoneForAlert();
  lastSmsSubmissionStatus = "none";

  double lat = 0.0;
  double lon = 0.0;
  bool hasGPS = getGPSLocation(lat, lon);

  if (!hasGPS) {
    if (globalCurrentLat != 0.0 && globalCurrentLon != 0.0) {
      lat = globalCurrentLat;
      lon = globalCurrentLon;
    } else if (!queryA7670CellularLBS(lat, lon)) {
      delay(1000);
      queryA7670InternalGNSS(lat, lon);
    }
  }

  fetchDeviceConfig();
  if (lat == 0.0 && lon == 0.0 &&
      globalCurrentLat != 0.0 && globalCurrentLon != 0.0) {
    lat = globalCurrentLat;
    lon = globalCurrentLon;
  }

  Serial.printf("[ALERT] Coordinates: %.6f, %.6f\n", lat, lon);
  if (lat != 0.0 && lon != 0.0) {
    syncDeviceCoordinatesToFirestore(lat, lon);
  }

  if (lat == 0.0 || lon == 0.0) {
    pendingEmergencySMSCoordinateUpdate = true;
    pendingUpdateTriggerType = triggerSource;
  } else {
    pendingEmergencySMSCoordinateUpdate = false;
  }

  bool smsSent = sendSMSAlert(lat, lon, triggerSource);
  Serial.println(smsSent ? "[ALERT] SMS submitted." : "[ALERT] SMS failed.");

  delay(1500);
  flushModemBuffer();

  bool firebaseSent = triggerFirebaseAlert(lat, lon, triggerSource);
  Serial.println(firebaseSent ? "[ALERT] Firebase uploaded." : "[ALERT] Firebase failed.");

  // Cooldown starts now, not when the keyword was first seen. SMS+HTTP can take
  // longer than VOICE_COOLDOWN_MS and was immediately re-triggering HELP.
  lastVoiceTriggerTime = millis();
  voiceDetectorArmed = false;
  voiceKeywordCurrentlyActive = false;
  voiceSliceWasQuiet = true;
  recoverMicrophoneListening();
  Serial.println("[VOICE] Mic restarted. Cooldown + quiet audio required before the next SOS.");
}
