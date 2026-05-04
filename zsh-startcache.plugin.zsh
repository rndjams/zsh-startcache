# zsh-startcache - Fast shell startup via time-based caching
#
# Source this BEFORE oh-my-zsh/framework. It automatically intercepts compinit
# and defers it until fpath is fully populated, then uses time-based caching.
#
# Usage (minimal):
#   source ~/.zsh-startcache/zsh-startcache.plugin.zsh
#   source $ZSH/oh-my-zsh.sh   # compinit is intercepted automatically
#
# Copyright (c) 2026 Randy James
# SPDX-License-Identifier: MIT

# Guard against double-sourcing
(( _STARTCACHE_LOADED )) && return
_STARTCACHE_LOADED=1

export ZSH_STARTCACHE_DIR="${ZSH_STARTCACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh-startcache}"
export ZSH_STARTCACHE_TTL="${ZSH_STARTCACHE_TTL:-24}"  # hours

# Deduplicate fpath early — prevents ordering drift from triggering rebuilds
typeset -U fpath PATH path

# --- compinit interception ---------------------------------------------------

_startcache_compinit_args=()
_startcache_compinit_done=0

# Load compinit so we can capture its function body, then replace it.
# If compinit isn't in fpath yet (unusual), skip interception gracefully.
if autoload -Uz compinit 2>/dev/null && (( $+functions[compinit] )); then
  functions[_startcache_real_compinit]=$functions[compinit]

  function compinit() {
    # Capture args but don't run yet — fpath isn't fully populated
    _startcache_compinit_args=("$@")
  }
else
  # compinit not available at source time — skip interception,
  # user will need to call _startcache_compinit manually after fpath is set
  function _startcache_real_compinit() {
    autoload -Uz compinit && compinit "$@"
  }
fi

# Queue compdef calls until compinit actually runs
_startcache_compdef_queue=()
if (( $+functions[compdef] )); then
  # compdef already exists (rare) — save it
  functions[_startcache_real_compdef]=$functions[compdef]
fi
function compdef() {
  _startcache_compdef_queue+=("${(j: :)${(q)@}}")
}

# Run the real compinit with time-based caching.
function _startcache_compinit() {
  (( _startcache_compinit_done )) && return
  _startcache_compinit_done=1

  # Restore real compinit
  if (( $+functions[_startcache_real_compinit] )); then
    functions[compinit]=$functions[_startcache_real_compinit]
    unfunction _startcache_real_compinit
  fi

  # Remove our compdef wrapper — real compinit will define the real one
  unfunction compdef 2>/dev/null

  local compdump="${ZSH_COMPDUMP:-${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST:-${(%):-%m}}-${ZSH_VERSION}}"

  # Time-based staleness: rebuild only if missing or older than TTL
  local -a stale
  stale=( ${compdump}(N.mh+${ZSH_STARTCACHE_TTL}) )
  if [[ -s "$compdump" ]] && (( ${#stale} == 0 )); then
    compinit -C -d "$compdump"
  else
    compinit ${_startcache_compinit_args[@]} -d "$compdump"
    zcompile "$compdump" 2>/dev/null &!
  fi

  # Replay queued compdef calls (compdef is now the real one from compinit)
  local def
  for def in "${_startcache_compdef_queue[@]}"; do
    eval "compdef ${def}"
  done
  unset _startcache_compdef_queue _startcache_compinit_args
}

# Auto-run on first prompt if not already called manually
function _startcache_precmd_hook() {
  _startcache_compinit
  add-zsh-hook -d precmd _startcache_precmd_hook
  unfunction _startcache_precmd_hook 2>/dev/null
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _startcache_precmd_hook

# --- eval caching ------------------------------------------------------------
# Usage: _startcache_eval [ENV=VAL...] COMMAND [ARGS...]
# Cache key includes all arguments to avoid collisions.
function _startcache_eval() {
  local name args_hash
  for name in "$@"; do
    [[ "$name" == *=* ]] || break
  done

  # Hash all args for cache key — prevents collisions between e.g.
  # "mise activate zsh" and "mise activate bash"
  if (( $+commands[md5] )); then
    args_hash=$(printf '%s' "$*" | md5)
  elif (( $+commands[md5sum] )); then
    args_hash=$(printf '%s' "$*" | md5sum | cut -d' ' -f1)
  else
    # Fallback: use a sanitized version of the full command
    args_hash=${${*//[^a-zA-Z0-9._-]/_}[1,80]}
  fi

  mkdir -p "$ZSH_STARTCACHE_DIR"
  local cache_file="$ZSH_STARTCACHE_DIR/eval-${name##*/}-${args_hash}.sh"

  local -a stale
  stale=( ${cache_file}(N.mh+${ZSH_STARTCACHE_TTL}) )
  if [[ -s "$cache_file" ]] && (( ${#stale} == 0 )); then
    source "$cache_file"
  else
    if (( $+commands[$name] )) || [[ -x "$name" ]] || typeset -f "$name" >/dev/null 2>&1; then
      # Write to temp file first to avoid partial reads from concurrent shells
      local tmp_file="${cache_file}.$$"
      eval ${(q)@} > "$tmp_file" 2>/dev/null
      if [[ -s "$tmp_file" ]]; then
        mv -f "$tmp_file" "$cache_file"
        source "$cache_file"
        zcompile "$cache_file" 2>/dev/null &!
      else
        # Command produced no output — run without caching
        rm -f "$tmp_file"
        eval ${(q)@}
      fi
    else
      echo "startcache: $name not found in PATH" >&2
      return 1
    fi
  fi
}

# --- cache management --------------------------------------------------------
function _startcache_clear() {
  rm -rf "$ZSH_STARTCACHE_DIR"
  rm -f "${ZSH_COMPDUMP:-${ZDOTDIR:-$HOME}/.zcompdump}"*(N)
  _startcache_compinit_done=0
  _STARTCACHE_LOADED=0
  echo "startcache: cleared. Restart shell to rebuild."
}
