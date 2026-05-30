# Screenshot Baselines

Deterministic screenshot comparison is driven by `Scripts/screenshots/run-screenshot-tests.sh`.

Run the visual regression path from the repository root:

```sh
Scripts/screenshots/run-screenshot-tests.sh compare
```

The script runs selected screenshot methods on `LifeOrganizeUITests/LifeOrganizeScenarioUITests`, writes a target-specific result bundle under `BuildArtifacts/`, extracts `screenshot__*` PNG attachments into `BuildArtifacts/screenshots/actual/<target-key>/<orientation>/<appearance>/`, and compares them with the baseline PNGs under `Tests/ScreenshotBaselines/<target-key>/<orientation>/<appearance>/`.

The current runner captures these PNG names: `first_launch`, `timeline_empty`, `timeline`, `things`, `thing_detail`, `carry_forward`, `search`, `review_queue`, `settings`, and `heavy_timeline`.

Baselines are grouped by target key, orientation, and appearance:

```text
Tests/ScreenshotBaselines/<target-key>/<orientation>/<appearance>/
```

Generated actual and diff artifacts mirror the same matrix under `BuildArtifacts/screenshots/actual/` and `BuildArtifacts/screenshots/diff/`. Result bundles include the same target key, orientation, and appearance by default, for example `BuildArtifacts/ScreenshotTests-iPhone_17_Pro-portrait-light.xcresult`.

The maintained light-appearance matrix is:

| Target key | Device | Orientation | Baseline path |
| --- | --- | --- | --- |
| `iPhone_17_Pro` | `iPhone 17 Pro`, iOS `26.2` | `portrait` | `Tests/ScreenshotBaselines/iPhone_17_Pro/portrait/light/` |
| `iPhone_17_Pro` | `iPhone 17 Pro`, iOS `26.2` | `landscape` | `Tests/ScreenshotBaselines/iPhone_17_Pro/landscape/light/` |
| `iPad_Pro_13-inch_M5` | `iPad Pro 13-inch (M5)`, iOS `26.2` | `portrait` | `Tests/ScreenshotBaselines/iPad_Pro_13-inch_M5/portrait/light/` |
| `iPad_Pro_13-inch_M5` | `iPad Pro 13-inch (M5)`, iOS `26.2` | `landscape` | `Tests/ScreenshotBaselines/iPad_Pro_13-inch_M5/landscape/light/` |

The static iOS layout guard checks that each maintained light-appearance matrix cell contains the guard-required scenario set: `first_launch`, `timeline_empty`, `timeline`, `things`, `thing_detail`, `carry_forward`, `search`, `review_queue`, and `heavy_timeline`. The screenshot comparator also fails on unexpected actual PNGs, so `settings.png` is maintained in the current baseline directories even though `Scripts/ios_static_layout_guard.py` does not list it in `REQUIRED_SCREENSHOT_SCENARIOS`.

Generated actual and diff artifacts stay under `BuildArtifacts/`, which is ignored by `.gitignore`. Baselines are resolved only from the target, orientation, and appearance path shown above. To intentionally accept a visual change, run:

```sh
Scripts/screenshots/run-screenshot-tests.sh update
```

The default command compares the iPhone portrait light target. To run explicit matrix cells:

```sh
SCREENSHOT_TARGET_KEY=iPhone_17_Pro \
SCREENSHOT_DEVICE_NAME="iPhone 17 Pro" \
SCREENSHOT_DEVICE_OS=26.2 \
SCREENSHOT_ORIENTATION=portrait \
SCREENSHOT_APPEARANCE=light \
Scripts/screenshots/run-screenshot-tests.sh compare
```

```sh
SCREENSHOT_TARGET_KEY=iPhone_17_Pro \
SCREENSHOT_DEVICE_NAME="iPhone 17 Pro" \
SCREENSHOT_DEVICE_OS=26.2 \
SCREENSHOT_ORIENTATION=landscape \
SCREENSHOT_APPEARANCE=light \
Scripts/screenshots/run-screenshot-tests.sh compare
```

```sh
SCREENSHOT_TARGET_KEY=iPad_Pro_13-inch_M5 \
SCREENSHOT_DEVICE_NAME="iPad Pro 13-inch (M5)" \
SCREENSHOT_DEVICE_OS=26.2 \
SCREENSHOT_ORIENTATION=portrait \
SCREENSHOT_APPEARANCE=light \
Scripts/screenshots/run-screenshot-tests.sh compare
```

```sh
SCREENSHOT_TARGET_KEY=iPad_Pro_13-inch_M5 \
SCREENSHOT_DEVICE_NAME="iPad Pro 13-inch (M5)" \
SCREENSHOT_DEVICE_OS=26.2 \
SCREENSHOT_ORIENTATION=landscape \
SCREENSHOT_APPEARANCE=light \
Scripts/screenshots/run-screenshot-tests.sh compare
```

Replace `compare` with `update` in the same commands to refresh that one baseline cell.

The default comparison thresholds are:

- pixel channel delta threshold: `10.0`
- maximum changed pixels: `250`
- maximum changed pixel ratio: `0.15`
- maximum mean channel delta: `3.0`

The changed-pixel limit allows the larger of the absolute and ratio limits. Failed comparisons write red-overlay diff PNGs under `BuildArtifacts/screenshots/diff/`.

`fastlane screenshots` runs the compare command. `fastlane update_screenshots` refreshes baselines after an intentional visual change.

## Adaptive Screen Validation

Run the local adaptive screen matrix from the repository root:

```sh
Scripts/run-adaptive-screen-validation.sh compare
```

The command runs the maintained iPhone 17 Pro portrait and landscape screenshot comparisons, iPad Pro portrait and landscape screenshot comparisons, normal, Large, Accessibility Large, and Accessibility XXXL Dynamic Type smoke coverage, compact and regular adaptive shell UI checks, and a smaller iPad portrait adaptive shell smoke when a configured smaller iPad simulator exists locally. It writes result bundles and screenshot artifacts under `BuildArtifacts/AdaptiveScreenValidation` and `BuildArtifacts/screenshots/`.

The command reports that Stage Manager or narrow iPad window sizing is not covered because CoreSimulator command-line tooling does not reliably create that window class for XCTest. Use `update` instead of `compare` only when intentionally refreshing the screenshot baseline cells owned by the matrix.

## CI Artifacts

The required iOS CI screenshot job runs the iPhone portrait light target. Main pushes run the job unconditionally; pull requests run it when iOS rendering code, assets, localization, UI tests, screenshot scripts, baselines, Fastlane screenshot lanes, or screenshot documentation changes. Manual workflow dispatch can run the iPad portrait light target with `screenshot_profile=ipad_portrait` or both CI light targets, iPhone portrait and iPad portrait, with `screenshot_profile=all_light`.

On failure, CI uploads the target-specific `BuildArtifacts/ScreenshotTests-*.xcresult`, actual PNGs, diff PNGs when present, and `BuildArtifacts/screenshots/compare.log`. Baselines are not refreshed by CI. Intentional visual changes still require a local `Scripts/screenshots/run-screenshot-tests.sh update` run and a commit of the changed PNGs under `Tests/ScreenshotBaselines/`.
