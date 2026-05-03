#!/usr/bin/env zsh
# bench.sh — Measure zsh-startcache impact on YOUR system
#
# Requirements: hyperfine (brew install hyperfine)
#
# Usage: ./bench.sh
#
# Customize EVAL_COMMANDS below to match your .zshrc's eval calls.

set -e

# --- Configuration -----------------------------------------------------------
# Add/remove eval commands to match your setup:
EVAL_COMMANDS=(
  '/opt/homebrew/bin/brew shellenv'
  'mise activate zsh'
  'direnv hook zsh'
  'starship init zsh'
)

# Framework detection
if [[ -n "$ZSH" && -d "$ZSH" ]]; then
  FRAMEWORK="omz"
  FRAMEWORK_SOURCE='export ZSH=$HOME/.oh-my-zsh; plugins=(git fzf kubectl history); source $ZSH/oh-my-zsh.sh'
elif [[ -d "${ZDOTDIR:-$HOME}/.zprezto" ]]; then
  FRAMEWORK="prezto"
  FRAMEWORK_SOURCE='source ${ZDOTDIR:-$HOME}/.zprezto/init.zsh'
else
  FRAMEWORK="none"
  FRAMEWORK_SOURCE='autoload -Uz compinit && compinit'
fi

# --- Helpers -----------------------------------------------------------------
STARTCACHE="${0:A:h}/zsh-startcache.plugin.zsh"
CACHE_DIR="/tmp/startcache-bench-$$"
mkdir -p "$CACHE_DIR"

extract_mean() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g' | grep "Time (mean" | awk '{print $5, $6}'
}

# Build eval strings
raw_evals=""
cached_evals=""
for cmd in "${EVAL_COMMANDS[@]}"; do
  raw_evals+="eval \"\$($cmd)\"; "
  cached_evals+="_startcache_eval $cmd; "
done

# --- Checks ------------------------------------------------------------------
if ! command -v hyperfine &>/dev/null; then
  echo "Error: hyperfine not found. Install with: brew install hyperfine"
  exit 1
fi

if [[ ! -f "$STARTCACHE" ]]; then
  echo "Error: zsh-startcache.plugin.zsh not found at $STARTCACHE"
  exit 1
fi

# Filter to only commands that exist
valid_evals=""
valid_cached=""
for cmd in "${EVAL_COMMANDS[@]}"; do
  name="${cmd%% *}"
  if command -v "${name##*/}" &>/dev/null; then
    valid_evals+="eval \"\$($cmd)\"; "
    valid_cached+="_startcache_eval $cmd; "
  else
    echo "Skipping $name (not installed)"
  fi
done
raw_evals="$valid_evals"
cached_evals="$valid_cached"

# Prime cache
zsh --no-globalrcs -c "export ZSH_STARTCACHE_DIR=$CACHE_DIR; source $STARTCACHE; $cached_evals _startcache_compinit" 2>/dev/null

# --- Benchmarks --------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " zsh-startcache benchmark"
echo " Framework: $FRAMEWORK"
echo " Eval commands: ${#EVAL_COMMANDS[@]}"
echo " System: $(uname -m) · zsh $ZSH_VERSION · $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "1/5 Baseline (zsh startup floor)..."
r1=$(extract_mean "$(hyperfine --warmup 3 --runs 15 -N "zsh --no-globalrcs -c exit" 2>&1)")

echo "2/5 Framework + raw evals (warm compinit cache)..."
r2=$(extract_mean "$(hyperfine --warmup 3 --runs 10 -N "zsh --no-globalrcs -c '$FRAMEWORK_SOURCE; $raw_evals exit'" 2>&1)")

echo "3/5 Framework + raw evals (fpath drift — compinit rebuilds every time)..."
r3=$(extract_mean "$(hyperfine --warmup 0 --runs 5 -N --prepare 'rm -f ~/.zcompdump*' "zsh --no-globalrcs -c '$FRAMEWORK_SOURCE; $raw_evals exit'" 2>&1)")

echo "4/5 Framework + startcache (warm)..."
r4=$(extract_mean "$(hyperfine --warmup 3 --runs 10 -N "zsh --no-globalrcs -c 'export ZSH_STARTCACHE_DIR=$CACHE_DIR; source $STARTCACHE; $FRAMEWORK_SOURCE; $cached_evals exit'" 2>&1)")

echo "5/5 Framework + startcache (fpath drift — startcache is immune)..."
r5=$(extract_mean "$(hyperfine --warmup 0 --runs 5 -N --prepare 'rm -f ~/.zcompdump*' "zsh --no-globalrcs -c 'export ZSH_STARTCACHE_DIR=$CACHE_DIR; source $STARTCACHE; $FRAMEWORK_SOURCE; $cached_evals exit'" 2>&1)")

# --- Results -----------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf " %-52s %10s\n" "Configuration" "Mean"
echo " ──────────────────────────────────────────────────── ──────────"
printf " %-52s %10s\n" "zsh baseline (floor)" "$r1"
printf " %-52s %10s\n" "$FRAMEWORK + evals (warm cache)" "$r2"
printf " %-52s %10s\n" "$FRAMEWORK + evals (fpath drift, rebuilds)" "$r3"
printf " %-52s %10s\n" "$FRAMEWORK + startcache (warm)" "$r4"
printf " %-52s %10s\n" "$FRAMEWORK + startcache (fpath drift, immune)" "$r5"
echo " ──────────────────────────────────────────────────── ──────────"
echo ""
echo " Warm savings:  $r2 → $r4"
echo " Drift savings: $r3 → $r5  ← the big win for tmux/screen users"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup
rm -rf "$CACHE_DIR"
