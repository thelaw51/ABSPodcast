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

- Ask the server for its version first. ABS changed its login and token handling across releases, and the client has to match the server it talks to.
- Server URL entry with validation, then username and password login.
- Store the token in the Keychain and the server URL in `UserDefaults`. Sign out clears both.
- List the user's libraries and keep only the podcast ones.
- Open question: if Cloudflare Access protects the ABS hostname, API calls will get a Cloudflare login page instead of JSON. Check before building the login screen.

### Phase 2: browse

- Podcast grid with cover art for the selected library, with image caching.
- Episode list per podcast: title, publish date, duration, and played or in-progress state from the user's ABS progress.
- Pull to refresh.

### Phase 3: playback

- Stream episodes with `AVPlayer`, using the ABS auth token on media requests.
- Background audio: `UIBackgroundModes` contains `audio`, and the app sets the `.playback` audio session category.
- Lock screen and Control Center controls through `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
- Mini player above the tab bar and a full-screen player. Skip back and forward, playback speed, scrubbing.
- Handle interruptions (calls, Siri) and route changes (headphones unplugged pauses playback).

### Phase 4: progress sync

- Open an ABS playback session when an episode starts, sync the position while it plays, and close the session when it stops.
- Resume from the server position, so the app, the web client and other ABS apps agree.
- Mark episodes finished near the end.
- Queue syncs that fail while offline and retry them later.

### Later

Downloads for offline listening, sleep timer, an up-next queue, CarPlay (needs an entitlement request to Apple), and widgets.

## Working agreement

- Branches use plain CamelCase names with no prefix, for example `ServerSignIn`.
- Every change goes through a PR into `main`.
- Server addresses, tokens and team IDs never go in the repo.
