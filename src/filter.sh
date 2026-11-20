#!/bin/zsh
# Alfred Script Filter: gh <query> [pull|issues|actions|...]
# Workflow configuration (Alfred "Configure Workflow"):
#   GH_USER          gh account to use; empty = gh's active account
#   CACHE_TTL_HOURS  hours before the repository cache is refreshed (default 24)
#   PR_SCOPE         mine (default) or all; only changes the ⌘ subtitle here
SELF=${0:A}
source "${SELF:h}/lib.sh"
[[ $CACHE_TTL_HOURS == <-> ]] || CACHE_TTL_HOURS=24
[ "$PR_SCOPE" = all ] && cmd_sub="⌘ List open pull requests" || cmd_sub="⌘ List my open pull requests"
CACHE=$CACHE_DIR/repos-$ACCOUNT_KEY.txt
ERROR=$CACHE_DIR/error-$ACCOUNT_KEY.txt
LOCK=$CACHE_DIR/refresh-$ACCOUNT_KEY.lock
TTL=$(( CACHE_TTL_HOURS * 3600 ))
nonempty() { [ -s "$1" ]; }
if [ -n "$ALFRED_GH_FETCH" ]; then
  fetch_to "$CACHE" "$ERROR" 300 nonempty gh api --paginate \
    "/user/repos?per_page=100&affiliation=owner,collaborator,organization_member" \
    --jq ".[].full_name"
  exit 0
fi
# A lock older than 10 minutes is treated as stale
refresh() { start_bg "$LOCK" 600 "$SELF"; }

command rm -f "$CACHE_DIR"/repos-*.txt.(tmp|log).*(N.mm+15)
if [ ! -s "$CACHE" ]; then
  # A failed fetch is shown once; the next keystroke retries
  if [ -s "$ERROR" ] && [ ! -d "$LOCK" ]; then
    ( show_error "$ERROR" repositories ); command rm -f "$ERROR"; exit 0
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

# gh my [pr|issue]: search pages for open PRs involving you / issues authored by you
my_items='[]'
if [ "${words[1]:l}" = my ]; then
  login=$(resolve_login)
  [ -z "$login" ] && fail_item "Could not determine your GitHub login" "Run: gh auth login, or set GH_USER"
  valid_login "$login" || fail_item "Invalid GitHub login: $login" "Check GH_USER"
  my_items=$(jq -n -c --arg u "$login" --arg k "${${sub/pulls/pr}/issues/issue}" '
    [ {k: "pr",    t: "Open pull requests involving me", q: "is:pr is:open involves:\($u)",    ty: "pullrequests"},
      {k: "issue", t: "My open issues",        q: "is:issue state:open author:\($u)", ty: "issues"} ]
    | map(select($k == "" or (.k | startswith($k[0:2]))))
    | map(("https://github.com/search?q=" + (.q | @uri) + "&type=" + .ty) as $url
          | {uid: ("my-" + .k), title: .t, subtitle: $url, arg: $url, quicklookurl: $url,
            mods: {cmd: (if .k == "pr"
              then {arg: "", valid: true, subtitle: "⌘ List open pull requests involving me",
                    variables: {repo: "", pr_mode: "my"}}
              else {valid: false, subtitle: $url} end)}})')
fi

jq -R -s -c --argjson my "$my_items" --arg q "$needle" --arg sub "$sub" --arg cmdsub "$cmd_sub" '
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
      quicklookurl: ("https://github.com/" + .full + $suffix),
      # arg is empty: Alfred would prefill the PR filter query box with it
      mods: {cmd: {arg: "", valid: true, subtitle: $cmdsub,
                   variables: {repo: .full, pr_mode: "repo"}}}
    }) }
  | .items = ($my + .items)
  | if (.items | length) == 0 then {items: [{title: "No matching repository", valid: false}]} else . end
' "$CACHE"
