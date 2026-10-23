# Streamify for iOS

Native SwiftUI interface based on the Android app in this repository. Requires iOS 17 or later, supports iPhone and iPad, and uses SwiftUI, WebKit, AVKit, URLSession and Keychain without third-party runtime packages.

The Android red accent, brand artwork, portrait hero, poster shelves, compact discovery menus, floating Home / Sports / Search / My list navigation, collections, and sports league cards are carried across to native iOS views. Native navigation, sheets, context menus, VoiceOver labels, Dynamic Type, safe areas, reduced motion, light/dark/system appearance, AirPlay, and Files import adapt the interface to iPhone.

## Current validation

The source and build configurations were prepared on Windows. All Swift files passed tree-sitter syntax parsing; resource JSON, property lists, 17 collection images, 15 provider templates, and the opaque 1024px app icon passed portable validation. **This is not a Swift compiler or simulator result.** No IPA has been compiled or signed locally, and no TestFlight build has been uploaded. The GitHub workflow must pass its Xcode build, eleven unit tests, and navigation/screenshot UI test before producing an unsigned device package.

## Test on your iPhone from Windows

You do not currently have an Apple Developer Program membership, so TestFlight is not available yet. A free personal-signing route is available for your own test device:

1. Push the `ios` directory and `.github/workflows/ios-check.yml` to your GitHub repository. Run **iOS build and tests** in GitHub Actions. It uses a macOS runner and generates the Xcode project from `project.yml`.
2. After the job passes, download the **Streamify-iOS-unsigned-for-local-signing** artifact and extract `Streamify-unsigned.ipa`.
3. Use [Sideloadly for Windows](https://sideloadly.io/) or another signing tool you already trust to sign this IPA with your own Apple Account and install it on your connected iPhone. Follow the tool's current setup instructions. Enter Apple credentials directly in that tool, never in chat or this repository.
4. Free personal signing expires after seven days and must be refreshed. [Sideloadly FAQ](https://sideloadly.io/faq).

The unsigned IPA cannot be installed merely by tapping it in Files. The simulator test-results artifact is also not an iPhone app. A failed CI run produces no usable device package.

After installation, open **More → Settings** and add a TMDB API key or read access token for movie and TV catalog data. The key stays in your iPhone Keychain. Anime and sports work without that key. No local `.env` credentials are bundled into this app.

## Build on a Mac

Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run from this folder:

```sh
brew install xcodegen
xcodegen generate
open Streamify.xcodeproj
```

Choose the Streamify target, set your unique bundle identifier and signing team, select your iPhone, and run. A personal Apple Account can sign a local development build through Xcode; an Apple Developer Program membership is required for TestFlight distribution. See [Apple's device-running guide](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices).

The generated project is ignored. Re-run `xcodegen generate` after adding source files; the specification includes the entire source tree. There is no React runtime or bundled website. Only external player pages use WKWebView.

## TestFlight later

[Apple's distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) describes account enrollment, archiving and TestFlight. Once you have membership:

1. Register a unique bundle ID and create its matching App Store Connect app record.
2. Create an Apple Distribution certificate with its private key and an App Store distribution provisioning profile for that exact bundle ID.
3. Add these repository **Actions variables**: `IOS_TEAM_ID`, `IOS_BUNDLE_ID`.
4. Add these repository **Actions secrets**: `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROFILE_BASE64`. These are the base64-encoded certificate export, its password, and the base64-encoded distribution profile.
5. For upload, also add `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8_BASE64` using an App Store Connect API key authorized to upload this app. Do not commit any signing files.
6. First ensure **iOS build and tests** passes. Run **iOS TestFlight** manually. Leave upload unchecked to export a distribution-signed IPA, or check upload to submit it to App Store Connect. Apple must process the upload before it appears in TestFlight; tester setup happens in App Store Connect.

The distribution IPA is intended for App Store Connect, not direct installation on arbitrary devices. The workflow uses an isolated runner keychain and removes signing material after the run. No Apple account, certificates, profile, or API key was created by this implementation.

## Implemented surfaces and differences

| Android surface | iOS implementation |
| --- | --- |
| Home | Swipe/automatic poster hero, play/save/info, carousel pause, Top 10, continue watching, recommendations, provider/genre shelves, collections |
| Movies / Shows / Anime | Independent category discovery with genres, sort, real paginated data |
| Search | Debounced mixed movie/show search, anime search, recent searches, native filters and load more |
| Details | Synopsis, genres, rating, trailer, save, cast biographies, credits, recommendations, season/episode picker |
| Collections | All 17 original franchises and artwork, search/genre filter, release-order collection movies |
| My list / History | Local persistence, movie/show/anime identity separation, search/type filters, remove and resume last episode |
| Sports | NFL/NBA/WNBA/NHL/MLB logos, ESPN schedules, local date handling, two-week strip/calendar, live/upcoming/final/following filters, list/carousel, search/follow teams, roster/results |
| Game center | Live score refresh, period scoring, team statistics, latest play, stream discovery with errors/empty states |
| Sports channels / Multi-watch | Four providers, seven broadcaster links, up to four selected stream tiles with reload/expand/remove; audio controls remain with each source |
| Player | All 15 movie/TV provider templates, verified AniList-to-MAL anime matching and SUB/DUB options, native persistent exit/reload/provider/Safari/AirPlay controls, embed/direct modes, episode picker/next episode |
| Downloads | Direct HTTPS MP4/M4V/MOV transfers with background URLSession and actual byte progress, cancel/retry/delete, Files import, native offline playback |
| Appearance / Settings / Preferences | Dark/light/system, Keychain catalog token, optional sports backend, default source, favorite genres |
| Account / cloud library / shared chat | Account and preference interface with honest device-only status. Google sign-in, cloud sync, and chat sending are not configured or implemented in this dependency-free first iOS version. Existing production Firebase settings are untouched. |

Other differences: category discovery uses an adaptive grid; Android download extraction, subtitle selection, exact seek/progress integration, player lock/hold-unlock, skip-intro, automatic ending overlays and app self-updates are not ported. AVKit supplies native controls for local/direct video; WKWebView providers supply their own video controls. An external provider opening is recorded in history but does not prove successful playback or provide a reliable timestamp. Team following and library state are local and do not sync with Android or the web yet. Provider availability and physical iPhone playback still need device validation.

## Source layout

```text
Streamify/App          App entry and native floating navigation
Streamify/Design       Shared theme, artwork, poster grids and state views
Streamify/Home         Hero, home shelves and discovery
Streamify/Browse       Search, categories, filters and pagination
Streamify/Media        Details, cast, collections, provider player, anime resolution
Streamify/Sports       Schedules, game center, teams, channels, multi-watch
Streamify/Downloads    Background direct-file transfers, Files import and offline player
Streamify/Library      Saved/history, settings, account status and preferences
Streamify/Data         TMDB/AniList clients, models, Keychain and local persistence
Streamify/Resources    Original Android artwork/config, icon, launch and privacy manifest
StreamifyTests         Network fixture, persistence, identity and provider/parser tests
StreamifyUITests       Navigation smoke test and attached screenshots
```

`python3 scripts/validate.py` validates prepared resources on any Python machine. Optional Swift grammar validation uses `python3 -m pip install --target .tools tree-sitter tree-sitter-swift` then `python3 scripts/validate.py --syntax`; it does not type-check SwiftUI. `prepare-assets.py` is only for recopying shared Android artwork and needs Pillow. All prepared assets are included with the source.
