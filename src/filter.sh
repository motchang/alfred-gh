#!/bin/zsh
# Alfred Script Filter: gh <query> [pull|issues|actions|...]
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
# Workflow configuration (Alfred "Configure Workflow"):
#   GH_USER          gh account to use; empty = gh's active account
#   CACHE_TTL_HOURS  hours before the repository cache is refreshed (default 24)
GH_USER=${GH_USER:-}
CACHE_DIR=${alfred_workflow_cache:-$HOME/Library/Caches/com.github.motchang.alfred-gh}
# Per-account cache so switching accounts never shows another account's repos
ACCOUNT_KEY=${GH_USER:-active}
CACHE=$CACHE_DIR/repos-$ACCOUNT_KEY.txt
LOGIN_CACHE=$CACHE_DIR/login-$ACCOUNT_KEY.txt
TTL=$(( ${CACHE_TTL_HOURS:-24} * 3600 ))
mkdir -p "$CACHE_DIR"

# Run gh as GH_USER when set; otherwise as gh's active account
ghx() {
  if [ -n "$GH_USER" ]; then
    GH_TOKEN=$(gh auth token --user "$GH_USER") gh "$@"
  else
    gh "$@"
  fi
}

LOCK=$CACHE_DIR/refresh-$ACCOUNT_KEY.lock
refresh() {
  # Prevent concurrent refreshes; a lock older than 10 minutes is treated as stale
  if ! mkdir "$LOCK" 2>/dev/null; then
    [ $(( $(date +%s) - $(stat -f %m "$LOCK") )) -lt 600 ] && return
    rmdir "$LOCK"; mkdir "$LOCK" || return
  fi
  # Detach so Alfred killing this script on the next keystroke doesn't abort the fetch
  nohup /bin/zsh -c '
    tmp="$1.tmp.$$"
    [ -n "$2" ] && export GH_TOKEN=$(gh auth token --user "$2")
    gh api --paginate \
      "/user/repos?per_page=100&affiliation=owner,collaborator,organization_member" \
      --jq ".[].full_name" > "$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"
    command rm -f "$tmp"; rmdir "$3"
  ' _ "$CACHE" "$GH_USER" "$LOCK" >/dev/null 2>&1 &!
}

command rm -f "$CACHE_DIR"/repos-*.txt.tmp.*(N.mm+15)
if [ ! -s "$CACHE" ]; then
  refresh
  echo '{"rerun":1,"items":[{"title":"Building repository cache…","subtitle":"First run only; this can take about a minute. Results appear automatically.","valid":false}]}'
  exit 0
elif [ $(( $(date +%s) - $(stat -f %m "$CACHE") )) -gt $TTL ]; then
  refresh
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
(( ${#words} > 1 )) && [ -n "$sub" ] && words=(${words[1,-2]})
needle="${(j: :)words}"

# gh my [pr|issue]: search pages for open PRs / issues authored by you
my_items='[]'
if [ "${words[1]:l}" = my ]; then
  login=$GH_USER
  if [ -z "$login" ]; then
    login=$(cat "$LOGIN_CACHE" 2>/dev/null)
    if [ -z "$login" ]; then
      login=$(ghx api user --jq .login 2>/dev/null) && [ -n "$login" ] && print -r -- "$login" > "$LOGIN_CACHE"
    fi
  fi
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
