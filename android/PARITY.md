# Web-to-Android parity audit

Compared against the current working-tree web code, including its uncommitted Collections and Sports changes. The web files were not changed by this Android pass.

| Web surface | Android implementation | Status / differences |
| --- | --- | --- |
| Home / HeroCarousel | Automatic/swipeable portrait hero, animated indicators, pause/resume, direct Play show/movie, details and save actions | Native layout; pauses offscreen/background and respects touch exploration/reduced motion |
| Continue watching / history | Home rail and Library history with episode resume | Account sync when signed in; separate guest storage. Opening a source is recorded, not successful playback |
| TOP 10, Trending Today, Top rated | TMDB catalog rails | Implemented |
| For you | Favorite genres and history genres, filtered for movie/TV; trending fallback | Same three-genre selection approach as the web |
| Only on / genre rails | Compact movie/TV and provider/genre menus beside section headings on one row | Implemented; provider discovery uses US catalog region |
| Collections rail, `/collections`, `/collections/:id` | All 17 web collections, exact bundled art, featured rail at the bottom of Home, search, genre filter, release-order movies | Implemented |
| Discover and Search | Movie/TV browse, genre/provider filtering, mixed search, recent searches, pagination | Native combined Browse tab |
| Movie / TV details | Synopsis, rating, genres, trailer, saved state, cast, recommendations, seasons/episodes | Implemented |
| `/person/:id` | Biography, birthday, birthplace, known-for credits | Implemented; reached from cast |
| Movie / TV player | Same 15 source templates, native close/retry, embed/direct modes, fullscreen, browser fallback, episode picker and next episode | Source availability remains external |
| Saved media / History | Searchable library, type filtering, remove/save, last episode | Synced with the web account; latest 200 history entries on mobile |
| Sports home | League directory with official logos, current schedule previews, shortcuts | Implemented with mobile cards |
| NFL / NBA / WNBA / NHL / MLB | Image buttons, league schedule, all-league view | Implemented |
| Sports filters / calendar | Live, upcoming within two hours, final, followed teams, local dates, two-week day picker | Calendar selects a day rather than displaying the web's full desktop calendar grid |
| Sports layouts | List and horizontal slider | Desktop grid adapted to mobile list |
| Sports search | Teams, league names, sport names; team profiles | Implemented; team directory loads from ESPN |
| Team pages | Schedule, results, roster, team follow | Implemented; ESPN fields can differ from the web's league-specific feeds |
| Gamecast | Overview, scoring, team comparison, latest play, watch sources, refresh | Implemented; explicit empty/error states when feed fields are absent |
| Sports stream sources | Same current streamed.pk matching and source lookup | Legacy static stream definitions are not used by the current web hook |
| Sports channels | Four configurable providers plus seven broadcaster links | Implemented |
| Multi-watch | Queue up to four game sources, remove/reload/open each tile | Native tiles; no desktop draggable windows |
| Appearance | Dark, light, system | Implemented |
| Sign-in | Native Google Credential Manager + Firebase Auth, persistent session, sign-out | Google only, as requested. Email/password and Facebook are intentionally excluded from Android |
| Cloud saved media/history/followed teams/searches | Real-time listeners on existing user subcollections, compatible writes and removals | Account-scoped caches, queued offline changes, explicit sync/error status; guest data stays separate |
| Account onboarding and favorite genres | Genres and followed teams, skip/complete flow, editable preferences | Existing onboarding state is preserved when signing in again |
| Sports live chat | Game-center tab and player chat panel, latest 100 messages, shared web room and message format | Sign-in required; integration tests use local demo data only |
| AI search | No Android entry point | Web `useAISearch` hook is not used by the current Search route either |

## Firebase integration

After explicit approval, registered `com.streamify.app` in the existing project `debugging-98550`. Android app ID: `1:794133279425:android:2acb0801dfc31725f89a40`. The app uses the existing `(default)` Standard Firestore database. The debug SHA-1 and SHA-256 fingerprints were registered and `app/google-services.json` was retrieved and refreshed through Firebase CLI; it contains the Android and web OAuth client IDs.

Production user documents, chat messages, auth providers, and security rules were not modified during development. Google is the only Android sign-in option by user request. First sign-in creates a profile only if it is missing; it does not reset existing preferences or onboarding.

The shared web contracts are `users/{uid}`, `savedMedia` (`mediaId`, `mediaType`), `watchHistory` (`mediaType-mediaId`, `genreIds`, `season`, `episode`, `updatedAt`), `favoriteTeams` (`league`, `abbrev`, `name`), `searchHistory` (`searchValue`, `timeStamp`), and `live-chats/{awayAbbrev-homeAbbrev}/messages`. Android supports the web's generated saved/team document IDs, removes duplicate references together, and keeps movie/TV identities distinct.

Tests use a named `demo-streamify-android` FirebaseApp with local Auth/Firestore emulators and mock Google credentials. This validates SDK sign-in/session behavior and data compatibility, not a real Google account consent flow. Live Google sign-in must still be completed on a device with the user's Google account. Distribution signing certificates must be registered separately.

## Playback regression checks

- Instrumented tests exercise a failed source's native exit/reload controls, fullscreen Back/close handling, sports chat dismissal with Back, and non-zero iframe height after first native layout.
- Unit tests cover provider URLs, iframe URL encoding, media identity, unsafe addresses, local timestamp parsing, sports source matching, and ESPN/backend variants.
- Debug WebView inspection established that the black player had a zero-height iframe even while video metadata was loaded. Explicit fill-parent native layout parameters fixed the viewport.
- Live playback checks and screenshots are kept under ignored `build/verification/`; a loaded provider page alone is not counted as successful playback.
