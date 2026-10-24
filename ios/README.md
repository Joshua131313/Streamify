# Streamify for iOS

Native SwiftUI interface based on the Android app in this repository. Requires iOS 17 or later, supports iPhone and iPad, and uses SwiftUI, WebKit, AVKit, URLSession and Keychain without third-party runtime packages.

The Android red accent, brand artwork, portrait hero, poster shelves, compact discovery menus, floating Home / Sports / Search / My list navigation, collections, and sports league cards are carried across to native iOS views. Native navigation, sheets, context menus, VoiceOver labels, Dynamic Type, safe areas, reduced motion, light/dark/system appearance, AirPlay, and Files import adapt the interface to iPhone.

## Version 1.1.2

The current source refines the bounded Home header, slimmer floating navigation and keyboard handling, high-resolution hero artwork, and card-to-detail transitions. Root pages support interactive horizontal paging, gated to avoid scrolling rails, controls, web players and presented details. Catalog and sports search open dedicated dialogs. Detail trailers have no extra native control strip. History uses compact landscape cards with actual saved playback progress, and shared button surfaces use a 12-point corner radius. Sports adds modern game/score/roster tables, bold final winning scores without a separate Winner badge, player photos, server switching inside the player and each multi-watch tile, and swipe-left player exit. Sports playback keeps the same game, source and playback surface across app returns. Its Picture in Picture action requests the default iOS system player only when the provider reports support; unsupported sources stay in the full player with an explanation. Downloads cache artwork on disk and use compact cards; the full-screen offline player has overlaid controls, real seek/resume, speed, audio/captions, local SRT/VTT import, lock, and episode switching. These source changes await combined CI and physical-device verification and require a newly built IPA; the installed 1.1.1 build 12 does not update itself.

## Previous 1.0.0 validation

On October 23, 2026, the [macOS CI build](https://github.com/Joshua131313/Streamify/actions/runs/40000855365) passed **12 unit tests and one navigation UI test**, with zero failures, on an iPhone 17 Pro simulator. This includes real Keychain read/write/update/delete, saved/history persistence, catalog and sports fixtures, stream matching, download attempt identity, root titles, a single floating navigation bar, and saving settings. The five exported screenshots were visually reviewed; the duplicate system tab bar and unsigned-simulator Keychain error found in the first pass are fixed.

The ARM64 iPhone Release build also passed. That run's IPA was **version 1.0.0, build 3, iOS 17+**, bundle ID `com.streamify.app`. [Download the previous CI device package](https://github.com/Joshua131313/Streamify/actions/runs/40000855365/artifacts/12522751198) or [its simulator screenshots](https://github.com/Joshua131313/Streamify/actions/runs/40000855365/artifacts/12522142051). The local `build/Streamify-unsigned.ipa` and its `.sha256` sidecar are replaced when a newer build is downloaded.

These results describe **1.0.0**, not the current 1.1.2 changes. Version 1.1.0 build 7 was subsequently installed on the iPhone through iLoader. End-to-end physical-device playback has not been verified, and no TestFlight upload has been performed. Portable Swift grammar, resource JSON, property lists, 17 collection images, 15 provider templates, and the opaque 1024px app icon also passed the previous validation.

## Test on your iPhone from Windows

The current free-account setup uses [iLoader](https://iloader.app/), which successfully installed the first build. Sideloadly failed at Apple sign-in before installation. To install a newly built update:

1. Run **iOS build and tests** on `codex/native-ios` in GitHub Actions. Use the **Streamify-iOS-unsigned-for-local-signing** artifact from the successful run for the desired version, and extract it. Earlier runs contain earlier app versions.
2. Keep Streamify installed. Connect and unlock the iPhone, open iLoader on Windows, and select the phone. Use the same Apple Account as the existing installation; enter credentials and verification codes directly in iLoader.
3. Choose **Import IPA**, then select `C:\Users\josht\Documents\streamify-main\ios\build\Streamify-unsigned.ipa` after replacing that local file with the new build. Keep the phone connected while iLoader signs and installs it.
4. Open Streamify. If iOS requests it, enable **Settings → Privacy & Security → Developer Mode**, restart, unlock, and confirm. [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

Free-account provisioning expires after seven days and needs refreshing. [Apple's account limits](https://developer.apple.com/help/account/basics/about-your-developer-account). iLoader supports wireless connections after device setup, but it still runs on a computer; Wi-Fi removes the cable requirement, not the computer requirement. [iLoader features](https://iloader.app/).

The unsigned IPA cannot be installed merely by tapping it in Files. The simulator test-results artifact is also not an iPhone app. Device compilation runs alongside simulator tests so a test package can be installed promptly; an available IPA does not mean the simulator tests passed. Check both jobs before publishing a release.

After installation, open **More options → Settings** from the top-right menu and add a TMDB API key or read access token for movie and TV catalog data. The key stays in your iPhone Keychain. Anime and sports work without that key. No local `.env` credentials are bundled into this app.

## Checking updates on the iPhone

**Settings → App updates → Check for updates** reads public GitHub releases and only offers a newer stable `ios-v<version>` release with a valid IPA asset. Android releases, drafts and prereleases are ignored. It shows release notes plus Download IPA and Share IPA link actions; checks are manual and require no GitHub token. No public iOS release has been published yet, so the current check correctly reports that none is available. CI artifacts remain the source of test builds.

The IPA still needs signing and installation. Streamify cannot replace its own executable simply by downloading it. When SideStore is installed, the update page also shows **Install with SideStore** for a newer release and **Add Streamify to SideStore** for its update source, using the [official SideStore URL schemes](https://docs.sidestore.io/docs/advanced/url-schema). To update using only the iPhone after one initial computer setup, use [SideStore's official setup guide](https://docs.sidestore.io/docs/installation/prerequisites). SideStore needs Wi-Fi and LocalDevVPN enabled when installing, updating or refreshing apps. It retains the free-account seven-day refresh requirement. Keep the original Streamify installation and import the newer IPA through SideStore; its [FAQ](https://docs.sidestore.io/docs/faq) describes transferring existing apps without deleting their data. Signing-service availability can still affect installation.

TestFlight offers iPhone update buttons and automatic updates once the app is distributed through it, but publishing requires Apple Developer Program membership. [Apple's TestFlight instructions](https://testflight.apple.com/), [developer account requirements](https://developer.apple.com/help/account/basics/about-your-developer-account).

### SideStore source setup

After initial [SideStore setup](https://docs.sidestore.io/docs/installation/prerequisites), keep Streamify installed, enable Wi-Fi and LocalDevVPN, and sign in to SideStore with the same Apple Account. Refresh SideStore first. Once the new IPA and source are published, add this URL in **SideStore → Sources → +**:

```text
https://raw.githubusercontent.com/Joshua131313/Streamify/refs/heads/codex/native-ios/ios/sideload-source.json
```

This is the planned stable source address; it is usable only after `ios/sideload-source.json` has been published on `codex/native-ios`. Install/update Streamify from that source without deleting the existing app. Later releases can be installed from SideStore on the phone, and SideStore still needs regular refreshes before the seven-day expiry.

For maintainers: after verifying the **new** device IPA, prepare its source locally from the repository root (replace `VERSION` and `YYYY-MM-DD` with the verified version and release date):

```sh
python ios/scripts/make-sideload-source.py --ipa ios/build/Streamify-unsigned.ipa --expected-version VERSION --date YYYY-MM-DD
```

The script reads the IPA's exact bundle/version/build/minimum iOS and archive size; it rejects a version mismatch, simulator package, signed/provisioned package markers or app extensions. It writes `ios/sideload-source.json` for [AltStore Classic's source format](https://faq.altstore.io/developers/make-a-source), also used by [SideStore sources](https://docs.sidestore.io/docs/faq). It performs no network requests or publication. Publish the verified IPA as `Streamify-VERSION-unsigned.ipa` in release `ios-vVERSION`, verify the public asset/icon URLs, then publish the generated source. An unsigned, extension-free build lists no signing entitlements; any future entitlement change requires review before publishing the feed.

## Build on a Mac

Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run from this folder:

```sh
brew install xcodegen
xcodegen generate
open Streamify.xcodeproj
```

Choose the Streamify target, set your unique bundle identifier and signing team, select your iPhone, and run. A personal Apple Account can sign a local development build through Xcode; an Apple Developer Program membership is required for TestFlight distribution. See [Apple's device-running guide](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices).

The generated project is ignored. Re-run `xcodegen generate` after adding source files; the specification includes the entire source tree. There is no React runtime or bundled website. External players and trailer previews use WKWebView.

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
| Home | Swipe/automatic poster hero with timed animated indicators, tap-to-select slides, pause, play/save/info, filled selectors, Top 10, continue watching, recommendations, provider/genre shelves, collections; automatic cycling pauses while inactive, covered, dragging, or using reduced motion/VoiceOver |
| Movies / Shows / Anime | Independent category discovery with genres, sort, real paginated data |
| Search | Dedicated catalog search dialog with debounced mixed movie/show search, anime search, recent searches, native filters and load more; sports has a separate game/team search dialog |
| Details | Muted inline autoplay trailer with provider controls and poster fallback; preview pauses when covered, scrolled away or inactive. Synopsis, genres, rating, save, cast biographies in a medium/large sliding sheet, credits, recommendations, season/episode picker. On iOS 18+, native interactive zoom returns to the tapped card; iOS 17 uses a dismissible sheet. Reduced motion skips the zoom. |
| Poster cards | Shared 2:3 clipped artwork surface for loaded, loading and missing images; consistent card widths within each rail/grid, with fixed title space |
| Collections | All 17 original franchises and artwork, search/genre filter, release-order collection movies |
| My list / History | Local persistence, movie/show/anime identity separation, search/type filters, compact landscape resume cards with actual progress and remaining time, remove and resume last episode |
| Sports | NFL/NCAAF/NBA/WNBA/NHL/MLB, ESPN schedules (college football merges FBS and FCS), mixed Today schedule below one compact toolbar with small league logos and multiple selection. Full calendar with two-week event markers, status filters and list/slider display open in sheets; channels, multi-watch, refresh and populated-first league browsing remain in the overflow menu. Dedicated game/team search, local times, following, rosters and results are retained. |
| Game center | Live score refresh; aligned team-by-quarter/period/inning scoring table with pinned totals and horizontal overflow for long games; bold winning scores without a Winner badge, comparison tables, roster photos, latest play, stream discovery with errors/empty states |
| Sports channels / Multi-watch | Four providers, seven broadcaster links, in-view live-game picker, up to four stable stream tiles with nested stream selection, reload/expand/remove and one selected audible stream; other HTML media tiles are muted. App-owned sports playback keeps the selected game/server through background returns and requests native system Picture in Picture for supported providers; the system restore action returns to the same player. |
| Player | All 15 movie/TV provider templates, verified AniList-to-MAL anime matching and SUB/DUB options, native persistent exit/reload/provider/Safari/AirPlay controls, embed/direct modes, episode picker/next episode |
| Downloads | Download actions on movie details, selected TV episodes and the player; quality selection resolves an available direct video file using the Android source flow. Background transfers, byte progress, duplicate prevention, retry, cancel/delete, direct HTTPS MP4/M4V/MOV links, Files import and disk-cached poster cards. Full-canvas offline player with transport/seek, speed, embedded audio/captions, local subtitle import, resume, episode/next selection, lock, fit/fill, AirPlay and supported-device PiP. Streaming-only/DRM sources produce an explanation; anime and live sports downloads are unavailable. |
| Appearance / Settings / Preferences | Dark/light/system, Keychain catalog token, optional sports backend, default source, favorite genres and manual iOS release checks |
| Account / cloud library / shared chat | Account and preference interface with honest device-only status. Google sign-in, cloud sync, and chat sending are not configured or implemented. Existing production Firebase settings are untouched. |

Other differences: category discovery uses an adaptive grid. Offline playback uses custom controls over AVPlayer; iOS rotation, AirPlay, PiP and volume follow platform capabilities. Skip-intro requires timing metadata that is not currently provided. WKWebView providers supply their own video controls and may restrict autoplay/audio or prevent timestamp access. Actual HTML5/native video progress is recorded only when the player can report valid timestamps; opening a protected provider alone never fabricates progress. Team following and library state are local and do not sync with Android or the web. Native iOS transitions and sheets adapt to OS/accessibility settings. The update check does not sign or install IPAs. Provider availability and the new 1.1.2 interactions still need physical-iPhone validation.

Sports system PiP depends on the external provider and iOS video support. The existing playback view stays mounted while native PiP is active, and restoring PiP returns to the same selected stream. Unsupported provider PiP leaves the full player visible. The test suite includes WebKit-document identity checks across background/foreground returns and a separate real AVKit PiP flow that skips only when the system reports it unavailable; these new flows still await CI results. A synthetic 10-minute H264 resource exercises real offline play, pause, seeking and resume without downloading a video.

## Source layout

```text
Streamify/App          App entry and native floating navigation
Streamify/Design       Shared theme, artwork, poster grids and state views
Streamify/Home         Hero, home shelves and discovery
Streamify/Browse       Search, categories, filters and pagination
Streamify/Media        Details, cast, collections, provider player, anime resolution
Streamify/Sports       Schedules, game center, teams, channels, multi-watch
Streamify/Downloads    Background direct-file transfers, Files import and offline player
Streamify/Library      Saved/history, settings, account status, preferences, iOS update checks
Streamify/Data         TMDB/AniList clients, models, Keychain and local persistence
Streamify/Resources    Original Android artwork/config, icon, launch and privacy manifest
StreamifyTests         Network fixture, persistence, identity and provider/parser tests
StreamifyUITests       Screen/interaction checks and attached screenshots
```

`python3 scripts/validate.py` validates prepared resources on any Python machine. Optional Swift grammar validation uses `python3 -m pip install --target .tools tree-sitter tree-sitter-swift` then `python3 scripts/validate.py --syntax`; it does not type-check SwiftUI. `prepare-assets.py` is only for recopying shared Android artwork and needs Pillow. All prepared assets are included with the source.
