# SafeWalk System Architecture

_Last updated: March 28, 2026_

## 1) Architecture Scope

This document describes the current `as-built` architecture of the SafeWalk project based on the Flutter code in this repository.

Primary goals covered by the system:
- Role-based access for `admin`, `student`, and `parent`
- Student safety monitoring and SOS workflow
- Parent-student linking and invitation flow
- Admin reporting and backup snapshots
- Email/SMS integration hooks and delivery logging

## 2) Context Diagram

```mermaid
graph LR
    Student[Student User]
    Parent[Parent User]
    Admin[Admin User]

    Student --> App[SafeWalk Flutter App]
    Parent --> App
    Admin --> App

    App --> Auth[Firebase Authentication]
    App --> Firestore[Cloud Firestore]
    App --> Maps[Google Maps SDK + Web JS API]
    App --> EmailJS[EmailJS HTTP API]
    App --> SMS[SMS Gateway HTTP API]

    Firestore --> AdminReports[System Reports + Backups]
```

## 3) Container / Component Architecture

```mermaid
graph TD
    subgraph Client[Flutter Client (Web + Mobile)]
      UI[UI Layer\nlanding/login/register\nadmin dashboard\nstudent dashboard\nparent dashboard]
      AuthSvc[AuthService]
      NotifSvc[NotificationService]
      AdminSvc[SystemAdminService]
      PrintSvc[PrintService\n(web implementation + stub)]
      MapsGuard[GoogleMaps Web Guard]
    end

    UI --> AuthSvc
    UI --> NotifSvc
    UI --> AdminSvc
    UI --> PrintSvc
    UI --> MapsGuard

    AuthSvc --> FirebaseAuth[Firebase Auth]
    AuthSvc --> Firestore[(Cloud Firestore)]
    AuthSvc --> EmailJS

    NotifSvc --> Firestore
    NotifSvc --> EmailJS
    NotifSvc --> SMS

    AdminSvc --> Firestore
    PrintSvc --> BrowserPrint[Browser Print Window]
    MapsGuard --> GoogleMapsJS[Google Maps JS availability check]
```

### Main module responsibilities

- `main.dart`: initializes Firebase and routes to `LandingPage` on web, otherwise `LoginPage`
- `auth/auth_service.dart`: login, registration, OTP email sending, password reset, login audit logs
- `User/user_dashboard.dart`: student profile/settings, parent invitation handling, SOS creation, map and alert history
- `User/parent_dashboard.dart`: linked student monitoring, invitation sending, alert acknowledgment, child map and status
- `admin/admin_dashboard.dart`: user/device/alert/log views, report generation, print, backup, test notifications
- `services/notification_service.dart`: outbound email/SMS calls and logging to Firestore
- `services/system_admin_service.dart`: report aggregation and Firestore snapshot backup

## 4) Key Runtime Flows

### 4.1 Registration with Email OTP

```mermaid
sequenceDiagram
    participant User
    participant RegisterUI as Register Page
    participant AuthSvc as AuthService
    participant EmailJS
    participant FA as Firebase Auth
    participant FS as Firestore

    User->>RegisterUI: Enter details + request OTP
    RegisterUI->>AuthSvc: sendEmailOtp(email, fullName)
    AuthSvc->>EmailJS: POST /email/send (OTP)
    AuthSvc-->>RegisterUI: OTP sent

    User->>RegisterUI: Submit OTP + password
    RegisterUI->>AuthSvc: registerWithEmailOtp(...)
    AuthSvc->>FA: createUserWithEmailAndPassword
    AuthSvc->>FS: set users/{uid}
    AuthSvc-->>RegisterUI: Account created
```

### 4.2 Login and role routing

```mermaid
sequenceDiagram
    participant User
    participant LoginUI as Login Page
    participant AuthSvc as AuthService
    participant FA as Firebase Auth
    participant FS as Firestore

    User->>LoginUI: Email/Phone + Password
    LoginUI->>AuthSvc: signIn(loginInput, password)
    AuthSvc->>FA: signInWithEmailAndPassword
    AuthSvc->>FS: get users/{uid} for role
    AuthSvc->>FS: add login_logs
    AuthSvc-->>LoginUI: LoginResult(success, role)
    LoginUI-->>User: Navigate to role dashboard
```

### 4.3 SOS and parent response

```mermaid
sequenceDiagram
    participant StudentUI as Student Dashboard
    participant FS as Firestore
    participant ParentUI as Parent Dashboard

    StudentUI->>FS: add emergency_alerts (status=active, parentUid, location)
    ParentUI->>FS: stream emergency_alerts by child + parent
    ParentUI->>FS: set status=acknowledged, ackBy, ackAt
```

### 4.4 Admin report and backup

```mermaid
sequenceDiagram
    participant AdminUI as Admin Dashboard
    participant AdminSvc as SystemAdminService
    participant FS as Firestore

    AdminUI->>AdminSvc: generateSystemReport()
    AdminSvc->>FS: read core collections
    AdminSvc->>FS: add system_reports/{id}
    AdminUI-->>AdminUI: show/print report

    AdminUI->>AdminSvc: createBackupSnapshot()
    AdminSvc->>FS: create system_backups/{backupId}
    AdminSvc->>FS: copy docs into system_backups/{backupId}/documents
```

## 5) Firestore Data Model (Current)

| Collection | Purpose | Key fields (observed) |
|---|---|---|
| `users` | User profile + role | `uid`, `fullName`, `email`, `phoneNumber`, `role`, `createdAt` |
| `user_settings` | Per-user preferences | `alertsEnabled`, `safeModeEnabled`, `locationSharingEnabled`, `smsAlertsEnabled`, `emailAlertsEnabled`, `childUid`, `updatedAt` |
| `devices` | Device registry / location source | `deviceId`, `deviceName`, `phoneNumber`, `location`, `status`, `createdAt`, optional coordinates |
| `parent_student_invitations` | Invitation workflow | `parentUid`, `studentUid`, normalized phones, `status`, `createdAt`, `updatedAt`, `respondedAt` |
| `parent_student_links` | Accepted parent-student links | parent/student IDs and names, normalized phones, `status`, `linkedAt`, `updatedAt` |
| `emergency_alerts` | SOS and alert timeline | student/user IDs, parent IDs, `type`, `severity`, `status`, `message`, `location`, `coordinates`, `timestamp`, `ackBy`, `ackAt` |
| `login_logs` | Authentication audit trail | `uid`, `loginInput`, `email`, `status`, `role`, `location`, `deviceId`, `reason`, `timestamp` |
| `sms_logs` | SMS delivery audit | `phoneNumber`, `message`, `status`, provider response fields, `timestamp` |
| `email_logs` | Email delivery audit | `toEmail`, `subject`, `status`, provider response fields, `timestamp` |
| `system_reports` | Generated admin reports | `generatedAt`, `counts`, `failedLoginSamples`, `recentAlerts`, `createdAt` |
| `system_backups` | Backup metadata | `status`, `collections`, `totalDocuments`, timestamps |
| `system_backups/{id}/documents` | Backup payload docs | `collection`, `sourceId`, `data`, `createdAt` |
| `walk_sessions` | Child route/session status | `uid`, `route`, `distanceKm`, `status` |

## 6) Deployment View

- Frontend runtime: Flutter (Web/Android/iOS/Desktop targets in repo)
- Backend runtime: Firebase Authentication + Cloud Firestore
- External providers:
- Email: EmailJS (`https://api.emailjs.com/api/v1.0/email/send`)
- SMS: configurable HTTP gateway (`lib/config/sms_config.dart`)
- Maps: `google_maps_flutter` with web JS readiness guard

## 7) Current Architectural Notes

- This is a client-heavy architecture (business logic in Flutter pages/services).
- Firestore is the system of record for operational data and logs.
- Real-time monitoring is implemented via Firestore snapshot streams.
- Notification sending exists, but automatic alert-to-SMS/email fan-out is not yet wired from SOS events.
- OTP state is in-memory inside `AuthService`; it resets when app process/session restarts.

## 8) Recommended Next Architecture Step

Introduce a backend automation layer (Firebase Cloud Functions) for:
- server-side OTP issuance/verification
- automatic SMS/email fan-out on new active `emergency_alerts`
- centralized role/permission enforcement and immutable audit trails

This keeps the current UI architecture while making security and reliability stronger.
