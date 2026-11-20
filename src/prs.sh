#!/bin/zsh
# Alfred Script Filter reached by ⌘+Enter on a repository: lists its open PRs.
# The repository comes from the workflow variable $repo (set by filter.sh's cmd
# mod), or pr_mode=my lists open PRs involving you (author, assignee, mentioned or
# commented) across all repositories; $1 is only the text typed to filter the list, which Alfred handles.
#   PR_SCOPE          mine (default): only PRs authored by you; all: every open PR
#   PR_CACHE_MINUTES  minutes before a repository's PR list is refreshed (default 5)
SELF=${0:A}
source "${SELF:h}/lib.sh"

is_array() { jq -e 'type == "array"' "$1" >/dev/null 2>&1; }
# Background fetch (see start_bg): FETCH_REPO (empty = all repos), FETCH_LOGIN
# (empty = all authors), FETCH_QUAL (author or involves), FETCH_CACHE, FETCH_ERR
if [ -n "$ALFRED_GH_FETCH" ]; then
  pick='{n: .number, t: .title, a: .user.login, u: .updated_at, d: (.draft // false), h: .html_url,
         r: ((.repository_url // "") | sub("^.*/repos/"; "")),
         o: (if ((.user.login // "") | ascii_downcase) == ($me | ascii_downcase) then "author"
             elif any((.assignees // [])[]; (.login // "" | ascii_downcase) == ($me | ascii_downcase)) then "assigned"
             else "involved" end)}'
  if [ -n "$FETCH_LOGIN" ]; then
    # Search API: finds your PRs even when they are not among the 20 most recent
    fetch_to "$FETCH_CACHE" "$FETCH_ERR" 20 is_array gh api -X GET search/issues \
      -f q="${FETCH_REPO:+repo:$FETCH_REPO }is:pr is:open ${FETCH_QUAL:-author}:$FETCH_LOGIN" \
      -f sort=updated -f order=desc -f per_page=20 --jq "\"$FETCH_LOGIN\" as \$me | [.items[] | $pick]"
  else
    fetch_to "$FETCH_CACHE" "$FETCH_ERR" 20 is_array \
      gh api "/repos/$FETCH_REPO/pulls?state=open&per_page=20&sort=updated&direction=desc" \
      --jq "\"\" as \$me | [.[] | $pick]"
  fi
  exit 0
fi

[[ $PR_CACHE_MINUTES == <-> ]] || PR_CACHE_MINUTES=5
repo=${repo:-}
# pr_mode=my: your open PRs in every repository; otherwise those of $repo
if [ "$pr_mode" = my ]; then
  repo=""
else
  # owner/name; no part may start with "." (rules out . and ..)
  part='[A-Za-z0-9_-][A-Za-z0-9._-]*'
  [[ $repo =~ "^$part/$part\$" ]] \
    || fail_item "Invalid repository: ${repo:-(none)}" "Use ⌘+Enter on a repository in the gh filter"
fi
login=""
if [ "$PR_SCOPE" != all ] || [ -z "$repo" ]; then
  login=$(resolve_login)
  [ -z "$login" ] && fail_item "Could not determine your GitHub login" "Run: gh auth login, or set GH_USER"
  valid_login "$login" || fail_item "Invalid GitHub login: $login" "Check GH_USER"
fi
if [ -z "$repo" ]; then
  KEY=$ACCOUNT_KEY-involves-$login
else
  KEY=$ACCOUNT_KEY-${${login:+mine-$login}:-all}-${repo//\//__}
fi
CACHE=$CACHE_DIR/prs-$KEY.json
ERROR=$CACHE_DIR/prs-error-$KEY.txt
LOCK=$CACHE_DIR/prs-refresh-$KEY.lock
TTL=$(( PR_CACHE_MINUTES * 60 ))

# A lock older than a minute is treated as stale (the fetch times out after 20s)
start_fetch() {
  start_bg "$LOCK" 60 "$SELF" FETCH_REPO="$repo" FETCH_LOGIN="$login" \
    FETCH_QUAL=${${repo:+author}:-involves} \
    FETCH_CACHE="$CACHE" FETCH_ERR="$ERROR"
}

command rm -f "$CACHE_DIR"/prs-*.json.(tmp|log).*(N.mm+15)
note=""
if [ ! -e "$CACHE" ]; then
  start_fetch
  # Wait up to ~10s for the fetch (ours or one already running) to finish
  for _ in {1..100}; do
    [ -d "$LOCK" ] || break
    sleep 0.1
  done
  if [ ! -e "$CACHE" ]; then
    if [ -s "$ERROR" ]; then
      ( show_error "$ERROR" "pull requests" ); command rm -f "$ERROR"; exit 0
    fi
    echo '{"rerun":1,"items":[{"title":"Loading pull requests…","valid":false}]}'
    exit 0
  fi
else
  # Keep serving stale data when a refresh failed, but say so
  if [ -s "$ERROR" ] && [ "$ERROR" -nt "$CACHE" ]; then
    read -r _ _ msg < "$ERROR"
    note=" (refresh failed: ${${msg:-unknown error}[1,60]})"
  fi
  a=$(age "$CACHE")
  [ -n "$a" ] && [ "$a" -gt $TTL ] && start_fetch
fi

jq -c --arg repo "$repo" --arg login "$login" --arg note "$note" '
  (if $repo == "" then
     {t: "Open pull requests involving me",
      u: "https://github.com/search?q=\("is:pr is:open involves:\($login)" | @uri)&type=pullrequests",
      e: "No open pull requests involving \($login)"}
   elif $login == "" then
     {t: "Open pull requests page", u: "https://github.com/\($repo)/pulls", e: "No open pull requests"}
   else
     {t: "Open my pull requests in \($repo)",
      u: "https://github.com/\($repo)/pulls?q=\("is:pr is:open author:\($login)" | @uri)",
      e: "No open pull requests by \($login)"}
   end) as $p
  | [ {uid: $p.u, title: $p.t, subtitle: ($p.u + $note), arg: $p.u, quicklookurl: $p.u, match: $p.t} ]
    + (if length == 0 then [{title: $p.e, subtitle: (if $repo == "" then $login else $repo end), valid: false, match: $p.e}]
       else map({
         uid: .h, title: ("#\(.n) \(.t)" + (if .d then " (draft)" else "" end)),
         arg: .h, quicklookurl: .h}
         + if $repo == "" then {subtitle: "\(.r) · \(.o)", match: "\(.n) \(.t) \(.r)"}
           else {subtitle: "", match: "\(.n) \(.t)"} end)
       end)
  | {items: .}
' "$CACHE"
