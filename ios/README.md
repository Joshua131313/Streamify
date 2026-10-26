# Streamify for iOS

Native SwiftUI interface based on the Android app in this repository. Requires iOS 17 or later, supports iPhone and iPad, and uses SwiftUI, WebKit, AVKit, URLSession and Keychain. Guest sports chat uses Firebase Core, Auth and Firestore; the WidgetKit extension has no Firebase dependency.

The Android red accent, brand artwork, portrait hero, poster shelves, compact discovery menus, floating Home / Sports / Search / My list navigation, collections, and sports league cards are carried across to native iOS views. Native navigation, sheets, context menus, VoiceOver labels, Dynamic Type, safe areas, reduced motion, light/dark/system appearance, AirPlay, and Files import adapt the interface to iPhone.

## Version 1.1.2

The current source includes compact live sports cards, a small horizontal league rail with Followed teams first, one selected league scope, and direct Live/Pregame/Final tabs. College football, mixed live schedules, accessible score and roster tables, and small winning-score chevrons are retained. Verified possession and colored football field progress appear only when the feed supplies them. The background fills both system safe areas; root tab changes are instant. Search opens from its input, cards have native press/context interactions, and history shows actual saved progress.

Sports uses the embedded provider's fullscreen control, with no added Streamify fullscreen button. A downward drag returns the player to its game card; horizontal-swipe dismissal is removed. The retained player preserves its selected stream across app returns and uses system Picture in Picture when the provider and device support it.

Cold launch opens the cinematic profile chooser with original detailed 3D avatar artwork, a compact three-column grid, and an Edit tile. Portrait artwork stays visible above a warm lower gradient; the bundled Hobbit artwork is available offline. Up to five profiles keep separate favorites, history, searches, teams, genres, appearance and video provider. The selected avatar appears in the bottom bar and selection has haptic feedback. Real account sign-in stores profile metadata/preferences in Firebase with separate guest/account caches, pending-write recovery and visible sync status. Guest sports chat joins the same matchup rooms as Android and creates an anonymous identity only on the first Send; anonymous chat does not enable profile sync.

Sports and catalog navigation retain loaded results while refreshing in the background. The shared bounded response cache deduplicates requests and separates configuration, URL, query and page; explicit refresh bypasses fresh cached data. Sports continues periodic score refreshes. Fullscreen/PiP restoration tracks WebKit presentation ownership so an empty app player window cannot cover a video still owned by the provider's fullscreen surface. These source changes are pending the next macOS regression run.

Downloads group shows into episode pages with season sections, cached artwork, circular progress and swipe/context actions. Quality is exact: selecting 1080p never silently downloads 480p. Choose quality is available on existing catalog downloads. An expired URL can refresh once at the same quality; this is not an alternate provider. The offline player includes Android-style skip/hold-to-unlock animations, hidden edge adjustments and a thumb-following 208×117 video-frame seek preview. Invalid or incompatible files are rejected before being marked ready.

## Current verification and delivery

Build 40 was installed on the physical iPhone through iLoader on October 25, 2026; the installer confirmed completion. [Build 40](https://github.com/Joshua131313/Streamify/actions/runs/40085796275), source `538ee39985fbef0487b53f18ab63c2d88304a318`, passed its ARM64 iPhone Release build, all 148 unit tests and eight player UI cases. One real system-PiP check skipped because that simulator reports PiP unavailable. The new regression test confirms unchanged PiP heartbeats do not invalidate player chrome, while actual capability transitions still update it.

UI coverage totals **48 passed and one capability skip** across the [full 49-case build 38 baseline](https://github.com/Joshua131313/Streamify/actions/runs/40082132630) and build 40's nine affected-player cases. This is not a claim that all 49 cases were rerun in build 40. All 14 screen flows and all three profile flows passed, with screenshots reviewed; only three sports player source files changed after that full baseline. The final recheck includes all sports playback cases and multi-watch, with the original single-tap server and embedded-fullscreen assertions. Offline playback verified a real ten-second skip, a physical thumb seek to 389 seconds and reopening at 392 seconds, preserving pause, preview dismissal and lock behavior.

[Download the verified build 40 package](https://github.com/Joshua131313/Streamify/actions/runs/40085796275/artifacts/12556937249). The ZIP contains an unsigned IPA for local signing, version 1.1.2, build 40, iOS 17+, with the matching WidgetKit extension. SHA256: `0310f1680565480ee061a06a73848e0c44ec5833b16bdadfd7d884b17828219f`. On Windows, extract the IPA and sign/install it with iLoader using the same Apple Account as before. Keep the existing app installed to preserve its local data. The package and widget were checked directly; the test-only numeric seek setting is absent from the Release executable.

Build 40 portable validation passed for resources, property lists, 17 collections, 15 providers and 106 Swift source files. The local Firebase emulator contract passed five checks for guest access, message/reply schema, timestamps and denied reaction updates. The user chose local-only chat verification; no production guest-account/chat-read probe is authorized. Live-service chat remains unverified.

## Previous 1.0.0 validation

On October 23, 2026, the [macOS CI build](https://github.com/Joshua131313/Streamify/actions/runs/40000855365) passed **12 unit tests and one navigation UI test**, with zero failures, on an iPhone 17 Pro simulator. This includes real Keychain read/write/update/delete, saved/history persistence, catalog and sports fixtures, stream matching, download attempt identity, root titles, a single floating navigation bar, and saving settings. The five exported screenshots were visually reviewed; the duplicate system tab bar and unsigned-simulator Keychain error found in the first pass are fixed.

The ARM64 iPhone Release build also passed. That run's IPA was **version 1.0.0, build 3, iOS 17+**, bundle ID `com.streamify.app`. [Download the previous CI device package](https://github.com/Joshua131313/Streamify/actions/runs/40000855365/artifacts/12522751198) or [its simulator screenshots](https://github.com/Joshua131313/Streamify/actions/runs/40000855365/artifacts/12522142051). The local `build/Streamify-unsigned.ipa` and its `.sha256` sidecar are replaced when a newer build is downloaded.

These results describe **1.0.0**, not the current 1.1.2 changes. Version 1.1.0 build 7 was subsequently installed on the iPhone through iLoader. End-to-end physical-device playback has not been verified, and no TestFlight upload has been performed. Portable Swift grammar, resource JSON, property lists, 17 collection images, 15 provider templates, and the opaque 1024px app icon also passed the previous validation.

## Home Screen widget and shortcuts

After installing the updated build, open Streamify once. Touch and hold an empty area of the iPhone Home Screen, choose **Edit → Add Widget**, search for **Streamify Live Games**, and add its small, medium, or large size. The small widget opens its displayed game; medium and large widgets provide individual **Watch** links. Streamify checks the game's current status and available sources when a link opens. With no live games or unavailable scores, the widget opens Sports instead.

The widget shows when scores were last updated. It requests a refresh about every ten minutes; iOS controls the actual schedule, so this is not a continuously updating scoreboard. After fifteen minutes without a new timeline, old scores are replaced by an update message. Open Sports for current scores and streams.

Touch and hold the Streamify app icon for **My Downloads**, **My Favorites**, or **Sports**. These shortcuts open the corresponding section directly, including when the app is closed.

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
| Collections | All 17 original franchises and artwork, search/genre filter, release-order collection media. Middle-earth includes the Hobbit films, Rings of Power, classic animated titles, and War of the Rohirrim. |
| My list / History | Local persistence, movie/show/anime identity separation, search/type filters, compact landscape resume cards with actual progress and remaining time, remove and resume last episode |
| Sports | NFL/NCAAF/NBA/WNBA/NHL/MLB, ESPN schedules (college football merges FBS and FCS), compact horizontal logo rail with Followed teams first and one selected scope. Live is the default, with direct Pregame and Final tabs. Full-width compact cards show verified possession and an offense-relative football field with green progress fill when supplied by the feed. Unknown possession stays hidden. Calendar legends select one league, future dates select Pregame and disable Live. Day swipes retain directional transitions. Channels, multi-watch, refresh, display options and populated-first league browsing remain in the overflow menu. Dedicated game/team search, local times, following, rosters and results are retained. |
| Game center | Live score refresh; aligned team-by-quarter/period/inning scoring table with pinned totals and horizontal overflow for long games; bold winning scores and a small chevron without a Winner badge, comparison tables, roster photos, latest play, stream discovery with errors/empty states |
| Sports channels / Multi-watch | Four providers, seven broadcaster links, in-view live-game picker, up to four stable stream tiles with nested stream selection, reload/expand/remove and one selected audible stream; other HTML media tiles are muted. App-owned sports playback keeps the selected game/server through background returns and requests native system Picture in Picture for supported providers; the system restore action returns to the same player. |
| Player | All 15 movie/TV provider templates, verified AniList-to-MAL anime matching and SUB/DUB options, native persistent exit/reload/provider/Safari/AirPlay controls, embed/direct modes, episode picker/next episode |
| Downloads | Download actions on movie details, selected TV episodes and the player; quality selection resolves an available direct video file using the Android source flow. Background transfers, byte progress, duplicate prevention, retry, cancel/delete, direct HTTPS MP4/M4V/MOV links, Files import and disk-cached poster cards. Full-canvas offline player with transport/seek, speed, embedded audio/captions, local subtitle import, resume, episode/next selection, Android-style cumulative skip animation, one-second hold-to-unlock ring and opening lock, edge brightness/volume swipes while controls are hidden, lock, fit/fill, AirPlay and supported-device PiP. Streaming-only/DRM sources produce an explanation; anime and live sports downloads are unavailable. |
| Appearance / Settings / Preferences | Dark/light/system including the adaptive floating bottom bar, Keychain catalog token, optional sports backend, default source, favorite genres and manual iOS release checks |
| Profiles / account | Cinematic launch chooser with dynamic portrait artwork, six original detailed avatars, up to five profiles, editing, selection haptics and confirmed deletion. The active avatar appears in the bottom bar. Each profile owns its appearance, provider, genres, teams and local library. Email account sign-in connects profile names/avatars and those preferences to the existing owner-only Firebase backend; guests and different accounts retain separate local stores. Favorites, history and searches remain on the device; downloads are shared device files. Catalog credentials and backend connection settings are never uploaded. |
| Guest game chat | Shared Android/web matchup rooms, bounded realtime messages, anonymous identity on first Send, replies and reaction controls with visible server errors. Uses the existing Firebase project and its current rules; it does not migrate local profiles/libraries into Firebase. |

Native app buttons use light selection haptics, with a slightly firmer light impact for primary actions. Feedback runs from successful button activation; cancelled touches, scrolling and disabled buttons do not generate it. The bottom bar keeps its existing single selection feedback. Provider-owned web controls and operating-system panels retain their own behavior.

Other differences: category discovery uses an adaptive grid. Offline playback uses custom controls over AVPlayer; iOS rotation, AirPlay, PiP and volume follow platform capabilities. Skip-intro requires timing metadata that is not currently provided. WKWebView providers supply their own video controls and may restrict autoplay/audio or prevent timestamp access. Actual HTML5/native video progress is recorded only when the player can report valid timestamps; opening a protected provider alone never fabricates progress. Native profile sync uses a separate account document; Android and web do not yet consume that profile schema. Native iOS transitions and sheets adapt to OS/accessibility settings. The update check does not sign or install IPAs. Provider availability and the new 1.1.2 interactions still need physical-iPhone validation.

Sports system PiP depends on the external provider and iOS video support. The existing playback view stays mounted while native PiP is active, and restoring PiP returns to the same selected stream. Unsupported provider PiP leaves the full player visible. The test suite includes WebKit-document identity checks across background/foreground returns and a separate real AVKit PiP flow that skips only when the system reports it unavailable. Full candidate results are recorded above. A synthetic 10-minute H264 resource exercises real offline play, pause, seeking and resume without downloading a video.

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
Streamify/Profiles     Account/profile identity, isolated preferences, backend sync and cinematic chooser
Streamify/Data         TMDB/AniList clients, models, Keychain and local persistence
Streamify/Resources    Original Android artwork/config, icon, launch and privacy manifest
StreamifyTests         Network fixture, persistence, identity and provider/parser tests
StreamifyUITests       Screen/interaction checks and attached screenshots
```

`python3 scripts/validate.py` validates prepared resources on any Python machine. Optional Swift grammar validation uses `python3 -m pip install --target .tools tree-sitter tree-sitter-swift` then `python3 scripts/validate.py --syntax`; it does not type-check SwiftUI. `prepare-assets.py` is only for recopying shared Android artwork; it preserves the separately composed iOS Home Screen icon. The icon edit prompt and tool are recorded in `artwork/AppIcon-edit.json`. All prepared assets are included with the source.

## Current iPhone refinements

Sports fullscreen uses the embedded provider’s own control and real WebKit element fullscreen for recognized JW players, retaining its HTML controls. Streamify adds no separate fullscreen button. The player closes by downward card dismissal; the horizontal-swipe exit is removed. Native-video providers and system PiP retain their supported paths.

In landscape, the sports video uses the entire canvas. Game/source selectors and utility controls overlay it through the options button instead of reserving top and bottom bars. Rotation retains the same provider document. Portrait retains its separate controls.

Recently fetched sports schedules are retained per league, local date, timezone and backend, including known-empty results. Warm league/tab changes reuse them immediately without requesting the schedule again. Thirty-second score polling and explicit refresh can update stale cards in place. Switching the selected filter never clears a cached result first.

Continue Watching and history try the poster if a backdrop fails, repair sparse catalog metadata, and preserve existing artwork when playback reports fewer fields. Artwork repair does not reset progress or change the last-watched time. Favorite genres use equal-width, equal-height cards in two columns, switching to one column at accessibility text sizes.

Google sign-in uses the official Google Sign-In SDK and the existing Firebase account. Explicit email/Google sign-in opens Home after loading the account’s last-used profile. Normal cold launches retain the profile chooser. Local injected auth/profile backends exercise success and cancellation without creating production users or sending test credentials.

Downloads group every catalog show into its own episode page, with season sections, cached artwork, progress rings and native swipe/context actions. Quality is an exact selection: an unavailable or incompatible 1080p file is never silently replaced with 480p. Retry resolves a fresh source; an expired catalog URL can renew automatically once, only if a different signed address is returned at the same quality. A refresh is not a second provider. No additional direct-file provider has been verified for FROM S1 E1.

The offline seek preview follows the native thumb horizontally and matches Android’s 208×117 fit-center frame, 6pt corners, black 2pt border, separate transparent 24pt timestamp row, and a preferred 100pt bottom inset, raised when necessary to keep the timestamp above the actual iOS thumb.

Firebase Core/Auth/Firestore 13.1.1 are linked only to the main app through the existing XcodeGen specification, with the required -ObjC linker flag. Firebase configuration is loaded before guest chat touches its SDKs; fixtures use an in-memory backend. A live-service guest-account probe requires separate approval and has not run. No production chat messages were sent during implementation.
