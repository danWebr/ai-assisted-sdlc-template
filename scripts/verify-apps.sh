#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d apps ]]; then
  exit 0
fi

for app_directory in apps/*; do
  [[ -d "$app_directory" ]] || continue

  if [[ ! -f "$app_directory/mise.toml" ]]; then
    printf 'Deployable app has no local mise contract: %s\n' "$app_directory" >&2
    exit 1
  fi

  (
    cd "$app_directory"
    mise run verify
  )
done
