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
