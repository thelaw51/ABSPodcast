# ABSPodcastApp

An iOS client for listening to the podcast libraries on an [Audiobookshelf](https://www.audiobookshelf.org) server.

The app is in early development. [docs/PLAN.md](docs/PLAN.md) has the phases and the decisions behind them.

## Requirements

- Xcode 26 or later
- iOS 18 or later on the device
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint)

```bash
brew install xcodegen swiftlint
```

## Getting started

The Xcode project is generated from `project.yml` and isn't committed. Generate it after cloning, and again whenever you add or remove files or pull changes that do.

```bash
xcodegen generate
open ABSPodcastApp.xcodeproj
```

The simulator needs no further setup. To install on a phone, copy the local config and set your team ID:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Git ignores `Config/Local.xcconfig`. With a free Apple ID the install expires after 7 days, and you reinstall from Xcode.

## Running tests

```bash
xcodebuild test -project ABSPodcastApp.xcodeproj -scheme ABSPodcastApp -destination 'platform=iOS Simulator,name=iPhone 17'
```
