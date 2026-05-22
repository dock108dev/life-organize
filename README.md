# LifeOrganize

LifeOrganize is a local-first iOS SwiftUI app for maintaining a personal ledger through conversational input. It stores ledger records in SwiftData, optionally uses a small backend AI gateway for structured extraction and web-backed ledger lookups, and exposes Timeline, Things, and Carry Forward tabs with local review, editing, search, recall, JSON export, and developer diagnostics.

## Run Locally

Open `LifeOrganize.xcodeproj` in Xcode, select the shared `LifeOrganize` scheme, choose an iOS 17.0 or newer simulator, and run the app.

The same project can be built from the command line:

```sh
xcodebuild -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' build CODE_SIGNING_ALLOWED=NO
```

Use Xcode or omit `CODE_SIGNING_ALLOWED=NO` when installing and launching the app in Simulator. The app stores a per-device AI service token in Keychain; the shared OpenAI key belongs only on the backend.

Run the test suite with:

```sh
xcodebuild test -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

AI extraction is optional for launching the app. By default the app calls `https://life.dock108.dev`; pass `-ai-service-base-url=http://127.0.0.1:8787` for a local backend. If the service is unavailable, entries are still saved locally as raw chat messages.

## Deployment

The Xcode project defines Debug and Release configurations, a shared `LifeOrganize` scheme, automatic signing, iOS deployment target `17.0`, marketing version `0.1`, build number `1`, and app bundle identifier `com.local.lifeorganize`. The repository includes a small FastAPI backend under `Backend/`, plus Fastlane and shell helpers for deterministic screenshot comparison and baseline updates.

## Docs

- [Current app state](docs/current-app-state.md)
- [Backend](Backend/README.md)
- [Screenshot baselines](docs/screenshot-baselines.md)
- [Documentation consolidation audit](docs/audits/docs-consolidation.md)

Customer voice is preserved separately in [BRAINDUMP.md](BRAINDUMP.md).
