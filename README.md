# LifeOrganize

LifeOrganize is a local-first iOS SwiftUI app for maintaining a personal ledger through conversational input. It stores records in SwiftData, routes AI extraction and web-backed lookups through a private backend gateway, and exposes Timeline, Things, Carry Forward, local search, review, export, and developer diagnostics surfaces.

## Run Locally

Open `LifeOrganize.xcodeproj` in Xcode, select the shared `LifeOrganize` scheme, choose an iOS 17.0 or newer simulator, and run the app. The app can launch without the backend; entries are still saved locally if AI extraction is unavailable.

Build from the command line:

```sh
xcodebuild -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' build CODE_SIGNING_ALLOWED=NO
```

Run tests:

```sh
xcodebuild test -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

By default the app calls `https://life.dock108.dev`. Pass `-ai-service-base-url=http://127.0.0.1:8787` to use a local backend.

## Deployment

The iOS project has Debug and Release configurations, automatic signing, deployment target `17.0`, marketing version `0.1`, build number `1`, and bundle identifier `com.local.lifeorganize`.

The backend lives in `Backend/`, runs as a small FastAPI service with Postgres, and owns the shared OpenAI key. Keep provider credentials in backend secrets only.

## Docs

- [Current app state](docs/current-app-state.md)
- [Backend](docs/backend.md)
- [Screenshot baselines](docs/screenshot-baselines.md)
- [Product stabilization notes](docs/product-stabilization-notes.md)
