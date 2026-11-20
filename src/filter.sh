#!/bin/zsh
# Alfred Script Filter: gh <query> [pull|issues|actions|...]
export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH
# Workflow configuration (Alfred "Configure Workflow"):
#   GH_USER          gh account to use; empty = gh's active account
#   CACHE_TTL_HOURS  hours before the repository cache is refreshed (default 24)
GH_USER=${GH_USER:-}
[[ $CACHE_TTL_HOURS == <-> ]] || CACHE_TTL_HOURS=24
CACHE_DIR=${alfred_workflow_cache:-$HOME/Library/Caches/com.github.motchang.alfred-gh}
# Per-account cache so switching accounts never shows another account's repos
ACCOUNT_KEY=${GH_USER:-active}
CACHE=$CACHE_DIR/repos-$ACCOUNT_KEY.txt
LOGIN_CACHE=$CACHE_DIR/login-$ACCOUNT_KEY.txt
ERROR=$CACHE_DIR/error-$ACCOUNT_KEY.txt
LOCK=$CACHE_DIR/refresh-$ACCOUNT_KEY.lock
TTL=$(( CACHE_TTL_HOURS * 3600 ))
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

refresh() {
  # Prevent concurrent refreshes; a lock older than 10 minutes is treated as stale
  if ! mkdir "$LOCK" 2>/dev/null; then
    local a; a=$(age "$LOCK")
    [ -n "$a" ] && [ "$a" -lt 600 ] && return
    command rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || return
  fi
  command rm -f "$ERROR"
  # Each job owns the lock via a token; a job whose lock was broken won't remove the new one
  local token=$$.$RANDOM
  print -r -- "$token" > "$LOCK/owner"
  # Detach so Alfred killing this script on the next keystroke doesn't abort the fetch
  nohup /bin/zsh -c '
    cache=$1 user=$2 lock=$3 err=$4 token=$5
    tmp="$cache.tmp.$$" log="$cache.log.$$"
    if [ -n "$user" ]; then
      GH_TOKEN=$(gh auth token --user "$user" 2>"$log")
      st=$?
      if [ $st -ne 0 ] || [ -z "$GH_TOKEN" ]; then
        print -r -- "token $st $(head -n1 "$log")" > "$err"
      else
        export GH_TOKEN
      fi
    fi
    if [ ! -e "$err" ]; then
      gh api --paginate \
        "/user/repos?per_page=100&affiliation=owner,collaborator,organization_member" \
        --jq ".[].full_name" > "$tmp" 2>"$log"
      st=$?
      if [ $st -eq 0 ] && [ -s "$tmp" ]; then
        command mv -f "$tmp" "$cache"; command rm -f "$err"
      else
        print -r -- "api $st $(head -n1 "$log")" > "$err"
      fi
    fi
    command rm -f "$tmp" "$log"
    [ "$(cat "$lock/owner" 2>/dev/null)" = "$token" ] && command rm -rf "$lock"
  ' _ "$CACHE" "$GH_USER" "$LOCK" "$ERROR" "$token" >/dev/null 2>&1 &!
}

# Turn a recorded background error into an Alfred item
show_error() {
  local kind st msg
  read -r kind st msg < "$ERROR"
  if [ "$kind" = token ]; then
    fail_item "GH_USER $GH_USER is not logged in to gh" "gh auth login  ($msg)"
  elif [[ $msg == *(auth login|not logged|GH_TOKEN|401|Bad credentials)* ]]; then
    fail_item "gh is not logged in" "Run: gh auth login  ($msg)"
  else
    fail_item "Failed to fetch repositories (exit $st)" "${msg:-unknown error}"
  fi
}

command rm -f "$CACHE_DIR"/repos-*.txt.(tmp|log).*(N.mm+15)
if [ ! -s "$CACHE" ]; then
  # A failed fetch is shown once; the next keystroke retries
  if [ -s "$ERROR" ] && [ ! -d "$LOCK" ]; then
    ( show_error ); command rm -f "$ERROR"; exit 0
  fi
  refresh
  echo '{"rerun":1,"items":[{"title":"Building repository cache…","subtitle":"First run only; this can take about a minute. Results appear automatically.","valid":false}]}'
  exit 0
else
  a=$(age "$CACHE")
  [ -n "$a" ] && [ "$a" -gt $TTL ] && refresh
fi

q="$1"
words=(${=q})
sub=""
case "${words[-1]:l}" in
  pull|pulls|pr|prs) sub=pulls ;;
  issue|issues)      sub=issues ;;
  action|actions)    sub=actions ;;
  wiki)              sub=wiki ;;
  setting|settings)  sub=settings ;;
  branch|branches)   sub=branches ;;
  release|releases)  sub=releases ;;
esac
# A trailing subcommand only counts when there is something before it
if (( ${#words} > 1 )); then
  [ -n "$sub" ] && words=(${words[1,-2]})
else
  sub=""
fi
needle="${(j: :)words}"

# gh my [pr|issue]: search pages for open PRs / issues authored by you
my_items='[]'
if [ "${words[1]:l}" = my ]; then
  login=$GH_USER
  if [ -z "$login" ]; then
    login=$(cat "$LOGIN_CACHE" 2>/dev/null)
    if [ -z "$login" ]; then
      login=$(gh api user --jq .login 2>/dev/null) && [ -n "$login" ] && print -r -- "$login" > "$LOGIN_CACHE"
    fi
  fi
  [ -z "$login" ] && fail_item "Could not determine your GitHub login" "Run: gh auth login, or set GH_USER"
  my_items=$(jq -n -c --arg u "$login" --arg k "${${sub/pulls/pr}/issues/issue}" '
    [ {k: "pr",    t: "My open pull requests", q: "is:pr state:open author:\($u)",    ty: "pullrequests"},
      {k: "issue", t: "My open issues",        q: "is:issue state:open author:\($u)", ty: "issues"} ]
    | map(select($k == "" or (.k | startswith($k[0:2]))))
    | map(("https://github.com/search?q=" + (.q | @uri) + "&type=" + .ty) as $url
          | {uid: ("my-" + .k), title: .t, subtitle: $url, arg: $url, quicklookurl: $url})')
fi

jq -R -s -c --argjson my "$my_items" --arg q "$needle" --arg sub "$sub" '
  def esc: gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/])"; "\\\(.c)");
  ($q | ascii_downcase | gsub("\\s+"; "")) as $n
  | ($n | split("") | map(esc) | join(".*")) as $re
  | [ split("\n")[] | select(length > 0)
      | . as $full | (split("/")[1]) as $name
      | ($full | ascii_downcase) as $lf | ($name | ascii_downcase) as $ln
      | select($n == "" or ($lf | test($re)))
      | { full: $full,
          score: ( if $n == "" then 0
                   elif $ln == $n then 1000
                   elif ($ln | startswith($n)) then 500
                   elif ($ln | contains($n)) then 300
                   elif ($lf | contains($n)) then 200
                   elif ($ln | test($re)) then 100
                   else 0 end ) - ($full | length) / 100 } ]
  | sort_by(-.score) | .[:30]
  | (if $sub == "" then "" else "/" + $sub end) as $suffix
  | { items: map({
      uid: .full,
      title: (.full + $suffix),
      subtitle: ("https://github.com/" + .full + $suffix),
      arg: ("https://github.com/" + .full + $suffix),
      autocomplete: (.full | split("/")[1]),
      quicklookurl: ("https://github.com/" + .full + $suffix)
    }) }
  | .items = ($my + .items)
  | if (.items | length) == 0 then {items: [{title: "No matching repository", valid: false}]} else . end
' "$CACHE"
