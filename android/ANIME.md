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

Provider route references:

- https://vidhawk.buzz/ — `/embed/ani/{anilistId}/{episode}/{sub|dub}`
- https://vidnest.streamy.org.uk/ — `/anime/{anilistId}/{episode}/{sub|dub}`

Catalog episode counts are not proof that a provider has a particular Sub/Dub
release. Playback availability remains provider-dependent. Upcoming titles have
no episode list; the next scheduled episode is excluded from airing titles.
Resume tracking uses the existing origin-scoped video bridge when a provider
exposes a video in that origin; cross-origin inner players may not expose progress.

## Sports diagnosis, October 16, 2026

The Streamed API returned `embed.st` URLs for multiple live games. The system DNS
resolver returned a server failure for that hostname before any player JavaScript
or PiP functionality could run. No DNS or TLS validation bypass was introduced.
The player now distinguishes DNS, connection, timeout, and TLS failures. PiP entry
and play/pause passed the controlled emulator playback test. This does not establish
the cause of every failure on a separate phone/network.
