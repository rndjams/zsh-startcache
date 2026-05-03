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

export ZSH_STARTCACHE_DIR="${ZSH_STARTCACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh-startcache}"
export ZSH_STARTCACHE_TTL="${ZSH_STARTCACHE_TTL:-24}"  # hours

# Deduplicate fpath early — prevents ordering drift from triggering rebuilds
typeset -U fpath PATH path

# --- compinit interception ---------------------------------------------------
# Wrap compinit so frameworks (OMZ, prezto, etc.) call our deferred version.
# The real compinit runs once at the end of .zshrc via precmd hook.

_startcache_compinit_args=()
_startcache_compinit_done=0

# Save the real compinit, replace with our interceptor
autoload -Uz compinit
functions[_startcache_real_compinit]=$functions[compinit]

function compinit() {
  # Capture args but don't run yet — fpath isn't fully populated
  _startcache_compinit_args=("$@")
}

# Queue compdef calls until compinit actually runs
_startcache_compdef_queue=()
function compdef() {
  _startcache_compdef_queue+=("${(j: :)${(q)@}}")
}

# Run the real compinit with time-based caching. Called automatically via
# precmd hook (first prompt) or manually if you prefer.
function _startcache_compinit() {
  (( _startcache_compinit_done )) && return
  _startcache_compinit_done=1

  # Restore real compinit
  functions[compinit]=$functions[_startcache_real_compinit]
  unfunction _startcache_real_compinit 2>/dev/null

  local compdump="${ZSH_COMPDUMP:-${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST:-${HOST/.*/}}-${ZSH_VERSION}}"

  # Time-based staleness: rebuild only if missing or older than TTL
  local stale=( ${compdump}(N.mh+${ZSH_STARTCACHE_TTL}) )
  if [[ -s "$compdump" ]] && (( ${#stale} == 0 )); then
    compinit -C -d "$compdump"
  else
    compinit ${_startcache_compinit_args[@]} -d "$compdump"
    zcompile "$compdump" 2>/dev/null
  fi

  # Replay queued compdef calls
  local def
  for def in "${_startcache_compdef_queue[@]}"; do
    eval "compdef ${def}"
  done
  unset _startcache_compdef_queue

  # Restore real compdef
  unfunction compdef 2>/dev/null
  autoload -Uz compdef 2>/dev/null || true
}

# Auto-run on first prompt if not already called manually
function _startcache_precmd_hook() {
  _startcache_compinit
  add-zsh-hook -d precmd _startcache_precmd_hook
  unfunction _startcache_precmd_hook
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _startcache_precmd_hook

# --- eval caching ------------------------------------------------------------
# Usage: _startcache_eval [ENV=VAL...] COMMAND [ARGS...]
function _startcache_eval() {
  local name
  for name in "$@"; do
    [[ "$name" == *=* ]] || break
  done

  mkdir -p "$ZSH_STARTCACHE_DIR"
  local cache_file="$ZSH_STARTCACHE_DIR/eval-${name##*/}.sh"

  local stale=( ${cache_file}(N.mh+${ZSH_STARTCACHE_TTL}) )
  if [[ -s "$cache_file" ]] && (( ${#stale} == 0 )); then
    source "$cache_file"
  else
    if (( $+commands[$name] )) || typeset -f "$name" >/dev/null 2>&1; then
      eval ${(q)@} > "$cache_file" 2>/dev/null
      source "$cache_file"
      zcompile "$cache_file" 2>/dev/null
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
  echo "startcache: cleared. Restart shell to rebuild."
}
