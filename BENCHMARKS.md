# Benchmark Results

**Date:** 2026-05-03
**Hardware:** Apple M1 Pro, macOS 26.4.1
**Shell:** zsh 5.9, Oh My Zsh (13 plugins)
**Tools tested:** brew, mise, direnv, starship

## 1. Eval Caching (`_startcache_eval`)

| Command | Subprocess (eval) | Cached (source) | Speedup |
|---------|-------------------|-----------------|---------|
| brew shellenv | 77ms | 16ms | 4.8x |
| mise activate | 54ms | 28ms | 1.9x |
| direnv hook | 13ms | 1ms | 13.0x |
| starship init | 25ms | 14ms | 1.8x |
| **TOTAL** | **169ms** | **59ms** | **2.9x** |

Net savings: **110ms per shell startup**

## 2. Compinit Caching (`_startcache_compinit`)

| Mode | Time | Notes |
|------|------|-------|
| Full rebuild | 1083ms | Scans all fpath directories |
| `compinit -C` (cached) | 12ms | Skips all checks |
| **Savings** | **1071ms** | **89x faster** |

Triggers for unnecessary rebuild (without startcache):
- fpath order changes between sessions (tmux, screen)
- New completion file added (`brew install`)
- Duplicate fpath entries from re-sourcing `.zshrc`

## 3. End-to-End Shell Startup (hyperfine, 10 runs)

| Configuration | Mean ± σ |
|---------------|----------|
| Raw evals only (no OMZ, no cache) | 238 ± 45ms |
| startcache evals (no OMZ, cached) | 115 ± 11ms |
| **Eval-only savings** | **123ms (2.1x)** |

## 4. Combined Savings

| Scenario | Before | After | Savings |
|----------|--------|-------|---------|
| Best case (compinit rebuild avoided + eval cached) | 1252ms | 71ms | **1181ms (17.6x)** |
| Typical case (compinit fresh, eval cached) | 181ms | 71ms | **110ms (2.5x)** |

## Methodology

- **Eval timing:** `zsh/datetime` EPOCHREALTIME, 10-100 iterations, mean reported
- **Compinit timing:** `zsh/datetime` EPOCHREALTIME, 5 iterations for rebuild, 20 for cached
- **End-to-end:** `hyperfine --warmup 3 --runs 10`
- **Cache files:** zcompiled (`.zwc`) for maximum source speed
- **Isolation:** `--no-globalrcs` for eval-only tests to exclude OMZ overhead
