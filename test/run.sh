#!/bin/zsh
# Offline smoke tests for src/filter.sh and src/prs.sh.
# Caches are pre-seeded with fixtures (fresh mtime) and `gh` is stubbed so any
# network call fails the run.
cd "${0:A:h}/.."
FIX=test/fixtures
TMP=$(mktemp -d)
trap 'command rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache"
GH_CALLS=$TMP/gh-calls
# Stub gh. STUB_GH=ok serves fixtures for the PR endpoints (applying --jq like
# gh does), STUB_GH=fail fails them; otherwise any call is recorded as a failure.
cat > "$TMP/bin/gh" <<STUB
#!/bin/zsh
fix=${PWD}/$FIX
if [ "\$STUB_GH" = ok ] || [ "\$STUB_GH" = fail ]; then
  if [ "\$1 \$2" = "auth token" ]; then print stub-token; exit 0; fi
  if [ "\$1" = api ]; then
    [ "\$STUB_GH" = fail ] && { print -u2 "HTTP 404: Not Found"; exit 1; }
    jqx=. file=""
    while (( \$# )); do
      [[ \$1 == q=* ]] && print -r -- "\$1" >> "$TMP/gh-queries"
      case \$1 in
        --jq) jqx=\$2; shift ;;
        search/issues) file=\${file:-\$fix/api-search.json} ;;
        q=is:pr*) file=\$fix/api-search-my.json ;;
        /repos/*/pulls\?*) file=\$fix/api-pulls.json ;;
      esac
      shift
    done
    [ -n "\$file" ] && exec jq -c "\$jqx" "\$file"
  fi
fi
echo "gh \$*" >> "$GH_CALLS"
echo "stub gh: unexpected call: \$*" >&2
exit 99
STUB
chmod +x "$TMP/bin/gh"
export ALFRED_GH_PATH_PREFIX=$TMP/bin alfred_workflow_cache=$TMP/cache GH_USER=tester
unset PR_SCOPE PR_CACHE_MINUTES CACHE_TTL_HOURS repo
cp $FIX/repos.txt "$TMP/cache/repos-tester.txt"
cp $FIX/prs-all.json "$TMP/cache/prs-tester-all-acme__widget-core.json"
cp $FIX/prs-mine.json "$TMP/cache/prs-tester-mine-tester-acme__widget-core.json"
print -r -- '[]' > "$TMP/cache/prs-tester-all-octo__dotfiles.json"
print -r -- '[]' > "$TMP/cache/prs-tester-mine-tester-octo__dotfiles.json"

pass=0 fail=0
# check <name> <json> <jq expression that must be true>
check() {
  if print -r -- "$2" | jq -e "$3" >/dev/null 2>&1; then
    pass=$((pass + 1)); print "ok   $1"
  else
    fail=$((fail + 1)); print "FAIL $1"; print -r -- "     expr: $3"; print -r -- "     out:  $2"
  fi
}
f() { zsh src/filter.sh "$@"; }
p() { zsh src/prs.sh "$@"; }

o=$(f wcore);           check "fuzzy wcore ranks widget-core first" "$o" '.items[0].uid == "acme/widget-core"'
o=$(f "widget-core pull"); check "trailing pull opens /pulls" "$o" '.items[0].arg == "https://github.com/acme/widget-core/pulls"'
o=$(f pull);            check "single word pull keeps root URLs" "$o" '.items[0].arg == "https://github.com/octo/pullman" and all(.items[]; .arg | test("/pulls$") | not)'
o=$(f "my pr");          check "my pr searches involves:GH_USER" "$o" '.items[0] | .title == "Open pull requests involving me" and .arg == "https://github.com/search?q=is%3Apr%20is%3Aopen%20involves%3Atester&type=pullrequests"'
check "my pr cmd mod opens my PR list" "$o" '.items[0].mods.cmd | .valid and .arg == "" and .variables == {repo: "", pr_mode: "my"}'
o=$(f "my issues");     check "my issues has no usable cmd mod" "$o" '.items[0].mods.cmd.valid == false'
for q in '*' '[' 'a\' '"'; do
  o=$(f "$q");          check "special char ${(q)q} gives valid JSON" "$o" '.items | type == "array"'
done
o=$(CACHE_TTL_HOURS=abc f widget); check "non-integer CACHE_TTL_HOURS" "$o" '.items | length > 0'
o=$(f widget-core);     check "cmd mod carries variables.repo, empty arg" "$o" '.items[0].mods.cmd | .valid and .arg == "" and .variables.repo == "acme/widget-core"'
check "cmd subtitle defaults to mine" "$o" '.items[0].mods.cmd.subtitle == "⌘ List my open pull requests"'
o=$(PR_SCOPE=all f widget-core); check "cmd subtitle for PR_SCOPE=all" "$o" '.items[0].mods.cmd.subtitle == "⌘ List open pull requests"'

o=$(repo=acme/widget-core PR_SCOPE=all p)
check "all: first item is pulls page" "$o" '.items[0] | .title == "Open pull requests page" and .arg == "https://github.com/acme/widget-core/pulls"'
check "all: PR items" "$o" '(.items | length) == 3 and .items[1].title == "#42 Add sprocket support" and .items[1].subtitle == "" and .items[1].match == "42 Add sprocket support"'
check "all: draft marked" "$o" '.items[2].title == "#41 WIP: refactor gears (draft)"'
o=$(repo=acme/widget-core p)
check "mine (default): first item is my search" "$o" '.items[0] | .title == "Open my pull requests in acme/widget-core" and (.arg | endswith("/pulls?q=is%3Apr%20is%3Aopen%20author%3Atester"))'
check "mine: PR items" "$o" '(.items | length) == 2 and .items[1].title == "#41 WIP: refactor gears (draft)"'
o=$(repo=acme/widget-core PR_SCOPE=bogus PR_CACHE_MINUTES=x p)
check "unknown PR_SCOPE falls back to mine" "$o" '.items[0].title | startswith("Open my pull requests")'
o=$(repo=octo/dotfiles PR_SCOPE=all p)
check "all: empty list" "$o" '(.items | length) == 2 and .items[1].title == "No open pull requests" and .items[1].valid == false'
o=$(repo=octo/dotfiles p)
check "mine: empty list" "$o" '.items[1].title == "No open pull requests by tester" and .items[1].valid == false'
o=$(repo='acme/../x;y' p)
check "invalid repo is an error item" "$o" '.items[0] | (.title | startswith("Invalid repository")) and .valid == false'
o=$(repo=acme/.github PR_SCOPE=all STUB_GH=ok p)
check "dot-prefixed repo name is accepted" "$o" '.items[0] | .title == "Open pull requests page" and .arg == "https://github.com/acme/.github/pulls"'
for r in acme/. acme/.. ./x ../x .acme/x; do
  o=$(repo=$r p)
  check "repo $r is rejected" "$o" '.items[0] | (.title | startswith("Invalid repository")) and .valid == false'
done
o=$(repo=acme/widget-core GH_USER='bad;user' p)
check "invalid login is an error item" "$o" '.items[0].title | startswith("Invalid GitHub login")'
o=$(p)
check "missing repo is an error item" "$o" '.items[0].valid == false'

# Stale cache with a failed refresh: data stays, header says so
F=$TMP/cache/prs-tester-all-acme__widget-core.json
touch -t 202001010000 "$F"; print -r -- 'api 1 HTTP 500: boom' > "$TMP/cache/prs-error-tester-all-acme__widget-core.txt"
o=$(repo=acme/widget-core PR_SCOPE=all STUB_GH=fail p)
check "stale + failed refresh keeps data, notes failure" "$o" '(.items | length) == 3 and (.items[0].subtitle | endswith("(refresh failed: HTTP 500: boom)"))'

# No cache: fetch through the stub, mapping realistic API responses
o=$(repo=acme/gadget PR_SCOPE=all STUB_GH=ok p)
check "fetch all: maps /pulls response" "$o" '[.items[].title] == ["Open pull requests page", "#7 Speed up gizmo", "#6 Draft: new gizmo API (draft)"] and .items[1].arg == "https://github.com/acme/gadget/pull/7" and .items[1].match == "7 Speed up gizmo"'
check "fetch all: cache written" "$(cat $TMP/cache/prs-tester-all-acme__gadget.json)" 'length == 2'
o=$(repo=acme/gadget STUB_GH=ok p)
check "fetch mine: maps search response" "$o" '[.items[].title] == ["Open my pull requests in acme/gadget", "#6 Draft: new gizmo API (draft)"] and .items[1].subtitle == ""'
check "fetch mine: query uses author:" "$(tail -1 $TMP/gh-queries | jq -R .)" '. == "q=repo:acme/gadget is:pr is:open author:tester"'
o=$(pr_mode=my repo=acme/widget-core PR_SCOPE=all STUB_GH=ok p)
check "fetch my: PRs involving me with roles" "$o" '[.items[] | [.title, .subtitle]] == [["Open pull requests involving me", "https://github.com/search?q=is%3Apr%20is%3Aopen%20involves%3Atester&type=pullrequests"], ["#6 Draft: new gizmo API (draft)", "acme/gadget · author"], ["#3 Fix typo", "octo/dotfiles · assigned"], ["#9 Review wanted", "octo/tools · involved"]] and .items[2].match == "3 Fix typo octo/dotfiles"'
check "fetch my: query uses involves:" "$(tail -1 $TMP/gh-queries | jq -R .)" '. == "q=is:pr is:open involves:tester"'
check "fetch my: cache keyed involves-<login>" "$(cat $TMP/cache/prs-tester-involves-tester.json)" 'length == 3'
print -r -- '[]' > "$TMP/cache/prs-other-involves-other.json"
o=$(pr_mode=my GH_USER=other p)
check "my: empty list" "$o" '.items[1] | .title == "No open pull requests involving other" and .valid == false'
o=$(pr_mode=my GH_USER='bad;user' p)
check "my: invalid login is an error item" "$o" '.items[0].title | startswith("Invalid GitHub login")'
o=$(repo=acme/missing PR_SCOPE=all STUB_GH=fail p)
check "fetch failure with no cache is an error item" "$o" '.items[0] | (.title | startswith("Failed to fetch pull requests (exit 1)")) and .subtitle == "HTTP 404: Not Found" and .valid == false'
o=$(repo=acme/widget-core ALFRED_GH_FETCH= p "ALFRED_GH_FETCH=1 --fetch x y")
check "typed text cannot trigger fetch mode" "$o" '.items[0].title == "Open my pull requests in acme/widget-core"'

if [ -s "$GH_CALLS" ]; then
  fail=$((fail + 1)); print "FAIL gh was called:"; cat "$GH_CALLS"
else
  pass=$((pass + 1)); print "ok   no gh calls"
fi
print "$pass passed, $fail failed"
(( fail == 0 ))
