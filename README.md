# SafeWalk

SafeWalk is a Flutter + Firebase safety platform with web and mobile support.

## Capstone Requirements Coverage

- Online system: Firebase Authentication + Cloud Firestore backend.
- Web-based application: Flutter Web target is included.
- Mobile application: Flutter Android/iOS targets are included.
- Email and SMS notification system:
  - Email: EmailJS integration (`lib/config/emailjs_config.dart`).
  - SMS: configurable gateway integration (`lib/config/sms_config.dart`) with logs in `sms_logs`.
- Backup mechanism:
  - Admin dashboard can create backup snapshots into `system_backups/{backupId}`.
- Generate and print report:
  - Admin dashboard can generate system reports (`system_reports`) and open printable report output.

## Configuration

1. Configure EmailJS values in `lib/config/emailjs_config.dart`.
2. Configure SMS gateway values in `lib/config/sms_config.dart`:
   - `endpoint`
   - `apiKey`
   - `senderId`
3. Ensure Firebase is configured for your platforms (`lib/firebase/firebase_options.dart`).

## Google Maps (Mobile) Setup Guide for Beginners

If Google Map is blank on Android/iOS, follow these steps carefully.

1. Open Google Cloud Console: https://console.cloud.google.com
2. Create/select a project.
3. Enable billing for the project (Google Maps needs billing, even on free tier usage).
4. Go to `APIs & Services > Library` and enable:
   - `Maps SDK for Android`
   - `Maps SDK for iOS` (if you will run on iPhone)
5. Go to `APIs & Services > Credentials` and create API key(s).
6. Restrict your Android key:
   - Application restriction: `Android apps`
   - Package name: `com.example.safewalk`
   - SHA-1 fingerprint: use your debug/release SHA-1
   - Windows command to get debug SHA-1:

```bash
keytool -list -v -alias androiddebugkey -keystore "%USERPROFILE%\.android\debug.keystore" -storepass android -keypass android
```

### Android project changes in this repo

This project now reads the Android Maps key from `android/local.properties`.

1. Open `android/local.properties`
2. Add this line:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

3. Save, then run:

```bash
flutter clean
flutter pub get
flutter run
```

### iOS key location

For iOS, the key is currently set in `ios/Runner/AppDelegate.swift`:

```swift
GMSServices.provideAPIKey("YOUR_IOS_MAPS_API_KEY")
```

Replace it with your iOS Maps key if needed.

### Common reasons map is still blank

1. Billing is not enabled in Google Cloud.
2. Wrong package name or wrong SHA-1 in key restrictions.
3. Using Android emulator image without Google Play services.
4. API key copied with extra spaces/quotes.

## Run

```bash
flutter pub get
flutter run -d chrome   # Web
flutter run             # Mobile/Desktop default target
```
