# Sports stream discovery

Sports players use the same public Streamed API discovered in LiveXTV's client bundle:

- `https://streamed.pk/api/matches/all` returns event titles, teams, categories, dates, and source IDs.
- `/stream/{source}/{id}` returns the available streams and their actual `embedUrl` values.

`useGameStreams` shares the match feed through React Query and resolves sources for the selected matchup. NBA/WNBA use basketball, NHL uses hockey, and MLB uses baseball. Matching requires both full team names, permits reversed team order and LA/St. Louis spelling variations, and excludes dated events farther than 18 hours from now. The nearest matching event wins. No URL is constructed from team slugs.

Both the full-screen sports player and the shared floating/multi-watch panel use this hook. Old provider query parameters select the first current stream if that provider is no longer available. Available sources remain selectable; one failing source does not discard successful sources. Queries refresh every minute and time out after 12 seconds. The players show a retry state when no stream is published or the service fails. Existing television channel streams are separate.

For local development, run `npm run dev:api` (sports API on port 3000) and `npm run dev` (frontend on port 5173) in separate terminals. Set `VITE_API_URL=http://localhost:3000` in `.env.local`. The local API runner uses the existing production handlers and needs no Vercel login.

Run matching regression tests with `node --test tests/streamMatch.test.mjs`, and validate the app with `npm run build`.

This provider does not guarantee coverage for every ESPN event. Playback still depends on the third-party stream being online, its embed permissions, and regional availability. HTTP/API checks confirm discovery and page availability, not successful video playback.
