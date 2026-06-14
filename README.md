# 📚 CEMS — College Education Management System

> A cross-platform Flutter application for managing college attendance and timetables with QR-code-based, geolocation-verified check-ins.

---

## 📖 Project Overview

**CEMS (College Education Management System)** is a role-based mobile and web application built with Flutter and Firebase. It streamlines the day-to-day workflow of attendance tracking and timetable management in a college environment.

### Problem It Solves

Traditional attendance systems rely on manual roll calls, paper sheets, or static spreadsheets — all of which are slow, error-prone, and easy to game. CEMS replaces this with:

- **Auto-rotating QR codes** that teachers display during class.
- **GPS geofencing** that verifies students are physically present in the classroom.
- **Real-time dashboards** for students, teachers, and administrators — each tailored to their role.

### Key Objectives

| Objective | How CEMS Achieves It |
|---|---|
| Eliminate proxy attendance | QR tokens rotate every 25 seconds and are validated against the student's GPS location. |
| Give students visibility | Students see per-subject lecture/lab percentages and get warned when they drop below 75%. |
| Empower teachers | Teachers can start live sessions, set a geofence radius, and view per-student attendance breakdowns. |
| Centralize admin control | Admins manage subjects, teacher accounts, and division timetables from a single console. |

---

## ✨ Features

### Authentication & Roles
- Email/password sign-in via Firebase Authentication.
- Automatic role-based routing: **Student**, **Teacher**, or **Admin** dashboard after login.
- Persistent auth state — users stay signed in across app restarts.

### Student Features
- **Attendance Dashboard** — Overall percentage, per-subject lecture/lab breakdown with progress bars, and low-attendance warnings (< 75%).
- **Weekly Timetable** — Division-specific schedule grouped by day with next-class indicator.
- **QR Scanner** — Camera-based QR scanner with animated overlay, processing indicator, and contextual error messages.
- **Profile & Theme Toggle** — View profile details and switch between light/dark mode.

### Teacher Features
- **Teaching Overview** — Aggregated lecture/lab session counts per subject and division.
- **Start Session** — Generate a live QR code with a configurable geofence radius (10–100 m). The QR token auto-rotates every 25 seconds with a visual countdown ring.
- **Attendance Sheet** — View per-student lecture and lab attendance percentages in a bottom sheet, color-coded by threshold (≥ 75% green, ≥ 60% amber, < 60% red).
- **Weekly Timetable** — View all assigned schedule slots grouped by day.
- **Profile & Theme Toggle** — Same as student.

### Admin Features
- **Subjects Management** — Create subjects and assign them to teachers. Change teacher mapping or delete subjects.
- **Timetable Builder** — Add/edit/delete schedule slots with subject, division, day, time, and type (lecture/lab).
- **Teacher Account Provisioning** — Create Firebase Auth accounts and Firestore profiles for teachers directly from the app, or map existing UIDs.
- **Teacher Directory** — View and remove teacher profiles.

### Design & UX
- Material 3 (Material You) design system with custom purple-branded color scheme.
- Light and dark themes with runtime toggle (no restart required).
- Shimmer loading placeholders while data is being fetched.
- Slide-up page transitions for scanner and session screens.
- Animated QR scan overlay with corner brackets and processing states.

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| **Language** | Dart 3.11+ |
| **Framework** | Flutter 3.41+ (stable channel) |
| **UI System** | Material 3 / Material You |
| **Authentication** | Firebase Authentication (email/password) |
| **Database** | Cloud Firestore (NoSQL, real-time) |
| **QR Generation** | `qr_flutter` ^4.1.0 |
| **QR Scanning** | `mobile_scanner` ^5.0.0 |
| **Geolocation** | `geolocator` ^10.1.0 |
| **Hosting** | Firebase Hosting (web build) |
| **Linting** | `flutter_lints` ^6.0.0 |
| **IDE** | VS Code / Android Studio |

---

## 📁 Project Structure

```
CEMS_MiniProject/
├── .github/                        # GitHub workflows & hooks
├── .vscode/                        # VS Code workspace settings
└── cems_application/               # Flutter application root
    ├── lib/
    │   ├── main.dart               # App entry point, Firebase init, auth-based routing
    │   ├── firebase_options.dart    # FlutterFire CLI-generated platform configs
    │   ├── screens/
    │   │   ├── login_screen.dart    # Email/password login UI
    │   │   ├── admin/
    │   │   │   ├── admin.dart             # Barrel export
    │   │   │   └── admin_dashboard.dart   # Subjects, timetable, teacher management
    │   │   ├── student/
    │   │   │   ├── student_dashboard.dart       # Attendance, timetable, profile tabs
    │   │   │   └── scan_attendance_screen.dart  # QR scanner with geolocation validation
    │   │   └── teacher/
    │   │       ├── teacher_dashboard.dart       # Dashboard, timetable, profile tabs
    │   │       └── start_session_screen.dart    # Live QR session with geofencing
    │   ├── services/
    │   │   ├── auth_services.dart   # Firebase Auth sign-in/sign-out + Firestore user fetch
    │   │   └── theme_service.dart   # Global theme mode (light/dark) via ValueNotifier
    │   ├── theme/
    │   │   └── app_theme.dart       # Material 3 light/dark ThemeData definitions
    │   └── widgets/
    │       ├── loading_shimmer.dart # Animated shimmer placeholder + SlideUpRoute transition
    │       ├── schedule_card.dart   # Reusable timetable slot card (lecture/lab styling)
    │       └── ui_blocks.dart       # AppSectionHeader, EmptyStateCard, QuickStatCard
    ├── test/
    │   └── widget_test.dart        # Default Flutter widget test (scaffold)
    ├── android/                    # Android platform files
    ├── ios/                        # iOS platform files
    ├── web/                        # Web platform files
    ├── windows/                    # Windows platform files
    ├── linux/                      # Linux platform files
    ├── macos/                      # macOS platform files
    ├── pubspec.yaml                # Dependencies and project metadata
    ├── pubspec.lock                # Locked dependency versions
    ├── firebase.json               # Firebase Hosting & FlutterFire config
    ├── .firebaserc                 # Firebase project alias
    ├── analysis_options.yaml       # Dart analyzer & lint rules
    └── .gitignore                  # Ignored files (build, secrets, IDE files)
```

### Key Files

| File | Purpose |
|---|---|
| `main.dart` | Initializes Firebase, listens to `authStateChanges()`, and routes to the correct dashboard based on the user's Firestore `role` field. |
| `auth_services.dart` | Wraps `FirebaseAuth` sign-in and enriches the result with the user's Firestore document. |
| `app_theme.dart` | Defines the full Material 3 `ThemeData` for both light and dark modes, including brand colors, card shapes, input decorations, and navigation bar styling. |
| `start_session_screen.dart` | Core of the attendance system — generates a cryptographically random QR token, writes it to Firestore with a 25-second expiry, and refreshes automatically. Streams GPS updates and stores teacher coordinates for geofence validation. |
| `scan_attendance_screen.dart` | Students scan the QR code; the app validates the token, checks GPS proximity, prevents duplicates, and writes an attendance record. |

---

## 🏗 Architecture / Workflow

### High-Level Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Student    │     │   Teacher    │     │    Admin     │
│  Dashboard   │     │  Dashboard   │     │   Console    │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └────────────┬───────┘────────────────────┘
                    │
            ┌───────▼────────┐
            │  Firebase Auth │  ← Authentication layer
            └───────┬────────┘
                    │
            ┌───────▼────────┐
            │ Cloud Firestore│  ← Data layer (users, subjects,
            │                │    schedule, sessions, attendance)
            └────────────────┘
```

### Attendance Session Flow

```
Teacher                          Firestore                         Student
  │                                 │                                 │
  ├─── Start Session ──────────────►│                                 │
  │    (GPS coords, token, expiry)  │                                 │
  │                                 │                                 │
  │    ◄── Token rotates every ────►│                                 │
  │        25 seconds               │                                 │
  │                                 │                                 │
  │                                 │◄────── Scan QR token ───────────┤
  │                                 │                                 │
  │                                 │── Validate: ────────────────────┤
  │                                 │   1. Token matches active       │
  │                                 │      session?                   │
  │                                 │   2. Token not expired?         │
  │                                 │   3. Same division?             │
  │                                 │   4. Within geofence radius?    │
  │                                 │   5. Not a duplicate?           │
  │                                 │                                 │
  │                                 │── Write attendance record ─────►│
  │                                 │                                 │
  ├─── End Session ────────────────►│                                 │
  │    (isActive = false)           │                                 │
```

### Data Flow Summary

1. **Admin** creates subjects (mapped to teachers) and schedule slots (mapped to divisions/days/times).
2. **Teacher** starts a live session → Firestore `sessions` document is created with a QR token, GPS coordinates, and 25-second expiry.
3. **Student** scans the QR code → the app validates the token, checks geolocation proximity, and writes to the `attendance` collection.
4. All dashboards read from Firestore in real-time (via `StreamBuilder` or pull-to-refresh).

---

## ⚙️ Installation Guide

### Prerequisites

| Requirement | Version |
|---|---|
| Flutter SDK | ≥ 3.41.x (stable) |
| Dart SDK | ≥ 3.11.1 |
| Firebase CLI | Latest |
| FlutterFire CLI | Latest |
| Git | Any recent version |
| Chrome | For web development |
| Android Studio | For Android builds (optional) |
| Xcode | For iOS builds (macOS only, optional) |

### Step-by-Step Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/<your-username>/CEMS_MiniProject.git
   cd CEMS_MiniProject/cems_application
   ```

2. **Install Flutter dependencies**

   ```bash
   flutter pub get
   ```

3. **Configure Firebase**

   The project is pre-configured with a Firebase project (`cems-application`). To use your own Firebase project:

   ```bash
   # Install Firebase CLI & FlutterFire CLI if not already installed
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli

   # Log in and configure
   firebase login
   flutterfire configure
   ```

   This regenerates `lib/firebase_options.dart` and platform-specific config files.

4. **Set up Firestore**

   In the [Firebase Console](https://console.firebase.google.com):
   - Enable **Cloud Firestore** in the project.
   - Enable **Email/Password** authentication under Authentication → Sign-in method.
   - Create an initial admin user via Firebase Auth console and add a corresponding document in the `users` collection with `role: "admin"`.

5. **Verify setup**

   ```bash
   flutter doctor
   ```

---

## 🚀 Usage Instructions

### Run Locally

```bash
# Web (recommended for development)
cd cems_application
flutter run -d chrome

# Android (requires Android SDK)
flutter run -d android

# Windows
flutter run -d windows

# iOS (macOS + Xcode required)
flutter run -d ios
```

### Development Workflow

```bash
# Hot reload is automatic in debug mode (press 'r' in terminal)
# Hot restart (press 'R')

# Analyze code for lint issues
flutter analyze

# Run tests
flutter test
```

### Build for Production

```bash
# Web
flutter build web

# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release
```

### Deploying Web Build to Firebase Hosting

```bash
flutter build web
firebase deploy --only hosting
```

---

## 🔧 Configuration

### Firebase Configuration

| File | Purpose |
|---|---|
| `lib/firebase_options.dart` | Auto-generated platform-specific Firebase config (API keys, app IDs, project ID). **Listed in `.gitignore`** — regenerate with `flutterfire configure`. |
| `firebase.json` | Firebase Hosting config — serves `build/web` with SPA rewrites. |
| `.firebaserc` | Maps the default project alias to `cems-application`. |

### Environment Variables

No `.env` file is used in the current codebase. Firebase configuration is handled via `firebase_options.dart`. The `.gitignore` includes an `.env` entry for future use.

### Required Credentials

| Credential | Where to Set |
|---|---|
| Firebase API Keys | Auto-generated in `firebase_options.dart` via FlutterFire CLI |
| Admin User | Create manually in Firebase Auth + Firestore `users` collection |

> **⚠️ Security Note:** `firebase_options.dart` is listed in `.gitignore` and should not be committed with sensitive API keys. Regenerate it per environment using `flutterfire configure`.

---

## 🗄 Database Information

### Firestore Collections Schema

#### `users`
| Field | Type | Description |
|---|---|---|
| `name` | string | User's display name |
| `email` | string | User's email address |
| `role` | string | One of: `student`, `teacher`, `admin` |
| `division` | string | Student's division (e.g., `A`, `B`) — students only |

#### `subjects`
| Field | Type | Description |
|---|---|---|
| `name` | string | Subject name (e.g., "Data Structures") |
| `teacherId` | string | UID of the assigned teacher |

#### `schedule`
| Field | Type | Description |
|---|---|---|
| `subjectId` | string | Reference to a `subjects` document |
| `division` | string | Division this slot applies to |
| `day` | string | Day of the week (e.g., "Monday") |
| `time` | string | Time slot (e.g., "10:00 AM – 11:00 AM") |
| `type` | string | `lecture` or `lab` |

#### `sessions`
| Field | Type | Description |
|---|---|---|
| `subjectId` | string | Reference to a `subjects` document |
| `teacherId` | string | UID of the teacher who started the session |
| `division` | string | Target division |
| `date` | string | ISO date string (YYYY-MM-DD) |
| `type` | string | `lecture` or `lab` |
| `qrToken` | string | Current active QR token (rotates every 25s) |
| `tokenExpiry` | Timestamp | When the current token expires |
| `isActive` | boolean | Whether the session is live |
| `latitude` | number | Teacher's GPS latitude |
| `longitude` | number | Teacher's GPS longitude |
| `radiusMetres` | number | Allowed check-in radius in metres |

#### `attendance`
| Field | Type | Description |
|---|---|---|
| `sessionId` | string | Reference to a `sessions` document |
| `studentId` | string | UID of the student |
| `subjectId` | string | Reference to a `subjects` document |
| `sessionType` | string | `lecture` or `lab` |
| `status` | boolean | `true` if present |
| `markedAt` | Timestamp | When attendance was recorded |
| `studentLatitude` | number | Student's GPS latitude at check-in |
| `studentLongitude` | number | Student's GPS longitude at check-in |
| `distanceMeters` | number | Distance from teacher at check-in |

> **Document ID convention:** Attendance documents use the composite key `{sessionId}_{studentId}` to prevent duplicate entries.

### Migrations

Not applicable — Cloud Firestore is schemaless. Collections are created automatically when documents are first written.

### Seed Data

There is no automated seed script. To bootstrap the system:

1. Create an admin user in Firebase Auth.
2. Add a document to the `users` collection with `role: "admin"`.
3. Log in as admin and use the Admin Console to create teachers, subjects, and timetable slots.
4. Create student accounts in Firebase Auth and add corresponding `users` documents with `role: "student"` and a `division` field.

---

## 🖼 Screenshots / Visuals

### Login

| Login Screen |
|:---:|
| ![Login Screen](App%20Screenshots/Screenshot%202026-04-28%20013645.png) |
| *Branded login card with email/password fields and sign-in button* |

### Student Portal

| Attendance Dashboard | Weekly Timetable | Profile |
|:---:|:---:|:---:|
| ![Student Attendance](App%20Screenshots/Screenshot%202026-04-28%20013902.png) | ![Student Timetable](App%20Screenshots/Screenshot%202026-04-28%20013915.png) | ![Student Profile](App%20Screenshots/Screenshot%202026-04-28%20013923.png) |
| *Per-subject lecture/lab percentages with low-attendance warnings* | *Next class indicator and weekly schedule grouped by day* | *Profile details, division info, theme toggle, and logout* |

### Teacher Portal

| Teaching Dashboard | Attendance Sheet | Weekly Timetable | Profile | Live QR Session |
|:---:|:---:|:---:|:---:|:---:|
| ![Teacher Dashboard](App%20Screenshots/Screenshot%202026-04-28%20013732.png) | ![Teacher Attendance Sheet](App%20Screenshots/Screenshot%202026-04-28%20013742.png) | ![Teacher Timetable](App%20Screenshots/Screenshot%202026-04-28%20013755.png) | ![Teacher Profile](App%20Screenshots/Screenshot%202026-04-28%20013804.png) | ![Live QR Session](App%20Screenshots/Screenshot%202026-04-29%20171302.png) |
| *Subject cards with session counts and start buttons* | *Per-student lecture and lab attendance breakdown* | *Schedule slots grouped by day with lecture/lab details* | *Teacher profile with theme toggle* | *Auto-rotating QR code with countdown ring and geofence indicator* |

### Admin Console

| Subjects Management | Timetable Builder | Teacher Management |
|:---:|:---:|:---:|
| ![Admin Subjects](App%20Screenshots/Screenshot%202026-04-28%20013950.png) | ![Admin Timetable](App%20Screenshots/Screenshot%202026-04-28%20014001.png) | ![Admin Teachers](App%20Screenshots/Screenshot%202026-04-28%20014017.png) |
| *Create subjects and assign teachers; view existing subjects with division info* | *Add schedule slots with subject, division, day, time, and lecture/lab type* | *Provision Firebase Auth accounts, map UIDs, and manage teacher directory* |

---

## 🧪 Testing

### Testing Framework

- **flutter_test** (built-in Flutter testing framework)

### Current Test Coverage

The project contains a single default widget test (`test/widget_test.dart`) that was auto-generated by `flutter create`. It tests the default counter app template and **does not reflect the current application** — it will fail if run against the CEMS codebase.

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

> **Note:** Comprehensive unit and widget tests have not yet been implemented. See [Future Improvements](#-future-improvements--roadmap) below.

---

## 🌐 Deployment

### Firebase Hosting (Web)

The project is configured for Firebase Hosting. The `firebase.json` serves `build/web` with SPA-style rewrites.

```bash
# Build the web app
flutter build web

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

**Hosting URL:** `https://cems-application.web.app` (or your custom domain)

### Android

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Production Considerations

- **Firestore Security Rules:** Ensure proper read/write rules are configured in Firebase Console to restrict access by role. The current codebase does not include a `firestore.rules` file.
- **API Key Restrictions:** Restrict Firebase API keys by domain/app in the Google Cloud Console.
- **Location Permissions:** Android and iOS require location permission declarations in their respective manifest/plist files.
- **Rate Limiting:** Consider Firestore usage costs for large deployments — the batch-fetch pattern used in the codebase (batches of 30 for `whereIn` queries) is optimized for Firestore's limits.

---

## 🤝 Contributing

Contributions are welcome! To contribute:

1. **Fork** the repository.
2. **Create a feature branch:** `git checkout -b feature/your-feature-name`
3. **Make your changes** and ensure `flutter analyze` passes with no issues.
4. **Test** your changes thoroughly.
5. **Commit** with clear, descriptive messages: `git commit -m "feat: add attendance export to CSV"`
6. **Push** to your fork: `git push origin feature/your-feature-name`
7. **Open a Pull Request** against the `main` branch.

### Development Standards

- Follow the [Dart style guide](https://dart.dev/effective-dart/style).
- Use `flutter analyze` to check for lint issues before committing.
- Keep widgets focused and reusable — follow the existing pattern in `lib/widgets/`.
- Do not commit `firebase_options.dart`, `google-services.json`, or `GoogleService-Info.plist`.

---

## 📄 License

This project does not currently have a license. All rights are reserved by the author.

---

## 🔮 Future Improvements / Roadmap

The following enhancements have been identified from the codebase analysis:

| Area | Improvement |
|---|---|
| **Testing** | Replace the default widget test with comprehensive unit, widget, and integration tests covering auth, attendance marking, and dashboard rendering. |
| **Firestore Security Rules** | Add a `firestore.rules` file with role-based access control (students can only read their own attendance, teachers can only manage their own sessions, etc.). |
| **Student Registration** | Add a self-service student registration flow or admin bulk-import feature (currently students must be manually created in Firebase Console). |
| **Attendance Export** | Allow teachers/admins to export attendance data as CSV/Excel for institutional records. |
| **Push Notifications** | Notify students when a session starts or when their attendance drops below threshold. |
| **Offline Support** | Enable Firestore offline persistence so the app works in low-connectivity environments. |
| **Batch/Section Support** | The data model already has a `batch` field in schedule documents — implement full UI support for batch-specific lab sessions. |
| **Analytics Dashboard** | Add charts and graphs (attendance trends over time, division-wide comparisons) for teachers and admins. |
| **Password Reset** | Add a "Forgot Password" flow on the login screen. |
| **Profile Editing** | Allow users to update their name and other profile details. |
| **Session History** | Let teachers view past sessions with attendance counts and timestamps. |
| **Multi-language Support** | Add localization for regional languages. |
| **Accessibility** | Audit and improve screen reader support and contrast ratios. |

---

<p align="center">
  Built with ❤️ using Flutter & Firebase
</p>
