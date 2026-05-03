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

### Caching compinit

Replace your `compinit` call (or let it replace Oh My Zsh's):

```zsh
# Instead of:
autoload -Uz compinit && compinit

# Use:
autoload -Uz compinit
_startcache_compinit
```

**With Oh My Zsh:** Add `zsh-startcache` to your plugins list and set `DISABLE_COMPFIX=true` in your `.zshrc` (before sourcing OMZ). The plugin handles compinit itself.

### Clearing the cache

After installing new tools or completions:

```zsh
_startcache_clear
```

Or just delete the cache directory:

```zsh
rm -rf ~/.cache/zsh-startcache
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

## Why not just `typeset -U fpath`?

`typeset -U fpath` prevents *duplicate* entries but doesn't prevent *ordering changes*. When tmux opens a new pane, macOS system paths may be prepended in a different order. OMZ's fpath-string comparison sees a different string and triggers a full rebuild — even though the *set* of paths hasn't changed.

The only reliable fix is to stop comparing fpath strings entirely and use time-based staleness instead.

## Benchmarks

Measured on Apple M1 Pro, Oh My Zsh with 13 plugins:

| Configuration | Shell startup |
|---------------|--------------|
| Stock OMZ (compinit every time) | ~350ms |
| OMZ + `typeset -U fpath` (still rebuilds on order change) | ~350ms* |
| OMZ + `_startcache_compinit` | ~35ms |
| OMZ + `_startcache_compinit` + `_startcache_eval` for mise/fzf | ~28ms |

*\*Helps only when duplicates were the sole cause of invalidation.*

## Credits

- [ctechols](https://gist.github.com/ctechols/ca1035271ad134841284) — Original "compinit once a day" gist
- [mroth/evalcache](https://github.com/mroth/evalcache) — Inspiration for the eval caching approach
- [mattmc3/ez-compinit](https://github.com/mattmc3/ez-compinit) — Prior art on compinit management

## License

MIT
