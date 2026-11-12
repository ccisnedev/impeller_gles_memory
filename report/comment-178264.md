A data point on how far `Graphics` / `GL mtrack` can be trusted, from a PowerVR device on GLES, measured on 3.50.0 and 3.41.8.

On this driver the counter grows at a fixed rate per second of rendering, wraps around, and does not reflect resident memory. A reading of 0 is not proof that memory was released, and a large reading is not proof that it is held.

**Device:** Galaxy A04 (SM-A045M), Android 14, 3.7 GB RAM, PowerVR Rogue GE8320, OpenGL ES 3.2 (driver 1.13@5776728). Impeller falls back to GLES. `--profile`.

**Repro:** https://github.com/ccisnedev/impeller_gles_memory
- **The app** runs 30 rounds. In each round it pushes a list of 24 cards (rounded corners, shadow, `Clip.antiAlias`, optionally an image), scrolls it and pops it, three times.
- **After each round,** a script samples `dumpsys meminfo <pkg>` and `/proc/meminfo`.
- **The repo also has** the raw CSVs, the analysis script and a lab notebook.

**Flutter 3.50.0, 30 rounds:**

| Run | `Graphics` growth | `Graphics` at the end (reconstructed) | App `TOTAL RSS − Graphics` | Device `MemAvailable` |
|---|---|---|---|---|
| Impeller, same images | 14.7 MB/s | 21.3 GB | 167 → 197 MB | 1652 → 1607 MB |
| Impeller, new images every round | 14.5 MB/s | 21.0 GB | 162 → 184 MB | 1777 → 1606 MB |
| Impeller, no images | 13.7 MB/s | 12.5 GB (shorter rounds) | 152 → 174 MB | 1692 → 1808 MB |
| Skia, same images | 1.9 MB/s | ~3.3 GB | 167 → 191 MB | 1772 → 1621 MB |
| Skia, new images every round | 1.6 MB/s | ~2.9 GB | 180 → 201 MB | 1695 → 1570 MB |

The app was never killed in these runs. On 3.41.8 the same Impeller runs grew 7.7–11.8 MB/s, and Skia 1.5 MB/s.

**What we found:**
1. **The counter wraps.** Past 2 GiB it reads 0 and the `GL mtrack` line disappears; past 4 GiB it comes back small, like a signed 32-bit byte count.
   - If the cumulative value is rebuilt on that assumption, it fits a straight line (R² ≥ 0.99).
   - In 152 of 159 zero readings across 12 runs, the line places them in the 2–4 GiB band; the other 7 fall within 71 MB of a band edge.
2. **It is not resident memory.** It reaches 21 GB on a 3.7 GB phone.
   - `TOTAL RSS` includes the same value: `TOTAL RSS − Graphics` is 178 MB when `Graphics` reads 1.9 GB and 179 MB one round later, when it reads 0.
   - Without it, the app stays at 150–200 MB.
3. **The growth depends on rendering time, not on content.** With Impeller it is ~14 MB per second whether the screens show the same images, new images, or no images.
   - Even if every second rendered 60 frames, that would be ~240 KB per frame; the rounds include pauses, so the real per-frame figure is higher.
   - Impeller drives it 5–8× faster than Skia, and 3.50.0 faster than 3.41.8.
   - That looks like per-frame transient allocations (render targets or buffers) that the driver counts and never subtracts, but we have not confirmed what they are.
4. **Real memory only falls when the UI really holds more,** and then equally with both renderers. When 90 image screens are pushed and never popped, `MemAvailable` drops ~56 MB per round with Impeller and ~60 with Skia.

**Caveats:**
- One device and one driver; no Vulkan control.
- `MemAvailable` is noisy (it swings 150–190 MB within a run), so it would not show a retention smaller than that.
- The contiguous pool (`CmaFree`) was already near 0 before every run on this phone, so we could not test the CMA effect described above.

In short: on drivers like this one, `GL mtrack` alone cannot tell whether there is a leak, in either direction. That supports exposing Impeller's own GPU memory stats, as this issue proposes.
