# roon-controller

A Roon extension that exposes a local REST API, enabling AI assistants (or any HTTP client) to search your library, control playback, and manage queues across all your zones.

Built to work with [Anthropic's Cowork](https://claude.ai) desktop tool — ask Claude to pick music for you and it just works.

---

## Architecture

```
AI Assistant / HTTP client (your Mac)
        │  HTTP → port 3001
        ▼
Docker container  (NAS / always-on server)
        │  Roon extension protocol (LAN)
        ▼
Roon Core
        │
        ▼
All your zones
```

---

## Prerequisites

- Roon running on your network
- Docker on an always-on machine (QNAP, Synology, Raspberry Pi, Linux server…)
- SSH access to that machine

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/andyrat33/roon-controller.git
cd roon-controller
```

### 2. Deploy

Copy to your NAS / server:

```bash
scp -r roon-controller admin@YOUR_NAS_IP:/share/Container/
ssh admin@YOUR_NAS_IP
cd /share/Container/roon-controller
docker compose up -d --build
```

> `network_mode: host` is required so Roon's SOOD discovery (UDP multicast) can find your Core on the LAN.

### 3. Authorise

Open Roon → **Settings → Extensions** → click **Enable** next to **Cowork Controller**.

### 4. Verify

```bash
curl http://YOUR_NAS_IP:3001/api/status | python3 -m json.tool
```

---

## REST API

### Playback

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/status` | Connection status + now playing in all zones |
| GET | `/api/zones` | List all playback zones |
| GET | `/api/search?q=<query>[&type=tracks\|albums\|artists]` | Search library |
| GET | `/api/browse[?item_key=<key>]` | Browse library hierarchy |
| POST | `/api/find-and-play` | Search + play a single track `{ zone_id, query, action?, artist? }` |
| POST | `/api/play-album` | Play an entire album natively `{ zone_id, query, action? }` |
| POST | `/api/playlist` | Queue multiple tracks in order `{ name, zone_id, mode?, tracks[] }` (see strict matching below) |
| POST | `/api/play` | Play an item by key `{ zone_id, item_key, action? }` |
| POST | `/api/transport` | Playback control `{ zone_id, action }` |
| POST | `/api/volume` | Set volume `{ zone_id, how, value }` |
| POST | `/api/shuffle` | Enable/disable shuffle `{ zone_id, shuffle }` |
| GET | `/api/queue/:zone_id` | View queue |
| GET | `/api/inspect?q=<query>` | Debug: show Roon's exact action names |

### Multi-room & zone control

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/mute` | Mute or unmute a zone `{ zone_id, mute }` |
| POST | `/api/mute/all` | Mute or unmute every zone `{ mute }` |
| POST | `/api/pause/all` | Pause all zones simultaneously |
| POST | `/api/standby` | Toggle standby on a zone's output `{ zone_id }` |
| POST | `/api/group` | Group zones for synchronised playback `{ zone_ids[] }` |
| POST | `/api/ungroup` | Ungroup zones `{ zone_ids[] }` |
| POST | `/api/transfer` | Move queue from one zone to another `{ from_zone_id, to_zone_id }` |

### Transport actions
`play` · `pause` · `stop` · `next` · `previous` · `toggle_play_pause`

### Play actions
`Play Now` (default) · `Queue` · `Add Next` · `Start Radio`

### Album vs track playback

Use `/api/play-album` for albums — it navigates Roon's full browse hierarchy and queues all tracks natively in the correct order. The `/api/find-and-play` endpoint is for single tracks only. The `/api/playlist` endpoint queues tracks by individual search queries, useful for custom playlists but not for playing a specific album (tracks may match wrong versions).

### Strict track matching for `/api/playlist` (this fork)

Give tracks as `{ "title": "...", "artist": "..." }` and `/api/playlist` only plays an exact match:

- the title must match (an exact full-title match is preferred; otherwise bracketed suffixes such as `(Remastered 2021)` are ignored),
- the artist must be one of the track's credited names (so "Johnny Cash" does not match "The Ghost of Johnny Cash"),
- karaoke, covers, tributes, live, acoustic, remix and similar versions are skipped unless the requested title asks for them.

A track with no qualifying result is reported as `"status": "not_found"` with its top candidates, and is **not** replaced by another result. Tracks given only as `{ "query": ... }` keep the original loose behaviour.

`mode` controls the queue:

- `"play_now"` (default): the first track that matches replaces the queue and starts playing; the rest are queued after it.
- `"queue"`: every track is appended; nothing currently playing is interrupted.

```
{ "zone_id": "...", "mode": "queue",
  "tracks": [ { "title": "Fade Into You", "artist": "Mazzy Star" },
              { "title": "Hurt", "artist": "Johnny Cash" } ] }
```

### Avoiding cover versions

`/api/find-and-play` and `/api/playlist` accept an optional `artist` field. When provided, the API matches it against Roon's artist field to filter out cover recordings — useful when Roon's search ranks an orchestral cover or live version above the original:

```json
{ "zone_id": "...", "query": "The Sound of Silence Simon and Garfunkel", "type": "Tracks", "artist": "Simon & Garfunkel", "action": "Play Now" }
```

Falls back to Roon's top result if no match is found, so it's always safe to include.

---

## Python Helper

`roon_control.py` is a command-line wrapper for the API, useful for scripting or AI tool use.

Set your NAS IP:

```bash
export ROON_HOST=192.168.1.50
```

Examples:

```bash
python3 roon_control.py status
python3 roon_control.py zones
python3 roon_control.py search "Miles Davis" --type albums
python3 roon_control.py transport ZONE_ID next
python3 roon_control.py volume ZONE_ID 40 --how absolute
python3 roon_control.py mute ZONE_ID true
python3 roon_control.py pause-all
python3 roon_control.py group ZONE_ID_1 ZONE_ID_2
python3 roon_control.py transfer FROM_ZONE_ID TO_ZONE_ID
```

---

## Notes

- The RoonLabs API packages are not on npm — they're installed directly from [github.com/RoonLabs](https://github.com/RoonLabs). The Dockerfile installs `git` first for this reason.
- The extension uses `node-roon-api-browse` sessions internally; the REST API is stateless from the caller's perspective.
- Roon authorisation is persisted in a Docker volume (`roon_auth`) so you only need to authorise once.

### Known API limitations

- **Queue clearing is not supported.** The Roon Extension API does not expose queue management to third-party extensions. `hierarchy:'browse'` root has no Queue item, and `hierarchy:'queue'` returns `InvalidHierarchy`. The only way to replace the queue is to use `Play Now` on any track or album, which atomically clears and replaces it.
- **Playlist management is not supported.** There is no "Add to Playlist" or "Create Playlist" action available to extensions. Workaround: queue tracks via the API, then in the Roon app go **Queue → ⋮ → Save Queue as Playlist**.
- **Profile switching is not supported.** Profiles are per-Roon-Remote (phone/tablet app) and cannot be changed by an extension.

---

## Related

- [Medium article: Controlling Roon with AI](https://medium.com/@andyrat33)
- [RoonLabs Node API](https://github.com/RoonLabs/node-roon-api)
- [Roon Community](https://community.roonlabs.com)

---

## Licence

MIT
