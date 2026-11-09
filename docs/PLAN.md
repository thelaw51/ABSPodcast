# Project plan

ABSPodcastApp is a personal iOS client for the podcast libraries on an Audiobookshelf (ABS) server. The official ABS app handles podcasts and audiobooks together. This one does podcasts only, and plays them the way a podcast app should.

## Decisions

| Area | Choice | Reason |
| --- | --- | --- |
| UI | SwiftUI, `@Observable` models | Current Apple default; no UIKit unless an API forces it. |
| Minimum iOS | 18.0 | Covers the owner's phone and one version back without availability checks for Observation. |
| Language | Swift 6, complete strict concurrency | Catches data races in the player and sync code at compile time. |
| Project file | XcodeGen (`project.yml`) | The generated `.xcodeproj` stays out of git, so parallel branches don't conflict in `project.pbxproj`. |
| Dependencies | None | `URLSession`, `AVFoundation` and the Keychain API cover v1. Adding a package needs a reason in its PR. |
| Lint | SwiftLint, run as a build phase | Warnings show inline in Xcode. |
| Tests | Swift Testing | Unit tests for networking, models and sync logic. |
| Server access | HTTPS through the owner's Cloudflare tunnel | No App Transport Security exceptions needed. |
| Signing | Free Apple ID, team ID in `Config/Local.xcconfig` | Installs expire after 7 days. Nothing account-specific is committed. |
| CI | None for now | macOS runner minutes on a private repo cost money. Each PR is built and tested locally. |

## Phases

Version 1 is phases 0 to 4. Each phase lands as one or more pull requests into `main`.

### Phase 0: scaffold

XcodeGen project, app and test targets, SwiftLint config, the local signing config pattern, and this plan. The app launches to a placeholder screen.

### Phase 1: connect and sign in

Built against ABS v2.37.1, which issues JWT sessions: a 1-hour access token and a 30-day refresh token that rotates on every refresh.

- Check `GET /status` first, to confirm the address is ABS and that password sign-in is enabled.
- Server URL entry with validation (https only, sub-paths allowed), then `POST /login` with `x-return-tokens: true` so the refresh token comes back in the body.
- Store both tokens in the Keychain and the account in `UserDefaults`. Sign out revokes this device's session on the server and clears both.
- Refresh on a 401, with one shared refresh for concurrent requests, since a rotated refresh token can't be spent twice.
- List the user's libraries and keep only the podcast ones.

### Phase 2: browse

- Podcast grid with cover art for the selected library, with image caching.
- Episode list per podcast: title, publish date, duration, and played or in-progress state from the user's ABS progress.
- Pull to refresh.

### Phase 3: playback

Streams each episode's `audioTrack.contentUrl` (`/api/items/{id}/file/{ino}`) directly. Phase 3 writes nothing to the server: the position lives in memory, so it doesn't reach the web app or survive the app being closed. Phase 4 adds that.

- `AVPlayer` sends the bearer token in a request header, not the URL.
- Access tokens last an hour, and ABS rejects expired ones. The player asks for a token with at least ten minutes left when it loads or resumes, and if a request still fails mid-episode, it refreshes once and reloads at the last position that played.
- Background audio: `UIBackgroundModes` contains `audio` (merged in from `Config/Info.plist`), and the session uses `.playback` with `.spokenAudio`.
- Lock screen and Control Center: title, podcast, artwork, scrubbing, skip back 15 and forward 30.
- Mini player above the content and a full-screen player with scrubber, speed (0.8× to 2×) and AirPlay.
- Calls and Siri pause and resume; unplugging headphones pauses.

### Phase 4: progress sync

`PlaybackCoordinator` starts every episode through an ABS playback session (`POST /api/items/{id}/play/{episodeId}`), so the app, the web client and other ABS apps agree on where you are.

- The session says where to resume and which file to stream. If it can't be opened, the episode plays from its file at the last known position and progress is written directly.
- The app reports the position and listening time every 15 seconds of listening, on pause, two seconds after the last seek, and at the end. ABS marks an episode finished when less than 10 seconds remain, or past the library's own threshold.
- Listening time is wall-clock time spent playing, like the ABS web player, so 2× speed and skips don't inflate the stats.
- Starting another episode closes the previous session with its final position. Sign-out does the same before it revokes the tokens, giving up after four seconds if the server can't be reached.
- Each position is saved on the phone before it is sent and dropped once ABS accepts it. Positions that didn't get through are sent when the app launches or returns to the foreground, unless the server already has newer listening for that episode. The queue is kept per server and user.
- ABS keeps open sessions in memory, so after a server restart a sync gets a 404. The app then writes progress directly for the rest of that episode.
- A random device ID stored on the phone means ABS replaces this device's previous session rather than leaving it open.
- Listening time that couldn't be sent through a session is dropped. Only the position is retried, because ABS has no way to add listening time without a session.

### Later

Downloads for offline listening, sleep timer, an up-next queue, CarPlay (needs an entitlement request to Apple), and widgets.

## Working agreement

- Branches use plain CamelCase names with no prefix, for example `ServerSignIn`.
- Every change goes through a PR into `main`.
- Server addresses, tokens and team IDs never go in the repo.
