# zsh-startcache

Fast zsh startup via time-based caching. One plugin that replaces both `evalcache` and the slow `compinit` rebuild cycle.

## The Problem

Two things make zsh startup slow:

1. **`eval "$(tool init zsh)"`** — Tools like `mise`, `rbenv`, `pyenv`, `nvm`, `direnv`, and `starship` need shell initialization. Each `eval` spawns a subprocess and costs 10-50ms.

2. **`compinit` rebuilds every session** — The completion system checks whether its cache (zcompdump) is stale by comparing the current `$fpath` as a string. If *anything* changes — a new completion file, a reordered path, a duplicate entry from tmux re-sourcing `.zshrc` — it nukes the cache and does a full rebuild (15-30ms).

Together these can add 100-300ms to every new shell.

## The Fix

`zsh-startcache` uses **time-based staleness** (default: 24 hours) for both:

- **`_startcache_eval`** — Caches command output to a file. Sources the file on subsequent shells. Only re-runs the command when the cache is older than the TTL.
- **`_startcache_compinit`** — Calls `compinit -C` (skip all checks) when the zcompdump exists and is fresh. Only does a full rebuild when the dump is missing or stale. Also applies `typeset -U fpath` to prevent duplicate-induced invalidation.

## Installation

### With a plugin manager

```zsh
# zinit
zinit light rndjams/zsh-startcache

# antidote
antidote bundle rndjams/zsh-startcache

# sheldon
sheldon add zsh-startcache --github rndjams/zsh-startcache

# oh-my-zsh (as custom plugin)
git clone https://github.com/rndjams/zsh-startcache ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-startcache
# then add zsh-startcache to your plugins=(...) list
```

### Manual

```zsh
git clone https://github.com/rndjams/zsh-startcache ~/.zsh-startcache
echo 'source ~/.zsh-startcache/zsh-startcache.plugin.zsh' >> ~/.zshrc
```

## Usage

### With Oh My Zsh (or any framework)

Source the plugin **before** your framework. It intercepts `compinit` automatically:

```zsh
# .zshrc
source ~/.zsh-startcache/zsh-startcache.plugin.zsh  # ← before OMZ

export ZSH="$HOME/.oh-my-zsh"
plugins=(git fzf kubectl ...)
source $ZSH/oh-my-zsh.sh  # compinit is intercepted, deferred, and cached

# Replace slow evals:
_startcache_eval mise activate zsh
_startcache_eval starship init zsh
_startcache_eval direnv hook zsh
```

That's it. No configuration needed. The plugin:
1. Wraps `compinit` before your framework calls it
2. Queues any `compdef` calls from plugins
3. Runs the real `compinit` with time-based caching at first prompt
4. Replays queued `compdef` calls

### Without a framework

```zsh
source ~/.zsh-startcache/zsh-startcache.plugin.zsh

# Your fpath additions...
fpath=(~/.zsh/completions $fpath)

# Cached evals:
_startcache_eval mise activate zsh
_startcache_eval starship init zsh

# compinit runs automatically at first prompt, or call manually:
# _startcache_compinit
```

### Caching eval initializations

Replace slow `eval` calls:

```zsh
# Before (runs every shell, 20-50ms each):
eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(direnv hook zsh)"

# After (cached, <1ms on subsequent shells):
_startcache_eval mise activate zsh
_startcache_eval starship init zsh
_startcache_eval direnv hook zsh
```

### Clearing the cache

After installing new tools or completions:

```zsh
_startcache_clear
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ZSH_STARTCACHE_DIR` | `~/.cache/zsh-startcache` | Cache directory |
| `ZSH_STARTCACHE_TTL` | `24` | Cache lifetime in hours |

Set these before sourcing the plugin:

```zsh
export ZSH_STARTCACHE_TTL=48  # rebuild every 2 days
source ~/.zsh-startcache/zsh-startcache.plugin.zsh
```

## How it works

When sourced, the plugin immediately:

1. **Applies `typeset -U fpath`** — prevents duplicate entries from causing cache invalidation
2. **Wraps `compinit`** with a no-op interceptor — frameworks call it, but nothing happens yet
3. **Wraps `compdef`** with a queue — plugin registrations are captured for later
4. **Registers a `precmd` hook** — at first prompt (after `.zshrc` is fully loaded and fpath is complete), runs the real `compinit` with time-based caching and replays all queued `compdef` calls

This means it works transparently with Oh My Zsh, Prezto, or any framework that calls `compinit` internally. No patching, no special flags.

## Benchmarks

Measured on Apple M1 Pro, zsh 5.9, Oh My Zsh with 13 plugins:

### Eval caching

| Command | Subprocess | Cached | Speedup |
|---------|-----------|--------|---------|
| `brew shellenv` | 77ms | 16ms | 4.8x |
| `mise activate zsh` | 54ms | 28ms | 1.9x |
| `direnv hook zsh` | 13ms | 1ms | 13x |
| `starship init zsh` | 25ms | 14ms | 1.8x |
| **Total** | **169ms** | **59ms** | **2.9x** |

### Compinit caching

| Mode | Time |
|------|------|
| Full rebuild (scans all fpath dirs) | 1083ms |
| `compinit -C` (time-based cache) | 12ms |
| **Savings when rebuild avoided** | **1071ms (89x)** |

### Combined

| Scenario | Before | After | Savings |
|----------|--------|-------|---------|
| Typical (compinit fresh, evals cached) | 181ms | 71ms | **110ms** |
| Worst case (compinit rebuild + evals) | 1252ms | 71ms | **1181ms** |

## Credits

- [ctechols](https://gist.github.com/ctechols/ca1035271ad134841284) — Original "compinit once a day" gist
- [mroth/evalcache](https://github.com/mroth/evalcache) — Inspiration for the eval caching approach
- [mattmc3/ez-compinit](https://github.com/mattmc3/ez-compinit) — Prior art on compinit management

## License

MIT
