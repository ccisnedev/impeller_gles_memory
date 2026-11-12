# Raw data

Each run writes one CSV here. The files are kept exactly as `tool/measure.ps1` wrote them.

**File name:** `<yyyyMMdd-HHmmss>-<renderer>-<scenario>.csv`. The time is local (UTC−5).

**Header lines** start with `#`:
- the device model and Android version;
- the GLES line from `dumpsys SurfaceFlinger`;
- `flutter --version`.

**Columns** (one row per round; round 0 is the baseline before the first round):

| Column | Source | Notes |
|---|---|---|
| `round` | the app's `IMPELLER_REPRO round=N` marker | |
| `time` | the PC clock when the sample was taken | |
| `total_pss_kb` | `dumpsys meminfo`, `TOTAL PSS` | Includes `Graphics`. |
| `graphics_kb` | `dumpsys meminfo`, `Graphics` | Driver counter. Reads 0 between 2 and 4 GiB (see the README). |
| `gl_mtrack_kb` | `dumpsys meminfo`, `GL mtrack` | Empty when the line is missing, which happens whenever `Graphics` reads 0. |
| `egl_mtrack_kb` | `dumpsys meminfo`, `EGL mtrack` | |
| `native_heap_kb` | `dumpsys meminfo`, `Native Heap` | |
| `device_mem_available_kb` | `/proc/meminfo`, `MemAvailable` | Device-wide physical check. Added in commit `625a5ad`, so older runs lack it. |
| `process_rss_kb` | `dumpsys meminfo`, `TOTAL RSS` in the App Summary | Added in commit `09df50a`, so older runs lack it. **It includes the `Graphics` value:** `process_rss_kb − graphics_kb` is the app's own resident memory. |
| `device_cma_free_kb` | `/proc/meminfo`, `CmaFree` | Contiguous pool some GPU drivers allocate from. Added in commit `32f5810`. |

A trailing `#` line after the rows means the run ended early; it says why. The app may have died, or an external event may have interrupted it.
