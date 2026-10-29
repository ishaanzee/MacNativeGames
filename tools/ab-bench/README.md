# A/B benchmark harness (Mac)

Small scripts used for the measurements in [docs/m3pro-tuning.md](../../docs/m3pro-tuning.md). They run a built app's game
binary directly, on a **copy** of the player's profile (saves are never touched), load the newest save with
`TOTK_AUTOLOAD=1`, pan the camera with scripted key presses and record every game frame's time (`TOTK_BENCH_FRAMES`).
Settings files are read from the run folder, so the player's own settings are neither read nor written.

Runs go to `$BENCH_RUNS/runs/<label>` (default `~/Games/bench-runs`). Quit the game first; one game at a time.

## One session per configuration

```sh
tools/ab-bench/bench.sh new-taa "$HOME/Games/Apps/Breath of the Wild.app" TOTK_MFX_OUTPUT=1 TOTK_MFX_UPSCALE=1 TOTK_TAA=1
python3 -I tools/ab-bench/bench_parse.py ~/Games/bench-runs/runs new-taa
```

`GAME=totk` for Tears of the Kingdom, `SETTLE` / `MEASURE` seconds, `KEEP_SLOT=<n>` keeps only that numbered save slot in
the copy (Breath of the Wild), `SETTINGS=graphics-frame.txt=lock-120,...` pre-seeds settings files, `CACHE=` another shader
cache folder (an older build's chain).

## In-session A/B (preferred)

Runtime flags switch between two conditions in 30 s windows, A B B A B A A B, in the same scene:

```sh
A="flag sync_lag 1" B="flag sync_lag 0" tools/ab-bench/bench_ab.sh ab-synclag "$HOME/Games/Apps/Breath of the Wild.app" \
    TOTK_MFX_OUTPUT=1 TOTK_MFX_UPSCALE=1 TOTK_TAA=1
python3 -I tools/ab-bench/ab_parse.py ~/Games/bench-runs/runs ab-synclag
```

Useful flags: `sync_lag`, `uncapped_interval`, `mfx_output` + `mfx_upscale` (MetalFX 2K), `taa` and `fps_lock <fps>`
(added on this branch), `pass_gpu <frames>` (per-pass GPU times, diagnostic only).

Columns: average FPS, 1 % low (from the 99th percentile frame time), frame-time p50 / p95 / p99, frames over 12.5 / 16.7 /
33 ms, the log's GPU and submit p50 (game submissions only: the present's MetalFX output stage is not in "GPU"), and the
present cadence (`held%` = presents that stayed on screen more than one refresh).
