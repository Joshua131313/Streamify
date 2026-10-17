# Anime

Anime browsing uses the public AniList GraphQL catalog. AniList IDs are stored as
`anime:<id>`; they must never be used as TMDB movie or TV identifiers. Each AniList
entry has its own episode numbering. Separate seasons are separate catalog entries.

Watch opens the saved anime source immediately. Watch sub and Watch dub open source
menus; choosing a source saves that source/audio pair and opens the player. The
player source sheet also allows changing between these choices. Defaults, saved
anime, and anime watch history are scoped to the local signed-in account or guest.
Anime is intentionally not written into the web app's existing TMDB-only cloud
collections. Supporting cross-device anime sync needs a shared AniList-aware schema.

Playback now resolves through Anikoto's public watch-page endpoints rather than
constructing AniList embed URLs. Search candidates are verified against each
release's MAL ID; ambiguous or missing mappings fail explicitly. Episode tokens
are refreshed from `/ajax/episode/list/{id}`, language-specific servers from
`/ajax/server/list`, and actual player URLs from `/ajax/server`. Sub never silently
falls back to Dub, or vice versa. Native source choices are HD-1, Vidstream-2, and
Vidstream-1 in each audio mode. Existing preferences migrate to Anikoto HD-1 while
preserving Sub/Dub.

Resolution has a 45-second overall timeout, plus bounded individual requests.
The player shows recovery controls if playback does not start. Availability still
depends on Anikoto's upstream servers. Resume tracking uses the existing exact-origin
video bridge; cross-origin nested players may not expose progress.

## Sports diagnosis, October 16, 2026

The Streamed API returned `embed.st` URLs for multiple live games. The system DNS
resolver returned a server failure for that hostname before any player JavaScript
or PiP functionality could run. No DNS or TLS validation bypass was introduced.
The player now distinguishes DNS, connection, timeout, and TLS failures. PiP entry
and play/pause passed the controlled emulator playback test. This does not establish
the cause of every failure on a separate phone/network.
