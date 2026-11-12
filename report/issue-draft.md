# Draft upstream report

**Status:** draft, not posted.

**Target:** a comment on flutter/flutter#178264, the open issue about `GL mtrack` growing to ~4 GB. A new issue only if the maintainers ask for one.

**Before posting:**
- [ ] Repeat on the latest stable (3.50.0).
- [x] Add per-process RSS: flat at ~180 MB once `Graphics` is subtracted.
- [x] Run at least one more scenario (`fresh`: same rate as `images`).
- [ ] Update the numbers below from `tool/analyze.dart`.

---

### Comment text

Another data point, on a PowerVR GPU running GLES. It suggests that the `Graphics` / `GL mtrack` numbers in `dumpsys meminfo` can be misleading on some drivers.

**Device:** Galaxy A04 (SM-A045M), Android 14, PowerVR Rogue GE8320, OpenGL ES 3.2 (driver 1.13@5776728). Impeller falls back to GLES. Flutter 3.41.8, profile mode.

**Repro:** https://github.com/ccisnedev/impeller_gles_memory. The app runs 30 rounds; in each round it pushes a list of image cards, scrolls it and pops it. `tool/measure.ps1` samples `dumpsys meminfo` and `/proc/meminfo` after every round.

**What we see:**

| | Impeller | Skia |
|---|---|---|
| `Graphics` growth | 397–590 MB/round, linear (R² ≥ 0.99); the same with new images every round (569) | 91 MB/round, linear |
| `Graphics` after 30 rounds (reconstructed) | 12.6–17.5 GB | ~2.8 GB |
| Device `MemAvailable` | no trend beyond noise (1745 → 1637 MB; −3 MB/round with new images) | flat (1658 → 1593 MB) |
| App RSS without `Graphics` | 159 → 180 MB over 30 rounds | not measured yet |
| Native heap | 25–42 MB | 33–51 MB |
| App killed | no | no |

- **The counter wraps around.** It reads 0 once the value passes 2 GiB, the `GL mtrack` line disappears, and it starts over after 4 GiB, like a signed 32-bit byte count. Fitting a line to the reconstructed value puts 63 of 68 zero readings inside the 2–4 GiB band. The other 5 fall within 71 MB of a band edge, within the fit's error.
- **The counter is not resident memory.** It reaches 17.5 GB on a phone with 3.7 GB of RAM, while free memory stays flat. `TOTAL RSS` includes the same value (`TOTAL RSS − Graphics` is unchanged whether `Graphics` reads 0 or 1.9 GB); without it, the app stays at ~180 MB.

**So, on this driver:**
1. **`GL mtrack` seems to count allocations it never subtracts,** so it cannot be used to detect leaks, and the wraparound hides the growth from anyone sampling occasionally.
2. **Impeller drives that counter 4–6× faster than Skia** for the same UI. That may point to many more short-lived allocations (textures, render targets), which matches the render-target caching explanation earlier in this thread.

**What we did not measure:** a Vulkan device, other driver versions, and Flutter newer than 3.41.8 (this comment will be updated if 3.50 differs).

Raw CSVs, the analysis script and a lab notebook are in the repo.
