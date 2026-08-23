#!/usr/bin/env bash
set -euo pipefail

git diff --check

required_files=(
  AGENTS.md
  README.md
  .pi/settings.json
  .github/workflows/verify.yml
  docs/agents/issue-tracker.md
  docs/agents/triage-labels.md
  scripts/bootstrap.sh
  scripts/provision.sh
  tests/bootstrap-test.sh
  tests/provision-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'Missing required scaffold file: %s\n' "$required_file" >&2
    exit 1
  fi
done

while IFS= read -r -d '' tracked_file; do
  if git check-ignore --no-index --quiet "$tracked_file"; then
    printf 'Ignored local or generated file is tracked: %s\n' "$tracked_file" >&2
    exit 1
  fi
done < <(git ls-files -z)
