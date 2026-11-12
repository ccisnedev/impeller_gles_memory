# Lab notebook

Entries in date order. Times are local (UTC−5). Each entry gives the commit of the app and script used for the run.

## 2026-11-11: background

A production app (Flutter 3.41.8) was profiled on the same Galaxy A04. Over several rounds of tab navigation, `Graphics` went from 716 to 1237 MB with Impeller, about +55 MB per round, and stayed flat with Skia. Frames over 16.7 ms were 22–47 % with Impeller and 2–5 % with Skia. This project was created to reproduce the memory part with no app-specific code.

## 2026-11-11 22:54: Impeller, `images` (commit `5620f62`)

- [Data](results/20261111-225455-impeller-images.csv). Each round took ~52 s.
- **`Graphics` dropped to 0 for runs of rounds and came back small** (rounds 5–9, 15–20 and 26–29). That pattern led to the hypothesis that the counter wraps around.
- **`MemAvailable` was not recorded yet.**
- **The run finished,** but the script failed during cleanup because the adb connection had dropped.

## 2026-11-11 23:29: Skia, `images` (commit `625a5ad`)

- [Data](results/20261111-232906-skia-images.csv). This run adds the `MemAvailable` column.
- **The counter also grows with Skia,** at ~91 MB per round, and reads 0 from round 21 on.
- **`MemAvailable` stays flat,** at 1593–1700 MB.
- **The script's end-of-run error appeared again:** PowerShell rewraps the end-of-run exception thrown inside a pipeline fed by a native command.

## 2026-11-12 08:16: Impeller, `images`, repeat (commit `625a5ad`)

- [Data](results/20261112-081612-impeller-images.csv).
- **The counter grows ~590 MB per round,** against 397 in the first Impeller run. The variance is not explained yet.
- **`MemAvailable` stays flat,** at 1637–1787 MB. The reconstructed counter reaches 17.5 GB.
- **The same end-of-run error appeared.** Fixed afterwards: the script now detects the normal end with a flag instead of the exception text.

## 2026-11-12: analysis

- Added [`tool/analyze.dart`](tool/analyze.dart). It rebuilds the counter's cumulative value, fits a line, and checks that every zero reading falls inside the predicted 2–4 GiB band.
- **Conclusion so far:** H2 (the counter is driver accounting) is supported, and H1 (a real leak) is not. The result is in the [README](README.md#results).

## 2026-11-12 09:06: Impeller, `fresh` (commit `0c0c040`)

- [Data](results/20261112-090653-impeller-fresh.csv). New images every round.
- **The counter grows ~569 MB per round,** about the same as `images` (590), so decoding new images does not change the rate. All 14 zero readings fall in the predicted band.
- **`MemAvailable` drifts −3 MB per round** (1684 → 1592 MB). That is inside the run's noise, but it is the first non-flat trend. Per-process RSS is needed to tell whether it is real.
- **The end-of-run fix works:** the script printed `CSV:` and finished without error.

## 2026-11-12: method change, per-process memory

- `tool/measure.ps1` now records `process_rss_kb`: `TOTAL RSS` from the App Summary of `dumpsys meminfo`. The regex was checked on the device against `com.android.systemui`.
- **Why:** the `fresh` run showed `MemAvailable` drifting −3 MB per round. Device-wide memory is too noisy to tell whether that is the app, so the app's own resident memory is needed.
- `tool/analyze.dart` reports its first → last value and its trend. Earlier runs show `not recorded`.

## 2026-11-12 10:44: Impeller, `fresh`, with process RSS (commit `09df50a`)

- [Data](results/20261112-104429-impeller-fresh.csv).
- **The counter grows ~595 MB per round,** the same as the previous `fresh` run (569).
- **The raw `TOTAL RSS` follows the counter** (1.6 GB at round 30), so it includes the `Graphics` value. `TOTAL RSS − Graphics` is the same whether `Graphics` reads 0 or 1.9 GB, which confirms it.
- **Without `Graphics`, the app's resident memory is flat:** 159 MB at round 1, 176 MB at round 8, 180 MB at round 30.
- **`MemAvailable` has no trend this time** (−0.2 MB per round). The −3 MB per round drift of the previous `fresh` run was noise.
- `tool/analyze.dart` now reports `TOTAL RSS − Graphics` instead of raw RSS.
