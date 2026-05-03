# zsh-startcache - Fast shell startup via time-based caching
#
# Provides two functions:
#   _startcache_eval  - Cache output of slow `eval "$(cmd)"` initializations
#   _startcache_compinit - Time-based compinit with fpath dedup
#
# Copyright (c) 2026 Randy James
# SPDX-License-Identifier: MIT

export ZSH_STARTCACHE_DIR="${ZSH_STARTCACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh-startcache}"
export ZSH_STARTCACHE_TTL="${ZSH_STARTCACHE_TTL:-24}"  # hours

# --- eval caching -----------------------------------------------------------
# Usage: _startcache_eval [ENV=VAL...] COMMAND [ARGS...]
# Caches the stdout of a command and sources it on subsequent shells.
# Rebuilds when cache is older than ZSH_STARTCACHE_TTL hours.
function _startcache_eval() {
  local data="$*" name
  # First non-assignment arg is the command name
  for name in "$@"; do
    [[ "$name" == *=* ]] || break
  done

  local cache_file="$ZSH_STARTCACHE_DIR/eval-${name##*/}.sh"
  mkdir -p "$ZSH_STARTCACHE_DIR"

  # Check staleness
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

# --- compinit caching --------------------------------------------------------
# Usage: _startcache_compinit [-d COMPDUMP] [-i|-u]
# Replaces compinit with time-based cache. Only rebuilds when:
#   - zcompdump is missing
#   - zcompdump is older than ZSH_STARTCACHE_TTL hours
# Also applies typeset -U fpath to prevent ordering-based invalidation.
function _startcache_compinit() {
  # Deduplicate fpath — prevents ordering drift across sessions
  typeset -U fpath

  local compdump="${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST:-${HOST/.*/}}-${ZSH_VERSION}"
  local compflags=(-d "$compdump")
  local arg
  for arg in "$@"; do
    case "$arg" in
      -d) shift; compdump="$1"; compflags=(-d "$compdump"); shift ;;
      -d*) compdump="${arg#-d}"; compflags=(-d "$compdump") ;;
      -i|-u) compflags+=("$arg") ;;
    esac
  done

  # Stale check: rebuild only if missing or older than TTL
  local stale=( ${compdump}(N.mh+${ZSH_STARTCACHE_TTL}) )
  if [[ -s "$compdump" ]] && (( ${#stale} == 0 )); then
    compinit -C $compflags
  else
    compinit $compflags
    zcompile "$compdump" 2>/dev/null
  fi
}

# --- cache management --------------------------------------------------------
function _startcache_clear() {
  echo "Clearing startcache: $ZSH_STARTCACHE_DIR"
  rm -rf "$ZSH_STARTCACHE_DIR"
  rm -f "${ZDOTDIR:-$HOME}"/.zcompdump*(N)
  echo "Done. Restart your shell to rebuild caches."
}
