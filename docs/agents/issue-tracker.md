# Issue tracker: GitHub

Issues and specifications live in this repository's GitHub Issues. Use the GitHub CLI or GitHub API for tracker operations and infer the repository from the current clone.

## Conventions

- Read issues as structured data, including labels and relevant comments.
- Create one issue per implementation ticket and preserve the parent specification with GitHub's native sub-issue relationship where available.
- Use native blocking relationships where available; otherwise record `Blocked by: #<number>` in the issue body.
- Specifications receive `ready-for-human`, never `ready-for-agent`.
- Implementation tickets receive `ready-for-agent` only after scope and dependencies are clear.
- A label never starts an agent. A human selects an issue and explicitly invokes `implement`.

## Pull requests as a triage surface

External pull requests are not a feature-request surface by default. Review pull requests through the repository's ordinary human review process.

## Wayfinding operations

A Wayfinder map is one issue labelled `wayfinder:map`. Decision tickets are native sub-issues, carry the matching `wayfinder:*` work label, and use native blockers where available. The frontier is the first open, unassigned child in map order with no open blocker. Claim work with an assignee; resolve it by recording the decision on the ticket and updating the map's decision summary.

Other issue trackers may replace this file, but GitHub is the only supported default.
