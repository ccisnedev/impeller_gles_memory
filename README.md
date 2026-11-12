# impeller_gles_memory

An experiment on graphics memory under **Impeller on OpenGL ES** on a PowerVR GPU (Samsung Galaxy A04, PowerVR Rogue GE8320), compared with Skia. Everything needed to check it is here: the app, the measuring script, the raw data, the analysis and a lab notebook.

**Status (2026-11-12):** on this device, the driver's `Graphics` / `GL mtrack` counter is not a usable leak signal.
- **It grows** at a steady ~14 MB per second of rendering with Impeller on Flutter 3.50.0, and ~2 MB/s with Skia.
- **It wraps around** past 2 GiB, and reaches 21 GB on a 3.7 GB phone.
- **The app's own memory stays at ~180 MB,** and the device's free memory does not move. Only when screens are never popped does real memory fall, and it falls the same with Skia.

See [Results](#results).

## Question

A production app showed `Graphics` memory growing with Impeller and not with Skia on this phone. Is this a real memory leak in Impeller's GLES backend?

| Hypothesis | Prediction | Verdict |
|---|---|---|
| **H1:** Impeller on GLES leaks GPU memory. | The counter grows, and real memory (`MemAvailable`, the app's RSS) falls with it until the app is killed. | Not supported. Real memory is flat, and where it does fall (`stack`), Skia falls the same. |
| **H2:** the counter reflects driver accounting, not resident memory. | The counter grows without bound, past physical RAM, while real memory stays flat. | Supported on 3.41.8 and 3.50.0. |

## Setup

| | |
|---|---|
| Device | Samsung Galaxy A04 (SM-A045M), Android 14, 3.7 GB RAM |
| GPU | PowerVR Rogue GE8320, OpenGL ES 3.2, driver build 1.13@5776728. Impeller falls back from Vulkan to GLES. |
| Flutter | **3.50.0** stable (the current project). Earlier runs used 3.41.8; reproduce those from commit `39772a9`. All runs in `--profile`. |
| Renderers | Impeller (default) and Skia (`--no-enable-impeller`). Skia runs print Flutter's "Impeller opt-out deprecated" notice, which confirms the renderer. |
| Conditions | USB, screen kept on by the device's stay-awake setting, nothing else in the foreground (one exception, noted below) |

## Method

1. **The app** ([`lib/main.dart`](lib/main.dart)) runs 30 rounds by itself. Each round does this three times:
   - push a list of 24 cards (rounded corners, shadow, `Clip.antiAlias`, an 800×600 PNG generated on the device);
   - scroll to the end and back, twice;
   - pop.

   After each round it prints `IMPELLER_REPRO round=N` and waits 4 s.
2. **The measuring script** ([`tool/measure.ps1`](tool/measure.ps1)) records one CSV row per round:
   - from `dumpsys meminfo <package>`: `Graphics`, `GL mtrack` and the app's `TOTAL RSS`;
   - from `/proc/meminfo`: the device's `MemAvailable` and `CmaFree`.
3. **The analysis** ([`tool/analyze.dart`](tool/analyze.dart)) works in four steps:
   - **It undoes the wraparound.** The counter reads 0 between 2 and 4 GiB and starts over after 4 GiB, like a signed 32-bit byte count. The script rebuilds the cumulative value from that.
   - **It fits a line** to the cumulative value against the round number.
   - **It tests the wraparound assumption:** every reading of 0 must fall where the fitted line predicts the 2–4 GiB band.
   - **It reports real memory:** `MemAvailable`, and the app's RSS without `Graphics` (see finding 3).

Scenarios (`--dart-define=SCENARIO=...`):

| Scenario | What it changes |
|---|---|
| `images` | The same images every round. This is the default. |
| `fresh` | New images every round. |
| `no_images` | Flat colors instead of images. Rounds are shorter (~31 s against ~50 s). |
| `stack` | Screens are never popped, so 90 image screens pile up. |

## Results

### Flutter 3.50.0

| Run | Renderer, scenario | `Graphics` growth (MB/round) | R² | Seconds per round | `Graphics` growth (MB/s) | Value at last round (reconstructed) | `MemAvailable`, first → last (MB) | App RSS without `Graphics`, round 1 → last (MB) |
|---|---|---|---|---|---|---|---|---|
| [130647](results/20261112-130647-impeller-images.csv) | Impeller, `images` | 729 | 1.000 | 49.6 | 14.7 | 21.3 GB | 1652 → 1607 | 167 → 197 |
| [140311](results/20261112-140311-impeller-fresh.csv) | Impeller, `fresh` | 717 | 1.000 | 49.6 | 14.5 | 21.0 GB | 1777 → 1606 | 162 → 184 |
| [145851](results/20261112-145851-impeller-no_images.csv) | Impeller, `no_images` | 425 | 1.000 | 31.0 | 13.7 | 12.5 GB | 1692 → 1808 | 152 → 174 |
| [151517](results/20261112-151517-impeller-stack.csv) | Impeller, `stack` | 580 | 1.000 | 49.0 | 11.8 | 17.3 GB | **1754 → 164** | 163 → 33 (swapped out) |
| [133302](results/20261112-133302-skia-images.csv) | Skia, `images` | 110 | 0.998 | 59.0 | 1.9 | ~3.3 GB (reads 0) | 1772 → 1621 | 167 → 191 |
| [142848](results/20261112-142848-skia-fresh.csv) | Skia, `fresh` | 96 | 0.999 | 58.9 | 1.6 | ~2.9 GB (reads 0) | 1695 → 1570 | 180 → 201 |
| [154041](results/20261112-154041-skia-stack.csv) | Skia, `stack` (28 rounds) | 166 | 1.000 | 57.7 | 2.9 | 4.6 GB | **1896 → 220** | 170 → 65 (swapped out) |

### Flutter 3.41.8

| Run | Renderer, scenario | `Graphics` growth (MB/round) | R² | Seconds per round | `Graphics` growth (MB/s) | Value at round 30 (reconstructed) | `MemAvailable`, round 0 → 30 (MB) | App RSS without `Graphics`, round 1 → 30 (MB) |
|---|---|---|---|---|---|---|---|---|
| [225455](results/20261111-225455-impeller-images.csv) | Impeller, `images` | 397 | 0.994 | 51.8 | 7.7 | 12.6 GB | not recorded | not recorded |
| [081612](results/20261112-081612-impeller-images.csv) | Impeller, `images` | 590 | 1.000 | 50.4 | 11.7 | 17.5 GB | 1745 → 1637 | not recorded |
| [090653](results/20261112-090653-impeller-fresh.csv) | Impeller, `fresh` | 569 | 1.000 | 50.4 | 11.3 | 16.6 GB | 1684 → 1592 | not recorded |
| [104429](results/20261112-104429-impeller-fresh.csv) | Impeller, `fresh` | 595 | 1.000 | 50.4 | 11.8 | 17.4 GB | 1731 → 1585 | 159 → 180 |
| [232906](results/20261111-232906-skia-images.csv) | Skia, `images` | 91 | 0.998 | 59.0 | 1.5 | ~2.8 GB (reads 0) | 1658 → 1593 | not recorded |

The full table, with zero-reading checks, `CmaFree` and native heap, is the output of `dart run tool/analyze.dart results/*.csv`. "Seconds per round" and "MB/s" come from the `time` column.

### Findings

1. **The counter grows at a fixed rate per second of rendering, whatever is on screen.**
   - With Impeller on 3.50.0 it grows 13.7–14.7 MB/s with the same images, with new images, and with no images at all. `no_images` grows less per round only because its rounds are shorter.
   - With Skia it grows 1.6–2.9 MB/s, 5–8× less.
   - 3.50.0 drives it faster than 3.41.8: 14 MB/s against 8–12.
2. **The counter goes far past physical RAM:** 21 GB on a 3.7 GB phone, and the app was never killed while screens were being popped. Whatever the counter tracks is not resident memory.
3. **The app's own resident memory is flat.** `TOTAL RSS` in `dumpsys meminfo` includes the same `Graphics` value.
   - **Proof:** `TOTAL RSS − Graphics` is the same whether `Graphics` reads 0 or 1.9 GB (run 104429: 178 MB at round 24, 179 MB at round 25).
   - **Without `Graphics`,** the app stays at 150–200 MB on both renderers and both versions. Most of the small rise happens in the first rounds (warm-up).
4. **When screens are never popped (`stack`), real memory does fall, and the same with both renderers.**
   - `MemAvailable` drops ~56 MB per round with Impeller and ~60 with Skia, down to 164–220 MB.
   - Android then swaps the app out: its RSS and native heap fall in the last rounds.
   - The app survived 30 rounds with Impeller. The Skia run was cut at round 28 by an external event (see Limitations).
   - This is the cost of keeping 90 image screens alive, not something specific to Impeller.
5. **`CmaFree` is not a signal on this phone.** The contiguous pool was nearly empty before every run (0–23 MB free of 336 MB at round 0), and it reaches 0 with both renderers.
6. **The wraparound explains the zeros.** In 152 of 159 cases, the fitted line puts a zero reading in the 2–4 GiB band. The other 7 are rounds the line places within 71 MB of a band edge, within the fit's error.

## Limitations

- **One device, one driver.** No Vulkan device has been measured as a control.
- **Run-to-run variance on 3.41.8:** the first Impeller run grew 7.7 MB/s against 11.3–11.8 in the next three. On 3.50.0 the three comparable Impeller runs agree (13.7–14.7 MB/s).
- **The Skia `stack` run stopped at round 28.** At 16:08:51 another app was launched on the phone, and the test app's process was killed. The CSV says so in its last line, and rounds 0–28 are valid. The script now stops and records it when the app dies.
- **Older runs lack some columns:** `MemAvailable`, RSS and `CmaFree` were added along the way (see the [notebook](NOTEBOOK.md)).
- **`MemAvailable` is device-wide and noisy:** it swings 150–190 MB within a run. It would hide a slow leak, but not one of hundreds of MB per round, which is what the counter claims.
- **Smoothness was not measured here.** The production app showed 22–47 % slow frames with Impeller against 2–5 % with Skia; that is flutter/flutter#195767's subject.

## Reproduce

Requirements: Flutter 3.50.0, `adb`, PowerShell 7, one Android device connected.

```powershell
./tool/measure.ps1 -Renderer impeller -Scenario images   # ~26 min
./tool/measure.ps1 -Renderer skia     -Scenario images
dart run tool/analyze.dart results/*.csv
```

To use an SDK that is not on `PATH`, pass `-Flutter C:\path\to\flutter\bin\flutter.bat`.

## Data and notebook

- [`results/`](results/) has every run, unedited apart from one appended note on the interrupted run. Its [README](results/README.md) explains the columns.
- [`NOTEBOOK.md`](NOTEBOOK.md) logs each run in date order: the commit used, anything that went wrong, and what changed in the method.
- [`report/comment-178264.md`](report/comment-178264.md) is the comment drafted for flutter/flutter#178264.

## Next steps

- [x] `fresh`, `no_images` and `stack` scenarios.
- [x] Repeat on Flutter 3.50.0.
- [x] The app's resident memory, on both renderers.
- [ ] Run a Vulkan device as a control.
- [ ] Check `dumpsys gpu` as a second view of GPU memory.
- [ ] Post upstream ([draft](report/comment-178264.md)).

## Related upstream issues

- flutter/flutter#178264: GL mtrack growing to ~4 GB on Adreno and Xclipse. It is open.
- flutter/flutter#195767: Impeller GLES raster about 2× slower than Skia on Mali-G31. It is open and P1.
- flutter/flutter#193009: GE8320 jank with Impeller. It was closed without a reproduction.

## License

MIT
