# Family Calendar

Family Calendar is a Flutter-based family productivity app for capturing everyday notes, coordinating household schedules, and turning voice or text memos into actionable calendar tasks. It combines a mobile-first Flutter client with Firebase Authentication, Cloud Firestore, Firebase Storage, Cloud Functions, and OpenAI-powered language features.


## Core Features

### Account and Session Management

- Email/password registration with email verification.
- Google sign-in support.
- Firestore-backed user profile records with display name, email, avatar, bio, status, and login metadata.
- Local session expiry management with automatic sign-out after extended inactivity.

### Memo Hub

- Personal memo feed grouped by date.
- Text memo creation and editing.
- Recorded voice memo creation from the main memo screen.
- Voice recording with AAC-LC `.m4a`, mono audio, `44100 Hz`, `64000 bps`, elapsed-time feedback, amplitude feedback, and wakelock support while recording.
- Firebase Storage upload for recorded audio.
- Firestore memo records with audio metadata, AI processing status, and local fallback path information.
- Recorded voice memo detail screen with audio playback, status updates, generated note text, and task creation.

### AI Memo Processing

- Recorded voice memos are processed by Firebase Cloud Functions after the memo document is created.
- Long recordings are handled by backend audio chunking before transcription.
- OpenAI transcription and summarization generate an English memo body from uploaded audio.
- Clear fallback output is persisted when no speech is recognized.
- Text memo detail supports realtime dictation through an OpenAI Realtime transcription client-secret flow, with a device speech-recognition fallback path.
- Memo content can be analyzed into a prefilled task draft.

### Calendar and Tasks

- Calendar view for the signed-in user's active events.
- Task creation and editing with title, description, category/type, date, start/end time, family, participants, reminder fields, repeat fields, status, and creator metadata.
- Firestore-backed `events` collection.
- Task invitations for selected participants.
- Notifications for pending task invitations and family invitations.

### Family Collaboration

- Family group creation.
- Family selection and membership screens.
- Invite users by email.
- Member role and family membership storage in Firestore.
- Accept/refuse flows for family invitations.

### Onboarding and UX

- First-run guided tour across memo creation, voice memo capture, navigation to Today, and calendar task creation.
- Shared bottom navigation for Memo, Family, Today, and Settings.
- Centralized theme styling in `lib/themes/app_theme.dart`.
- Profile settings with system avatar selection and image upload.

## Tech Stack

| Layer | Technology |
| --- | --- |
| Client | Flutter, Dart, Material 3 |
| Platforms | Android, iOS, macOS, web, Windows project scaffolds |
| Auth | Firebase Authentication, Google Sign-In |
| Data | Cloud Firestore |
| Files | Firebase Storage |
| Backend | Firebase Cloud Functions v2, TypeScript |
| AI | OpenAI chat, transcription, and realtime transcription APIs |
| Audio | `record`, `just_audio`, `speech_to_text`, `flutter_tts`, `wakelock_plus` |
| Local state | `shared_preferences` |
| Styling | Google Fonts, custom app theme |

## Repository Structure

```text
.
|-- android/                         # Android platform project
|-- ios/                             # iOS platform project
|-- macos/                           # macOS platform project
|-- web/                             # Web platform project
|-- windows/                         # Windows platform project
|-- assets/images/                   # App logos and image assets
|-- functions/                       # Firebase Cloud Functions backend
|   |-- src/index.ts                 # AI, transcription, memo, and chat functions
|   |-- package.json                 # Backend scripts and dependencies
|   `-- tsconfig.json
|-- lib/
|   |-- main.dart                    # Firebase bootstrap and auth gate
|   |-- firebase_options.dart        # FlutterFire generated Firebase config
|   |-- models/                      # Shared Dart models
|   |-- navigation/                  # Bottom-navigation routing
|   |-- screens/                     # App screens and feature flows
|   |-- services/                    # Firestore, invitation, session, onboarding, realtime AI services
|   |-- testing/performance/         # Memo benchmark helpers
|   |-- themes/                      # AppTheme and visual constants
|   `-- widgets/                     # Shared UI components
|-- test/
|   |-- widget_test.dart
|   `-- performance/                 # Memo performance benchmark tests
|-- firebase.json                    # Firebase project and function deploy config
|-- pubspec.yaml                     # Flutter dependencies and assets
`-- README.md
```

## Prerequisites

- Flutter SDK compatible with Dart `^3.10.7`.
- Firebase CLI.
- Node.js compatible with the Functions runtime declared in `functions/package.json` (`node: 24`).
- Android Studio/Xcode as needed for device or simulator builds.
- A Firebase project with Authentication, Cloud Firestore, Firebase Storage, and Cloud Functions enabled.
- An OpenAI API key stored as a Firebase Functions secret named `OPENAI_API_KEY`.

## Local Setup

1. Install Flutter dependencies:

   ```powershell
   flutter pub get
   ```

2. Install Cloud Functions dependencies:

   ```powershell
   cd functions
   npm install
   cd ..
   ```

3. Confirm Firebase configuration:

   The repository is configured for the Firebase project `family-calendar-65220` through `.firebaserc`, `firebase.json`, and `lib/firebase_options.dart`.

   If you connect a different Firebase project, regenerate the FlutterFire config:

   ```powershell
   flutterfire configure
   ```

4. Configure the OpenAI secret for Cloud Functions:

   ```powershell
   firebase functions:secrets:set OPENAI_API_KEY
   ```

5. Run the Flutter app:

   ```powershell
   flutter run
   ```

## Firebase Backend

Cloud Functions live in `functions/src/index.ts` and are deployed to `australia-southeast1`.

Important callable and trigger functions include:

- `chatWithAI` - AI assistant chat that can return draft calendar events.
- `createRealtimeTranscriptionClientSecret` - creates short-lived Realtime transcription credentials for text memo dictation.
- `summarizeVoiceMemo` - summarizes direct voice memo input.
- `summarizeRecordedVoiceMemo` - manually summarizes an existing recorded memo.
- `summarizeRecordedVoiceMemoOnCreate` - Firestore trigger that processes newly created recorded voice memo documents.
- `analyzeMemoToTask` - converts memo text into a task draft.

Build and validate Functions locally:

```powershell
cd functions
npm run lint
npm run build
```

Deploy Functions:

```powershell
firebase deploy --only functions
```

View backend logs:

```powershell
firebase functions:log
```

## Data Model Overview

The app relies on these main Firestore collections:

- `users` - user profile, onboarding state, session-related metadata, avatar information, and family references.
- `families` - family groups, member subcollections, roles, and membership state.
- `events` - calendar tasks/events with participant IDs, timestamps, status, category/type, notes, and creator metadata.
- `memos` - text and recorded voice memos, including audio URLs, local audio metadata, generated body text, and AI status fields.
- `notifications` - family invitations, task invitations, read state, sender/recipient data, and invitation status.
- `voice_memos` - legacy or alternate voice memo summary records used by the dedicated voice memo flow.

Recorded voice memo documents in `memos` use fields such as:

- `memoType: "voice"`
- `audioUrl`
- `audioStoragePath`
- `localAudioPath`
- `localAudioFileBytes`
- `audioDurationMillis`
- `aiSummaryStatus`
- `aiSummaryModel`
- `aiTranscriptionModel`
- `transcriptChunkCount`

## AI Recording Pipeline

The recorded voice memo flow is intentionally backend-driven:

1. The Flutter client records `.m4a` audio and writes a memo document.
2. Audio is uploaded to Firebase Storage under `voice_memos/{uid}/{memoId}.m4a`.
3. The memo starts with `aiSummaryStatus: "pending"`.
4. `summarizeRecordedVoiceMemoOnCreate` runs when the Firestore document is created.
5. The function downloads audio from Storage.
6. Files larger than the conservative 24 MB threshold are split with ffmpeg.
7. Chunks are transcribed with `gpt-4o-mini-transcribe`.
8. The merged transcript is summarized with `gpt-4o-mini`.
9. The generated English note, transcript metadata, model names, and final status are written back to Firestore.
10. The recorded memo detail screen listens for Firestore updates and refreshes the UI when processing completes.

This keeps long-running AI work alive even if the user leaves the detail page while staying in the app.

## Testing and Quality Checks

Run the default Flutter tests:

```powershell
flutter test
```

Run memo performance benchmarks:

```powershell
flutter test test/performance/memo_performance_test.dart
```

Run targeted analysis for frequently edited memo files:

```powershell
flutter analyze lib/screens/memo_screen.dart
flutter analyze lib/screens/memo_detail_screen.dart
flutter analyze lib/screens/recorded_voice_memo_detail_screen.dart
```

Build the Android debug APK:

```powershell
flutter build apk --debug
```

Build the Android release APK:

```powershell
flutter build apk --release
```

## Platform Permissions

Android currently declares:

- `android.permission.INTERNET`
- `android.permission.RECORD_AUDIO`

iOS declares microphone and speech-recognition usage descriptions in `ios/Runner/Info.plist`.

When adding camera, photo library, push notification, or background audio features, update the corresponding platform permission files before release builds.

## Development Notes

- Keep text memo realtime dictation and recorded voice memo processing separate. They use different code paths, models, and lifecycles.
- Recorded voice memo processing should be treated as Firestore/Storage/Functions work, not as page-owned UI work.
- Use targeted `dart format` and file-scoped `flutter analyze` on noisy Flutter changes to avoid unrelated churn.
- For AI failures, inspect `firebase functions:log` before changing prompts or client code.
- For long-recording issues, check local audio bytes, upload status, Firestore `aiSummaryStatus`, transcript length, and backend logs before assuming the summary prompt failed.

## Common Commands

```powershell
# Flutter dependencies
flutter pub get

# Run app
flutter run

# Analyze project
flutter analyze

# Run tests
flutter test

# Build Functions
cd functions
npm run build

# Deploy Functions
firebase deploy --only functions

# Show Functions logs
firebase functions:log
```

## Current Project Status

The project is an active Flutter/Firebase application with production-style app flows and ongoing iteration around memo capture, AI summarization, realtime dictation, task conversion, family collaboration, and calendar scheduling. The README should be kept updated whenever Firestore schemas, Cloud Function names, OpenAI models, platform permissions, or release/build steps change.
