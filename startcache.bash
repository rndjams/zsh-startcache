# startcache.bash — Fast shell startup for bash
#
# No framework needed. No plugin manager. Just source this file.
#
# Add to your .bashrc:
#   source ~/.startcache.bash
#   _startcache_eval brew shellenv
#   _startcache_eval mise activate bash
#   _startcache_eval direnv hook bash
#   _startcache_eval starship init bash
#
# Copyright (c) 2026 Randy James
# SPDX-License-Identifier: MIT

STARTCACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/startcache"
STARTCACHE_TTL="${STARTCACHE_TTL:-1440}"  # minutes (24h)

_startcache_eval() {
  local name="$1"
  local hash file

  # Hash the full command for cache key
  if command -v md5sum &>/dev/null; then
    hash=$(printf '%s' "$*" | md5sum | cut -d' ' -f1)
  elif command -v md5 &>/dev/null; then
    hash=$(printf '%s' "$*" | md5)
  else
    hash=$(printf '%s' "$*" | cksum | cut -d' ' -f1)
  fi

  file="$STARTCACHE_DIR/${name##*/}-$hash.sh"
  mkdir -p "$STARTCACHE_DIR"

  # Fresh cache? Source it.
  if [[ -f "$file" ]]; then
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
    age=$(( (now - mtime) / 60 ))
    if (( age < STARTCACHE_TTL )); then
      source "$file"
      return
    fi
  fi

  # Rebuild: run command, cache output, source it
  if command -v "$name" &>/dev/null; then
    local tmp="$file.$$"
    "$@" > "$tmp" 2>/dev/null
    if [[ -s "$tmp" ]]; then
      mv -f "$tmp" "$file"
      source "$file"
    else
      rm -f "$tmp"
      eval "$("$@")"
    fi
  else
    echo "startcache: $name not found" >&2
    return 1
  fi
}

_startcache_clear() {
  rm -rf "$STARTCACHE_DIR"
  echo "startcache: cleared. Restart shell to rebuild."
}
