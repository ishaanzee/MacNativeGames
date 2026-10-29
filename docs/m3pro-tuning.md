# Tuning notes: MacBook Pro 14" M3 Pro, 120 Hz (2026-10-29)

Measured on a MacBook Pro 14" (M3 Pro, 18-core GPU, 36 GB), macOS 27.0, built-in 120 Hz ProMotion display in the scaled
"More Space" mode (1800x1169 points, so the game window's drawable is 3600x2025), on AC power. Breath of the Wild 1.9.0
with both DLC packs, Tears of the Kingdom 1.4.3, both built from upstream main `f1d0077` plus this branch.

Every number comes from [tools/ab-bench](../tools/ab-bench/README.md): a copy of the player's own profile, the newest (or a
chosen) save loaded with `TOTK_AUTOLOAD=1`, the camera panning, every game frame's time recorded. "In-session A/B" means one
session switching between the two conditions with runtime flags in 30 s windows, A B B A B A A B, so both see the same
scene, cache and temperature. "1 % low" is 1000 / the 99th-percentile frame time.

## What this branch changes

1. **Breath of the Wild: sync lag off by default** (`games/totk/third_party/d2r_gfx/gfx/nvn/hle_nvn.c`,
   `SYNC_LAG_DEFAULT`). `TOTK_SYNC_LAG=1` or `flag sync_lag 1` turns it back on.
2. **Two A/B flags** for settings the panel holds: `flag taa <0|1>` (edge smoothing) and `flag fps_lock <0|30|...|120>`
   (`nvn_mtl.m`, `dm_gfx_set_flag`).
3. **Fast edge smoothing** (`totk_taa.m`, opt-in): a classic TAA resolve in one compute pass on key 5's own jitter,
   motion vectors and reactive mask, instead of MetalFX's temporal network. The settings panel's edge smoothing row is now
   off / fast / MetalFX (kept in `graphics-taa.txt` and `graphics-taa-mode.txt`); `TOTK_TAA_FAST=1` or
   `flag taa_fast 1` select it too, `TOTK_TAA_FAST_ALPHA` / `TOTK_TAA_FAST_GAMMA` tune it. MetalFX stays the default.
4. **tools/ab-bench**: the harness above.

### Why sync lag off (Breath of the Wild 1.9.0, MetalFX 2K + edge smoothing)

With the lag on, the game's main thread computes frame N+1 while the GPU still draws frame N. Where the GPU is the
bottleneck that queue never drains, and every tenth frame (the frames that draw about 20 more render passes than the rest)
waits it out: a ~25 ms frame, then two or three short ones catching up, and the display holds that frame for three
refreshes. The per-frame TSV (`DM_NVN_TSV`) shows the GPU busy back to back in both modes, so the lag only bought the
average a few percent and cost an even cadence:

| Scene (in-session A/B) | sync lag | FPS | 1 % low | p95 | frames > 16.7 ms |
|---|---|---|---|---|---|
| Great Deku Tree | on | 90.3 | 39.7 | 24.4 ms | 1,087 |
| Great Deku Tree | **off** | 84.2 | **62.9** | **14.5 ms** | **11** |
| a village (Goddess Statue) | on | 73.4 | 36.8 | 25.7 ms | 1,928 |
| a village (Goddess Statue) | **off** | 68.9 | **51.0** | **17.8 ms** | 1,133 |

Upstream turned it on for Breath of the Wild on 2026-10-28 from a 1.6.0 Hebra measurement (8.78 -> 7.29 ms a frame, p95
unchanged); there the CPU was the limit. With the heavier picture settings the GPU is, and then the lag only adds queue
depth.

## Findings

### Breath of the Wild 1.9.0

- **Update vs the Oct 22 build** (Great Deku Tree, MetalFX 2K + edge smoothing, one session each): about 82 -> 87 FPS on
  upstream main with its defaults; with sync lag off (this branch) the hitches of the new default go away.
- **Edge smoothing (key 5 / settings panel) is the expensive setting on macOS 27.** In a shrine, MetalFX 2K on, in-session
  A/B: edge smoothing on 98.6 FPS (GPU 8.4 ms a frame), off 144.0 FPS (the 144 ceiling; GPU 4.3 ms). MetalFX's temporal
  scaler on macOS 27 is a neural network (BRNet); on this M3 Pro part of it also runs on the Neural Engine, and the commit
  that submits it costs the render thread about 1 ms a frame (`sample`: `ANEServicesProgramProcessRequestDirect` under
  `q4_commit`).
- **MetalFX's own switches do not make it cheaper here.** The framework reads `MTLFX_TEMPORAL_SCALER_VERSION` (BRNet3,
  BRNet4, BRNet4_Fused, BBRNet1, BBRNet1_Fused) and `MTLFX_FORCE_GPU`. One session each, shrine, MetalFX 2K + edge
  smoothing (FPS / GPU ms a frame): default 98.9 / 8.32, BRNet3 97.6 / 8.39, BRNet4_Fused 98.0 / 8.39, BBRNet1_Fused
  98.8 / 8.33, `MTLFX_FORCE_GPU=1` 91.2 / 9.17 (the Neural Engine offload helps), edge smoothing off 143.7 / 4.34.
- **Fast edge smoothing vs MetalFX's** (shrine, MetalFX 2K, in-session A/B): fast 122.6 FPS, 1 % low 93.6, GPU
  6.1 ms a frame, 1.0 % of presents held; MetalFX 95.4 FPS, 1 % low 76.0, GPU 8.6 ms, 25.9 % held. Still frames of the
  same view look alike at 2x (both smooth the stair steps that "off" shows); frames in the middle of a camera pan show no
  trails on Link or the light beams. Not yet checked: dense foliage in the open world, where variance clipping can let
  thin bright detail shimmer more than the network does.
- **Frame lock 120 vs uncapped (144)**: no difference where the game runs below 120 (shrine with edge smoothing: 98.8 vs
  98.9 FPS). It matters where it would run above 120: frames the panel can never show are not rendered.
- **Latency**: with the GPU saturated a frame reaches the screen 30-40 ms after its GPU work ends (per-frame TSV,
  `@gpu_end_ms` to `@pres_at_ms`): the present's copy and MetalFX output stage are committed at the display tick, behind
  the next frames' work on the one Metal queue.

## Follow-ups (not done here)

- A present queue of its own (or committing the present ahead of the next frame's work) for the latency above.
- MetalFX output straight into the drawable (drawable sized to the 16:9 picture, Core Animation letterboxing it): saves the
  full-screen present pass, about 0.3-0.5 ms a frame at 3600x2025.
- Fast edge smoothing: a sharpening pass (RCAS) and object motion (it follows the camera only, like key 5's MetalFX
  path; the reactive mask and clipping handle characters).
