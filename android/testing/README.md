# Local account integration tests

Tests use local Firebase Auth (`9099`) and Firestore (`8085`) with project ID `demo-streamify-android`. They create a named FirebaseApp with synthetic Google credentials, never the app's production FirebaseApp. No real Google account, production user document, or real sports-chat message is used.

`firestore.production-snapshot.rules` is an unchanged copy of the live project's rules retrieved on October 15, 2026. It exists solely to test current compatibility and account isolation. Do not deploy this testing directory to a production project.

From `android/`, with Node and JDK 21 available:

```powershell
npx -y firebase-tools@latest emulators:start --only auth,firestore --project demo-streamify-android --config testing/firebase.json
```

In a second terminal, with an Android emulator running:

```powershell
$env:ANDROID_SERIAL = 'emulator-5556' # replace with your test device from adb devices
.\gradlew.bat :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug
```

The test emulator must be able to reach host-loopback services through `10.0.2.2`. Only debug builds permit HTTP to the emulator/loopback hosts. Release builds retain the HTTPS-only policy and contain no emulator redirection.

Coverage includes Google credential sign-in through Firebase Auth, profile/onboarding preservation, separate guest and account libraries, web-created document IDs, movie/TV identity collisions, episode updates, team/search sync, queued offline writes, public chat reads, guest posting through anonymous authentication, chat schema and empty-message rejection, cross-account read denial, and player navigation/viewport regressions.

The real Google account picker and consent step require a Google account on a device. Mock credentials verify Firebase integration, not Google Play services or user consent. See the [Firebase emulator documentation](https://firebase.google.com/docs/emulator-suite/connect_auth) for the supported mock credential flow and [native Google sign-in documentation](https://firebase.google.com/docs/auth/android/google-signin) for production setup.
