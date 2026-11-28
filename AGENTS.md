# AGENTS.md

Conventions for agents (Claude Code, Codex, and others) working in this repository.

## Pull requests

- Once a pull request is ready for review (including one opened as ready from the start), wait for Codex (`chatgpt-codex-connector[bot]`) to finish its code review before reporting the work as done or merging.
- Also confirm that CI (the `build` job of the `CI` workflow, which runs `make lint test build`) has passed.
- Merging into `main` does not publish a release; releases are created by pushing a `v*` tag (`release.yml`). Do not push release tags unless the repository owner asks for it.
- When CI passes and the conditions under "Merging pull requests" below are met, you may merge without waiting for the repository owner's instruction.

## Merging pull requests

Never merge until Codex has finished reviewing the pull request's current head commit.

- Codex leaves a summary comment on the pull request (`<!-- codex-pull-request-review-summary -->`). In its `codex-review-state:v1` JSON, `code_review.status` must be `completed`, `code_review.commit_sha` must match the pull request's current head, and `has_unresolved_findings` must be `false`.
- Codex does not re-review on push. If the head has moved since its last review, comment `@codex review` on the pull request and wait for the new result.
- Codex does not approve. A 👍 reaction from Codex on the pull request means it found nothing.
- Before merging, address every Codex finding (fix it and push), or reply in its thread explaining why it will not be fixed.
