# Screenshot Baselines

Deterministic screenshot comparison is driven by `Scripts/screenshots/run-screenshot-tests.sh`.

Run the visual regression path from the repository root:

```sh
Scripts/screenshots/run-screenshot-tests.sh compare
```

The script runs selected screenshot methods on `LifeOrganizeUITests/LifeOrganizeScenarioUITests`, writes the result bundle to `BuildArtifacts/ScreenshotTests.xcresult`, extracts `screenshot__*` PNG attachments into `BuildArtifacts/screenshots/actual/<device>/<appearance>/`, and compares them with the baseline PNGs under `Tests/ScreenshotBaselines/<device>/<appearance>/`.

Baselines are grouped by simulator and appearance. The current default baseline directory is:

```text
Tests/ScreenshotBaselines/iPhone_16/light/
```

Generated actual and diff artifacts stay under `BuildArtifacts/`, which is ignored by `.gitignore`. To intentionally accept a visual change, run:

```sh
Scripts/screenshots/run-screenshot-tests.sh update
```

The default comparison thresholds are:

- pixel channel delta threshold: `1.0`
- maximum changed pixels: `250`
- maximum changed pixel ratio: `0.00025`
- maximum mean channel delta: `0.35`

The stricter changed-pixel limit applies between the absolute and ratio limits. Failed comparisons write red-overlay diff PNGs under `BuildArtifacts/screenshots/diff/`.

`fastlane screenshots` runs the compare command. `fastlane update_screenshots` refreshes baselines after an intentional visual change.

## CI Artifacts

The iOS CI screenshot job runs the same compare command with the default `iPhone 16`, `iOS 18.6`, and light-appearance baseline path. Main pushes run the job unconditionally; pull requests run it when iOS rendering code, assets, localization, UI tests, screenshot scripts, baselines, Fastlane screenshot lanes, or screenshot documentation changes.

On failure, CI uploads `BuildArtifacts/ScreenshotTests.xcresult`, actual PNGs, diff PNGs when present, and `BuildArtifacts/screenshots/compare.log`. Baselines are not refreshed by CI. Intentional visual changes still require a local `Scripts/screenshots/run-screenshot-tests.sh update` run and a commit of the changed PNGs under `Tests/ScreenshotBaselines/`.
