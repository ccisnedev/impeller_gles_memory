# impeller_gles_memory

Minimal reproduction for investigating **graphics-memory growth with Impeller on OpenGL ES** on PowerVR GPUs. It was first seen on a Samsung Galaxy A04 (PowerVR Rogue GE8320), where Impeller falls back from Vulkan to GLES.

## Observation that motivated this

In a production Flutter 3.41.8 app, on a Galaxy A04:

| | Impeller (default) | Skia (`--no-enable-impeller`) |
|---|---|---|
| Graphics memory after several navigation rounds | 716 → 1237 MB (about +55 MB per round, not released at rest) | stable |
| Frames over 16.7 ms while scrolling | 22–47 % | 1.6–5 % |

The growth happened even on screens without image-heavy lists. This project tries to reproduce it with no app-specific code.

Related upstream issues:
- flutter/flutter#193009: GE8320 jank, closed without a reproduction.
- #168788: scroll jank with Impeller on Android.
- #179454 and #180347: the Impeller opt-out deprecation notice.

## What the app does

The app runs "rounds" by itself. Each round does this on three screens:
1. Push a screen with a list of cards. Each card has rounded corners, a shadow, clipping and an 800×600 PNG generated on the device.
2. Scroll to the end and back, twice.
3. Pop the screen.

After each round the app prints `IMPELLER_REPRO round=N` to logcat and pauses, so memory can be sampled.

Scenarios (`--dart-define=SCENARIO=...`):

| Scenario | What it isolates |
|---|---|
| `images` (default) | Same images every round. Memory should reach a plateau. |
| `fresh` | New images every round. Exercises texture allocation and release. |
| `no_images` | Same layout with flat colors. Separates images from layers. |
| `stack` | Screens are pushed and never popped, like a tab bar that stacks routes. |

Other defines:
- `ROUNDS`: default 30; `0` means endless.
- `PAUSE_MS`: default 4000.

## How to measure

Connect one Android device over adb, then run:

```powershell
./tool/measure.ps1 -Renderer impeller -Scenario images -Rounds 30
./tool/measure.ps1 -Renderer skia     -Scenario images -Rounds 30
```

Each run writes `results/<timestamp>-<renderer>-<scenario>.csv`.
- **Header:** the device, the GPU and the Flutter version.
- **One row per round,** taken from `dumpsys meminfo`: `TOTAL PSS`, `Graphics`, `GL mtrack`, `EGL mtrack` and `Native Heap`.

Runs use `--profile`, because `--no-enable-impeller` only applies to debug and profile builds.

A leak looks like this: `Graphics` and `GL mtrack` grow roughly linearly with the round number under Impeller, and flatten under Skia.

### Comparing Flutter versions

Use `-Flutter` to point at another SDK, so the same measurement runs on each version:

```powershell
./tool/measure.ps1 -Renderer impeller -Flutter C:\sdk\flutter-3.50.0\bin\flutter.bat
```

## Plan

- [ ] Reproduce on the Galaxy A04 with Flutter 3.41.8: Impeller vs Skia, all four scenarios.
- [ ] Repeat with the latest stable (3.50.0). Several 3.44–3.47 changes touch GLES texture and fence cleanup, for example #187216, #183561 and #188313.
- [ ] Compare against a Vulkan-capable device.
- [ ] If it still reproduces on the latest stable, file an upstream issue with this project and the CSVs.

## License

MIT
