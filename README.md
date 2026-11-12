# impeller_gles_memory

An experiment on graphics memory under **Impeller on OpenGL ES** on a PowerVR GPU (Samsung Galaxy A04, PowerVR Rogue GE8320), compared with Skia. Everything needed to check it is here: the app, the measuring script, the raw data, the analysis and a lab notebook.

**Status (2026-11-12):** on this device, the driver's `Graphics` / `GL mtrack` counter grows linearly with both renderers, 4–6× faster with Impeller. The device's free memory does not follow it. So far the counter growth does not show a real leak. See [Results](#results).

## Question

A production app showed `Graphics` memory growing with Impeller and not with Skia on this phone. Is this a real memory leak in Impeller's GLES backend?

| Hypothesis | Prediction | Verdict so far |
|---|---|---|
| **H1:** Impeller on GLES leaks GPU memory. | The counter grows, and the device's `MemAvailable` falls with it until the app is killed. | Not supported: `MemAvailable` stays flat. |
| **H2:** the counter reflects driver accounting, not resident memory. | The counter grows without bound, past physical RAM, while `MemAvailable` stays flat. | Supported. |

## Setup

| | |
|---|---|
| Device | Samsung Galaxy A04 (SM-A045M), Android 14, 3.7 GB RAM |
| GPU | PowerVR Rogue GE8320, OpenGL ES 3.2, driver build 1.13@5776728. Impeller falls back from Vulkan to GLES. |
| Flutter | 3.41.8 stable, `--profile` |
| Renderers | Impeller (default) and Skia (`--no-enable-impeller`) |
| Conditions | USB, screen on, nothing else in the foreground |

## Method

1. **The app** ([`lib/main.dart`](lib/main.dart)) runs 30 rounds by itself. Each round does this three times:
   - push a list of 24 cards (rounded corners, shadow, `Clip.antiAlias`, an 800×600 PNG generated on the device);
   - scroll to the end and back, twice;
   - pop.

   After each round it prints `IMPELLER_REPRO round=N` and waits 4 s.
2. **The measuring script** ([`tool/measure.ps1`](tool/measure.ps1)) runs the app and records one CSV row per round. Each row comes from `dumpsys meminfo <package>`, plus `MemAvailable` from `/proc/meminfo`.
3. **The analysis** ([`tool/analyze.dart`](tool/analyze.dart)) works on the `Graphics` counter in three steps:
   - **It undoes the wraparound.** The counter reads 0 between 2 and 4 GiB and starts over after 4 GiB, like a signed 32-bit byte count. The script rebuilds the cumulative value from that.
   - **It fits a line** to the cumulative value against the round number.
   - **It tests the wraparound assumption:** every reading of 0 must fall where the fitted line predicts the 2–4 GiB band.

Scenarios (`--dart-define=SCENARIO=...`):
- `images` is the default, with the same images every round.
- `fresh` decodes new images every round.
- `no_images` (flat colors instead of images) and `stack` (screens are never popped) are not measured yet.

## Results

Output of `dart run tool/analyze.dart results/*.csv`, 30 rounds each:

| Run | Renderer, scenario | Growth of `Graphics` (MB/round) | R² | Value at round 30 (reconstructed) | Zeros explained by the wrap | `MemAvailable`, round 0 → 30 (MB) | `MemAvailable` trend (MB/round) | Native heap (MB) |
|---|---|---|---|---|---|---|---|---|
| [20261111-225455](results/20261111-225455-impeller-images.csv) | Impeller, `images` | 397 | 0.994 | 12.6 GB | 14/15 | not recorded | — | 29–39 |
| [20261111-232906](results/20261111-232906-skia-images.csv) | Skia, `images` | 91 | 0.998 | ~2.8 GB (reads 0) | 9/10 | 1658 → 1593 | +0.7 | 33–51 |
| [20261112-081612](results/20261112-081612-impeller-images.csv) | Impeller, `images` | 590 | 1.000 | 17.5 GB | 12/14 | 1745 → 1637 | −0.8 | 26–39 |
| [20261112-090653](results/20261112-090653-impeller-fresh.csv) | Impeller, `fresh` | 569 | 1.000 | 16.6 GB | 14/14 | 1684 → 1592 | −3.0 | 27–42 |

Findings:
1. **Both renderers grow the counter linearly** (R² ≥ 0.99). Impeller grows it 4–6× faster than Skia.
2. **The counter goes far past physical RAM:** 17.5 GB on a 3.7 GB phone, and the app was never killed. Whatever the counter tracks is not resident memory.
   - In `images`, `MemAvailable` has no trend (under 1 MB per round).
   - In `fresh` it drifts −3 MB per round (~90 MB over the run). That is inside the run's noise, and 0.5 % of what the counter claims. It needs a per-process check.
3. **New images do not change the rate.** `fresh` (569 MB/round) grows like `images` (590). The growth does not come from decoding new images.
4. **The wraparound explains the zeros.** In 49 of 53 cases, the fitted line puts a zero reading in the 2–4 GiB band. The other 4 are rounds the line places 21–71 MB below the 2 GiB edge, which is within the fit's error.

## Limitations

- **One device, one driver, one Flutter version, two scenarios.** No Vulkan device has been measured as a control.
- **The two Impeller runs differ** (397 vs 590 MB/round). Run-to-run variance is not characterized yet.
- **Free memory was not recorded in the first Impeller run:** that column was added after it.
- **`MemAvailable` is device-wide and noisy:** it swings about 150–190 MB within a run.
  - It would hide a slow leak.
  - It would not hide one of hundreds of MB per round, which is what the counter claims.
- **Smoothness was not measured here.** The production app showed 22–47 % slow frames with Impeller against 2–5 % with Skia, but that is a separate question.

## Reproduce

Requirements: Flutter on `PATH`, `adb`, PowerShell 7, one Android device connected.

```powershell
./tool/measure.ps1 -Renderer impeller -Scenario images   # ~26 min
./tool/measure.ps1 -Renderer skia     -Scenario images
dart run tool/analyze.dart results/*.csv
```

To try another Flutter SDK, pass `-Flutter C:\path\to\flutter\bin\flutter.bat`.

## Data and notebook

- [`results/`](results/) has every run, unedited. Its [README](results/README.md) explains the columns.
- [`NOTEBOOK.md`](NOTEBOOK.md) logs each run in date order: the commit used, anything that went wrong, and what changed in the method.
- [`report/issue-draft.md`](report/issue-draft.md) is the draft of the upstream report.

## Next steps

- [x] Run the `fresh` scenario.
- [ ] Run the `no_images` and `stack` scenarios.
- [ ] Repeat the `images` scenario to measure run-to-run variance (397 vs 590 MB/round so far).
- [ ] Repeat on Flutter 3.50.0.
- [ ] Run a Vulkan device as a control.
- [ ] Check per-process resident memory (`/proc/<pid>/status` VmRSS) and `dumpsys gpu`, not only device-wide `MemAvailable`.
- [ ] Post upstream ([draft](report/issue-draft.md)).

## Related upstream issues

- flutter/flutter#178264: GL mtrack growing to ~4 GB on Adreno and Xclipse. It is open.
- flutter/flutter#195767: Impeller GLES raster about 2× slower than Skia on Mali-G31. It is open and P1.
- flutter/flutter#193009: GE8320 jank with Impeller. It was closed without a reproduction.

## License

MIT
