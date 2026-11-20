# alfred-gh

An [Alfred](https://www.alfredapp.com/) workflow that fuzzy-searches the GitHub
repositories you have access to and opens them (or their pull requests, issues,
actions, ...) in your browser. It uses the [GitHub CLI](https://cli.github.com/)
for authentication, so there is no token to paste into Alfred.

> Not affiliated with, endorsed by, or sponsored by GitHub, Inc.

## Install

Download `alfred-gh.alfredworkflow` from the
[Releases](https://github.com/motchang/alfred-gh/releases) page and open it.

## Requirements

- Alfred with the Powerpack
- [`gh`](https://cli.github.com/), logged in (`gh auth login`)
- [`jq`](https://jqlang.github.io/jq/)
- zsh (built into macOS)

`gh` and `jq` are looked up in `/opt/homebrew/bin`, `/usr/local/bin`, then `PATH`.

## Usage

| Input | Opens |
| --- | --- |
| `gh <query>` | `https://github.com/<owner>/<repo>` |
| `gh <query> pr` (`pull`, `pulls`, `prs`) | `.../pulls` |
| `gh <query> issues` (`issue`) | `.../issues` |
| `gh <query> actions` (`action`) | `.../actions` |
| `gh <query> wiki` | `.../wiki` |
| `gh <query> settings` (`setting`) | `.../settings` |
| `gh <query> branches` (`branch`) | `.../branches` |
| `gh <query> releases` (`release`) | `.../releases` |
| `gh my` | GitHub searches for your open PRs and issues, above the repo results |
| `gh my pr` / `gh my issues` | only the PR / issue search |

### ⌘+Enter: open pull requests of a repository

Press ⌘+Enter on any repository result (with or without a trailing
`pull`/`issues`/...) to open a second list with that repository's open pull
requests, shown as `#<number> <title>` (with ` (draft)` for drafts). Type to
filter it by number or title; Enter opens the PR.

- `PR_SCOPE=mine` (default): only PRs authored by you (`GH_USER`, or the active
  account's login), found with the search API. The first item opens the
  repository's PR page filtered to `is:pr is:open author:<you>`.
- `PR_SCOPE=all`: the 20 most recently updated open PRs. The first item opens
  `https://github.com/<owner>/<repo>/pulls`.

⌘+Enter on the `gh my` item "My open pull requests" opens the same list for
your open PRs across all repositories (search `is:pr is:open author:<you>`,
20 most recently updated). Each PR shows its `owner/repo` as the subtitle, and
typing also filters by repository. The first item opens the GitHub search.

The list is cached per account, scope and repository for `PR_CACHE_MINUTES`.
Without a cache it is fetched while you wait (up to about 10 seconds); a stale
cache is shown immediately and refreshed in the background. If that refresh
fails, the stale list stays and the first item says `(refresh failed: …)`.
Requests to GitHub time out after 20 seconds (5 minutes for the repository list).

A trailing word is treated as a destination only when something comes before
it: `gh pull` searches for repositories matching "pull" and opens their root.

If the fetch fails (gh missing, not logged in, `GH_USER` not logged in to gh),
the error is shown with a hint; the next keystroke retries.

Repositories come from `/user/repos` with
`affiliation=owner,collaborator,organization_member`.

### How matching works

The query (spaces removed, case-insensitive) matches a repository when its
characters appear in order in `owner/name`, so `bwcore` matches `bewell-core`.
Matches are ranked:

1. repository name equals the query
2. name starts with the query
3. name contains the query
4. `owner/name` contains the query
5. name contains the query as a subsequence
6. any other subsequence match on `owner/name`

Ties are broken in favor of shorter `owner/name`. The top 30 are shown.

## Configuration

Set these in Alfred under the workflow's **Configure Workflow…** button.

| Variable | Default | Meaning |
| --- | --- | --- |
| `GH_USER` | empty | gh account to use (one of the logins in `gh auth status`). Empty uses gh's active account. When set, the workflow runs `gh` with `GH_TOKEN=$(gh auth token --user "$GH_USER")`, so it works without switching the active account. |
| `CACHE_TTL_HOURS` | `24` | Age after which the repository list is refreshed. |
| `PR_SCOPE` | `mine` | ⌘+Enter lists your open PRs (`mine`) or all open PRs (`all`). Other values mean `mine`. |
| `PR_CACHE_MINUTES` | `5` | Age after which a repository's PR list is refreshed. |

For `gh my`, the author is `GH_USER` if set; otherwise the login of the active
account (`gh api user`), which is cached.

## Cache

The repository list is cached in Alfred's workflow cache directory
(`~/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/com.github.motchang.alfred-gh/`),
one file per account (`repos-<GH_USER>.txt`, or `repos-active.txt`). PR lists
for ⌘+Enter are stored as `prs-<account>-<scope>-<owner>__<repo>.json`, and
your PRs across repositories as `prs-<account>-my-<login>.json`.

- On the first run there is no cache: the workflow shows "Building repository
  cache…" and fetches in the background; results appear automatically when done.
- When the cache is older than `CACHE_TTL_HOURS`, the old list is shown
  immediately and a background refresh replaces it.
- The fetch runs detached, so typing (which makes Alfred kill the script) does
  not abort it.

To force a refresh, delete the cache files.

## Build

```sh
make                 # dist/alfred-gh.alfredworkflow
make VERSION=1.2.3   # stamp the version into info.plist
make lint
make test            # offline smoke tests with fixtures; gh is stubbed, no network
```

CI runs `make lint test build` on macOS for every push and pull request.

Pushing a `v*` tag builds the workflow and publishes a GitHub Release.

## License

MIT. See [LICENSE](LICENSE).

The icon (`src/icon.png`) is derived from the `repo` icon of
[Primer Octicons](https://github.com/primer/octicons) (MIT, see
[LICENSE-octicons](LICENSE-octicons)).
