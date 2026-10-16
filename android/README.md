# Streamify for Android

A standalone native Android version of the Streamify web app. All navigation, catalog, detail, episode, sports, library, and settings screens are written in **Kotlin and Jetpack Compose**. Only third-party video embeds use Android WebView, matching the providers used by the web app. There is no React runtime or bundled website.

## Open and run

1. Open this `android` directory as a project in Android Studio.
2. Install Android SDK Platform 36 if prompted. Use JDK 17 or newer (this workspace uses JDK 21).
3. Copy `local.properties.example` to `local.properties`. Let Android Studio set `sdk.dir`, and optionally add your TMDB API key or read access token as `TMDB_API_KEY`.
4. Sync Gradle, select an Android device or emulator running Android 8.0/API 26 or later, and run the `app` configuration.

The catalog key and optional backend can also be edited in the app's Settings. Saved settings override build-time defaults. No catalog data is fabricated when a key or service is unavailable; the app displays a setup or retry state. Sports work without a TMDB key.

From PowerShell in this directory:

```powershell
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
.\gradlew.bat :app:installDebug
```

On macOS/Linux, use `bash gradlew` for the same tasks. The debug APK is at `app/build/outputs/apk/debug/app-debug.apk`.

The project pins Gradle 9.3.1, Android Gradle Plugin 9.0.1, Kotlin/Compose compiler 2.3.20, and Compose BOM 2024.12.01. AGP supplies built-in Kotlin support; the Kotlin Android plugin is declared at the root to select the compiler version, and is not applied to the app. See [Android's AGP 9 documentation](https://developer.android.com/build/releases/agp-9-0-0-release-notes).

## Implemented

- Home: automatic/swipeable portrait hero with progress indicators and pause/resume, direct Play show/Play movie actions, compact filled category shortcuts, Top 10 Today, continue watching, recommendations, and provider/genre discovery. Small dropdowns sit beside each section heading on one row. Collections appear at the bottom with a compact Explore all link.
- Collections: the same 17 franchises and bundled artwork as the web app; featured rail, search, genre filters, and release-ordered collection details.
- Browse: debounced movie/TV search, recent searches, popular/top-rated, genre and provider filters, paginated results, loading/error/empty states.
- Details: synopsis, genres, rating, clickable cast biographies and filmographies, trailer link, recommendations, seasons and episodes.
- Library: persistent saved titles and history, last selected episode, search/type filters, removal, and real-time web account sync.
- Account: Google-only native sign-in, profile creation, genres/team onboarding, sign-out, separate guest/account caches, and offline sync status.
- Sports: official bundled NFL/NBA/WNBA/NHL/MLB league logos, league directory, all-league schedules, live/upcoming/final/following filters, two-week calendar, list/slider views, team search and following, team schedules/results/rosters, and game-center scoring/statistics/latest play.
- Sports channels: all four channel providers and seven broadcaster links from the current web app. Up to four selected game sources can be opened in native multi-watch tiles.
- Sports chat: the web's shared matchup rooms in the game center and a player chat panel, with native message entry and failure feedback.
- Player: all 15 web providers, explicit WebView sizing, measured-view initialization, embedded/direct modes, persistent native exit/reload controls, fullscreen exit, renderer recovery, source switching, TV episode picker/next episode, and browser fallback.
- Settings: dark/light/system themes, TMDB key/token, optional sports backend, default provider, and data-source information.
- Native back handling, adaptive poster grids, system insets, accessible control labels, the web logo in the header/launcher, a logo-and-title header with Search/My list/More actions, and floating translucent bottom navigation. Account and Settings remain available in More.

## Data and configuration

`TMDB_API_KEY` accepts a TMDB v3 API key or a read access bearer token. A bundled key can be extracted from an APK; use an authenticated backend proxy for a production app if the credential must remain private. Do not put service-account credentials or server secrets into this setting. `local.properties` is ignored by Git.

`API_BASE_URL` is optional and must be an HTTPS origin for the existing Streamify backend, without `/api` at the end. When set, the client calls:

```text
GET /api/schedule?league=nba&start=YYYY-MM-DD&end=YYYY-MM-DD
```

When blank, the client uses ESPN scoreboards. It fetches adjacent UTC days and filters to the selected local day. Partial schedule failures are surfaced. Scores and game-center summaries poll every minute only while the screen is in the foreground. Team pages use ESPN team, schedule, and roster endpoints. The web backend also uses league-specific feeds; detailed statistics can differ when those feeds expose different fields.

Sports embeds are discovered via the existing `streamed.pk` service. Matching requires both full team names, the sport category, and a recent match. Unavailable or unmatched streams produce an empty/retry state. Provider availability and actual video playback depend on the external service, region, and content. Loading a provider page does not prove its video plays.

The player permits HTTPS provider frames, disables file/content access and popups, preserves TLS validation, and prevents advertising from replacing the top-level player page. Third-party cookies and media playback are enabled for embed compatibility. A narrowly scoped document-start compatibility script tolerates Android's unsupported orientation-lock API on the selected provider's origin. No JavaScript-to-native bridge is exposed. Explicit `MATCH_PARENT` WebView layout parameters prevent a zero-height CSS viewport inside Compose; navigation begins only after the native view has dimensions. Native close/reload controls remain outside the provider and fullscreen view.

## Scope and differences from the web app

See [PARITY.md](PARITY.md) for the route-by-route audit and remaining differences. Google is the only Android sign-in option, as requested. Signed-in libraries, history, searches, followed teams, and favorite genres use the web app's existing Firebase collections. Guest data remains on the device and is not uploaded automatically. Android shows the latest 200 history entries and 100 chat messages. AI search exists as an unused web hook and is not exposed in the current web search screen. Watch history records opening the player and episode selection, not video progress; the web embeds do not provide one reliable progress protocol. Trailers open in the user's browser or YouTube app.

The registered Firebase Android app and debug signing certificates are configured in `app/google-services.json`. A different debug keystore or release signing key needs its own SHA fingerprints registered in Firebase and a refreshed configuration. Firebase config is public client configuration; service-account keys and OAuth client secrets must never be added to the APK. Production rules and auth providers were left unchanged. The existing chat rules require authentication but do not enforce sender identity or field limits on the server; Android enforces its own input limits, and server-rule hardening remains a separate deployment concern.

Builds are debug-signed for development. A release needs your application ID/signing configuration, store assets, distribution review, and validation of the selected content providers. No app-store publication is performed by this project.

## Source layout

```text
app/src/main/java/com/streamify/app/
  MainActivity.kt             Native tabs, home, browse, library, settings
  StreamifyViewModel.kt       Screen state, requests, saved media and history
  PlayerActivity.kt           Provider playback and fullscreen lifecycle
  data/Models.kt              Models, media identity, URL and stream matching
  data/StreamifyRepository.kt TMDB, sports schedule and stream requests
  data/LocalStore.kt          Device preferences and library persistence
  data/AccountRepository.kt   Google auth, profile and account-scoped sync
  data/CloudContracts.kt      Web identity and team abbreviation mapping
  data/LiveChatRepository.kt  Shared matchup chat reads/writes
  data/PlayerDocument.kt      Provider frame and orientation compatibility
  data/SportsData.kt          ESPN teams, rosters and game-center data
  ui/Components.kt            Theme, images, poster rails and state components
  ui/HomeScreen.kt            Home shelves, automatic carousel and hero actions
  ui/HomeChrome.kt            Logo/title header and floating bottom navigation
  ui/DetailScreen.kt          Movie/TV details and episodes
  ui/ExploreScreens.kt        Collections, cast profiles and discovery shelves
  ui/AccountScreens.kt        Google sign-in, account and preferences
  ui/LiveChat.kt              Game-center and player chat interface
  ui/SportsScreen.kt          League directory, search and schedules
  ui/SportsDetails.kt         Game center, team profiles and channels
  ui/MultiWatchScreen.kt      Up to four selected sports streams
app/src/main/assets/media-servers.json
app/src/main/assets/collections.json
app/src/test/java/com/streamify/app/data/ModelsTest.kt
app/src/test/java/com/streamify/app/data/CloudContractsTest.kt
app/src/androidTest/java/com/streamify/app/PlayerNavigationTest.kt
app/src/androidTest/java/com/streamify/app/AccountIntegrationTest.kt
```

Tests cover mixed TMDB results and media identity, persistence-model round trips, provider templates, URL restrictions, stream matching, sports responses, web document compatibility, Google credentials through Firebase Auth, account isolation, offline sync, and player navigation. See [testing/README.md](testing/README.md) to run the Firebase emulator tests.

## Verified in this workspace

On October 15, 2026:

- `assembleDebug`, `testDebugUnitTest`, `connectedDebugAndroidTest`, and `lintDebug` completed successfully: 13 unit tests, nine instrumented tests, and zero lint errors. After the Home styling update, assemble/lint passed again with zero errors and 35 non-blocking warnings; layout and carousel changes were verified on the emulator.
- Local Firebase tests verified mock Google sign-in, profile/onboarding preservation, web document compatibility, account isolation, offline changes uploading after reconnection, and the shared chat format. The live Google account picker/consent and production account sync still need a user sign-in on a device.
- Confirmed that Continue with Google opens Google's native account setup on a clean emulator, and cancelling returns to the usable account screen. Installed the final APK on the visible Pixel 7 emulator and opened the Google-only account screen.
- Verified actual movie playback (Interstellar) and TV playback (The Bear, season 1 episode 1) through Vidy on Android 16 / API 36. Both videos were unpaused with advancing playback clocks and loaded video duration. Other providers and physical devices still need individual validation.
- Fixed the black player at its source: a wrap-content native WebView produced a zero-height iframe. Both the main player and multi-watch now use explicit fill-parent layout parameters and begin navigation after layout.
- Instrumented regressions verify a non-zero iframe viewport, exit/reload controls for a failed source, native fullscreen Back/close handling, and Back dismissing sports chat before closing the player. Confirmed real movie exit returns to details and Browse.
- Verified the Home collections rail with the web artwork, collection browser, and Harry Potter's eight movies in release order.
- Verified the sports league artwork, team search, and the Lakers' schedule and roster. The emulator crash log remained empty.
- Home polish: verified automatic carousel advancement and pause/resume, provider menus, bottom navigation, collections at the end of the page, and single-line buttons at 360dp with 130% text size. Carousel rotation pauses offscreen, during dragging/vertical scrolling, and in the background; it is disabled for touch exploration and starts paused when system animations are disabled.
- Reference-design pass: verified the small media/provider dropdowns beside headings, compact Collections link, floating Home/Sports/Search/My list navigation, and header menu access. Direct hero Play opens the native player and Close returns to Home. On narrow screens or enlarged text, the genre heading becomes "Genres" to leave room for its controls. The build and lint pass with no errors; screenshots are in `build/verification/reference-*.png`.
- Existing catalog/search, saved-title/history persistence, TV season switching, NHL game/stream discovery, and team following were also exercised during the Android port. See PARITY.md for the remaining platform differences and device validation limits.

Local screenshots, UI dumps, and the final build log are under ignored `build/verification/`. The current debug APK remains at `app/build/outputs/apk/debug/app-debug.apk`.

The parent React app and its existing files are independent of this project.
