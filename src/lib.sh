# Shared helpers for alfred-gh script filters. Sourced by zsh scripts.
# ALFRED_GH_PATH_PREFIX lets tests put stub commands first
export PATH=${ALFRED_GH_PATH_PREFIX:+$ALFRED_GH_PATH_PREFIX:}/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH
GH_USER=${GH_USER:-}
CACHE_DIR=${alfred_workflow_cache:-$HOME/Library/Caches/com.github.motchang.alfred-gh}
# Per-account cache so switching accounts never shows another account's data
ACCOUNT_KEY=${GH_USER:-active}
mkdir -p "$CACHE_DIR"

# Print a single non-actionable Alfred item and exit
fail_item() {
  jq -n -c --arg t "$1" --arg s "$2" '{items: [{title: $t, subtitle: $s, valid: false}]}'
  exit 0
}

if ! command -v jq >/dev/null; then
  # Cannot use jq to build the JSON; the text is static
  echo '{"items":[{"title":"jq not found","subtitle":"brew install jq","valid":false}]}'
  exit 0
fi
command -v gh >/dev/null || fail_item "gh not found" "brew install gh"

# Seconds since a file was modified; empty if it doesn't exist
age() { local m; m=$(stat -f %m "$1" 2>/dev/null) && print $(( $(date +%s) - m )); }

# Turn an error file ("<kind> <exit> <message>") into an Alfred item; $2 names what failed
show_error() {
  local kind st msg
  read -r kind st msg < "$1"
  if [ "$kind" = token ]; then
    fail_item "GH_USER $GH_USER is not logged in to gh" "gh auth login  ($msg)"
  elif [[ $msg == *(auth login|not logged|GH_TOKEN|401|Bad credentials)* ]]; then
    fail_item "gh is not logged in" "Run: gh auth login  ($msg)"
  else
    fail_item "Failed to fetch $2 (exit $st)" "${msg:-unknown error}"
  fi
}

# GitHub login to use as author: GH_USER, else the active account's (cached)
resolve_login() {
  local login=$GH_USER f=$CACHE_DIR/login-$ACCOUNT_KEY.txt
  if [ -z "$login" ]; then
    login=$(cat "$f" 2>/dev/null)
    if [ -z "$login" ]; then
      login=$(gh api user --jq .login 2>/dev/null) && [ -n "$login" ] && print -r -- "$login" > "$f"
    fi
  fi
  print -r -- "$login"
}

# Valid GitHub login (EMU logins contain "_")
valid_login() { [[ $1 =~ '^[A-Za-z0-9_-]+$' ]]; }

# --- Background fetches --------------------------------------------------------
# A script re-runs itself detached with ALFRED_GH_FETCH=1 and its parameters in
# the environment (never argv, which carries the user's typed query).

# start_bg <lock> <max lock age in s> <script> [VAR=value...]
# Each job owns the lock via a token; a job whose lock was broken won't touch the new one.
start_bg() {
  local lock=$1 maxage=$2 script=$3; shift 3
  if ! mkdir "$lock" 2>/dev/null; then
    local a; a=$(age "$lock")
    [ -n "$a" ] && [ "$a" -lt "$maxage" ] && return 1
    command rm -rf "$lock"; mkdir "$lock" 2>/dev/null || return 1
  fi
  local token=$$.$RANDOM
  print -r -- "$token" > "$lock/owner"
  # Detach so Alfred killing the script on the next keystroke doesn't abort the fetch
  ALFRED_GH_FETCH=1 FETCH_LOCK=$lock FETCH_TOKEN=$token \
    nohup env "$@" /bin/zsh "$script" >/dev/null 2>&1 &!
}

owns_lock() { [ "$(cat "$FETCH_LOCK/owner" 2>/dev/null)" = "$FETCH_TOKEN" ]; }

# Export GH_TOKEN for GH_USER; on failure write "token <exit> <message>" to $1
use_gh_user() {
  [ -n "$GH_USER" ] || return 0
  local log=$1.log.$$ st
  GH_TOKEN=$(gh auth token --user "$GH_USER" 2>"$log"); st=$?
  if [ $st -ne 0 ] || [ -z "$GH_TOKEN" ]; then
    print -r -- "token $st $(head -n1 "$log")" > "$1"
    command rm -f "$log"; return 1
  fi
  command rm -f "$log"; export GH_TOKEN
}

# with_timeout <seconds> <cmd...>: exit status 143 if the command was killed
with_timeout() {
  local secs=$1 pid w st; shift
  "$@" & pid=$!
  ( trap 'kill $s 2>/dev/null; exit 0' TERM; sleep "$secs" & s=$!; wait $s; kill $pid 2>/dev/null ) & w=$!
  wait $pid; st=$?
  kill $w 2>/dev/null
  return $st
}

# fetch_to <cache> <error file> <timeout s> <check fn> <cmd...>
# Writes the command's stdout to the cache if it succeeds, passes <check fn> and
# this job still owns the lock; otherwise records "api <exit> <message>".
fetch_to() {
  local cache=$1 err=$2 secs=$3 check=$4 tmp log st; shift 4
  tmp=$cache.tmp.$$ log=$cache.log.$$
  command rm -f "$err"
  if use_gh_user "$err"; then
    with_timeout "$secs" "$@" > "$tmp" 2>"$log"; st=$?
    [ $st -eq 143 ] && print -r -- "timed out after ${secs}s" > "$log"
    if [ $st -eq 0 ] && $check "$tmp"; then
      owns_lock && command mv -f "$tmp" "$cache"
    else
      print -r -- "api $st $(head -n1 "$log")" > "$err"
    fi
  fi
  command rm -f "$tmp" "$log"
  owns_lock && command rm -rf "$FETCH_LOCK"
}
