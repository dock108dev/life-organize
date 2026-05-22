# Screenshot Baselines

Deterministic screenshot comparison is driven by `Scripts/screenshots/run-screenshot-tests.sh`.

Run the visual regression path from the repository root:

```sh
Scripts/screenshots/run-screenshot-tests.sh compare
```

The script runs `LifeOrganizeUITests/LifeOrganizeScreenshotTests`, writes the result bundle to `BuildArtifacts/ScreenshotTests.xcresult`, extracts `screenshot__*` PNG attachments into `BuildArtifacts/screenshots/actual/`, and compares them with the baseline PNGs under `Tests/ScreenshotBaselines/`.

Baselines are grouped by simulator and appearance. The current default baseline directory is:

```text
Tests/ScreenshotBaselines/iPhone_16/light/
```

Generated actual and diff artifacts stay under `BuildArtifacts/`, which is ignored by `.gitignore` and excluded by `.swiftlint.yml`. To intentionally accept a visual change, run:

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
