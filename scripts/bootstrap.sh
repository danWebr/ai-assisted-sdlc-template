#!/usr/bin/env bash
set -euo pipefail

canonical_repository="danWebr/ai-assisted-sdlc-template"
managed_files=(README.md AGENTS.md CONTEXT.md)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "$script_dir/.." && pwd -P)"
temporary_directory=""
atomic_temporary_file=""
transaction_started="false"
transaction_committed="false"
onboarding_was_present="false"
project_config_was_present="false"
sdlc_directory_was_present="false"

cleanup() {
  local exit_status="$?"
  set +e
  trap - EXIT HUP INT TERM

  if [[ -n "$atomic_temporary_file" ]]; then
    rm -f "$atomic_temporary_file"
  fi

  if [[ "$transaction_started" == "true" && "$transaction_committed" != "true" ]]; then
    for managed_file in "${managed_files[@]}"; do
      cp -p "$temporary_directory/original/$managed_file" "$repository_root/$managed_file"
    done

    if [[ "$onboarding_was_present" == "true" ]]; then
      cp -p \
        "$temporary_directory/original/template-maintainer-onboarding.md" \
        "$repository_root/docs/template-maintainer-onboarding.md"
    else
      rm -f "$repository_root/docs/template-maintainer-onboarding.md"
    fi

    if [[ "$project_config_was_present" == "true" ]]; then
      mkdir -p "$repository_root/.sdlc"
      cp -p "$temporary_directory/original/project.conf" "$repository_root/.sdlc/project.conf"
    elif [[ -d "$repository_root/.sdlc" ]]; then
      rm -f "$repository_root/.sdlc/project.conf"
    fi

    if [[ "$sdlc_directory_was_present" != "true" && -d "$repository_root/.sdlc" ]]; then
      rmdir "$repository_root/.sdlc" 2>/dev/null || true
    fi
  fi

  if [[ -n "$temporary_directory" ]]; then
    rm -rf "$temporary_directory"
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'Bootstrap failed: %s\n' "$1" >&2
  exit 1
}

git_root="$(git -C "$repository_root" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "this directory is not an extracted Git repository. Create and clone a repository from the template first."
git_root="$(cd "$git_root" && pwd -P)"

if [[ "$git_root" != "$repository_root" ]]; then
  fail "refusing to run from a scaffold nested inside another repository. Export the scaffold into an independent repository first."
fi

origin_url="$(git -C "$repository_root" remote get-url origin 2>/dev/null)" ||
  fail "could not infer repository identity because the origin remote is missing. Clone the generated GitHub repository, then rerun bootstrap."

case "$origin_url" in
  https://github.com/*)
    repository_identity="${origin_url#https://github.com/}"
    ;;
  http://github.com/*)
    repository_identity="${origin_url#http://github.com/}"
    ;;
  git@github.com:*)
    repository_identity="${origin_url#git@github.com:}"
    ;;
  ssh://git@github.com/*)
    repository_identity="${origin_url#ssh://git@github.com/}"
    ;;
  *)
    fail "could not infer a GitHub repository identity from origin '$origin_url'."
    ;;
esac

repository_identity="${repository_identity%.git}"
repository_identity="${repository_identity#/}"
repository_owner="${repository_identity%%/*}"
repository_name="${repository_identity#*/}"

if [[ "$repository_identity" != */* || -z "$repository_owner" || -z "$repository_name" || "$repository_name" == */* ]]; then
  fail "could not infer an owner/name repository identity from origin '$origin_url'."
fi

normalized_identity="$(printf '%s' "$repository_identity" | tr '[:upper:]' '[:lower:]')"
normalized_canonical="$(printf '%s' "$canonical_repository" | tr '[:upper:]' '[:lower:]')"

if [[ "$normalized_identity" == "$normalized_canonical" ]]; then
  fail "refusing to personalize the canonical template source '$canonical_repository'. Create a repository from the GitHub template and run bootstrap in that clone."
fi

printf 'Detected repository: %s\n' "$repository_identity"
printf 'Use this repository identity? [Y/n] '
if ! IFS= read -r confirmation; then
  fail "input ended while confirming repository identity; no files were changed."
fi

parse_yes_no() {
  local value="$1"
  local default_value="$2"

  case "$value" in
    y | Y | yes | YES | Yes)
      yes_no_value="true"
      ;;
    n | N | no | NO | No)
      yes_no_value="false"
      ;;
    "")
      yes_no_value="$default_value"
      ;;
    *)
      return 1
      ;;
  esac
}

if ! parse_yes_no "$confirmation" "true"; then
  fail "expected yes or no when confirming repository identity; no files were changed."
fi
if [[ "$yes_no_value" != "true" ]]; then
  fail "repository identity was not confirmed; no files were changed."
fi

prompt_for_nonempty_line() {
  local prompt="$1"
  local value

  printf '%s' "$prompt"
  if ! IFS= read -r value; then
    fail "input ended before personalization was complete; no files were changed."
  fi
  if [[ ! "$value" =~ [^[:space:]] ]]; then
    fail "a non-empty one-line value is required; no files were changed."
  fi
  if [[ "$value" == *"<!-- bootstrap:"* ]]; then
    fail "project metadata cannot contain reserved bootstrap markers; no files were changed."
  fi
  prompt_value="$value"
}

prompt_for_nonempty_line "Project display name: "
project_display_name="$prompt_value"
prompt_for_nonempty_line "One-line project description: "
project_description="$prompt_value"

printf 'Plan to use Railway for this project? [y/N] '
if ! IFS= read -r railway_answer; then
  fail "input ended before Railway intent was recorded; no files were changed."
fi

if ! parse_yes_no "$railway_answer" "false"; then
  fail "expected yes or no for Railway intent; no files were changed."
fi
railway_intent="$yes_no_value"
if [[ "$railway_intent" == "true" ]]; then
  railway_summary="requested"
else
  railway_summary="not requested"
fi

require_single_marker() {
  local file="$1"
  local marker="$2"
  local count

  count="$(grep -Fxc "$marker" "$file" || true)"
  if [[ "$count" != "1" ]]; then
    fail "expected one '$marker' marker in ${file#"$repository_root/"}; no files were changed."
  fi
}

require_optional_marker_pair() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local start_count
  local end_count

  start_count="$(grep -Fxc "$start_marker" "$file" || true)"
  end_count="$(grep -Fxc "$end_marker" "$file" || true)"
  if [[ "$start_count" != "$end_count" || ( "$start_count" != "0" && "$start_count" != "1" ) ]]; then
    fail "expected a complete optional onboarding block in ${file#"$repository_root/"}; no files were changed."
  fi
}

render_managed_block() {
  local source_file="$1"
  local destination_file="$2"
  local replacement_file="$3"

  awk -v replacement_file="$replacement_file" '
    $0 == "<!-- bootstrap:project:start -->" {
      print
      while ((getline replacement_line < replacement_file) > 0) {
        print replacement_line
      }
      close(replacement_file)
      skipping = 1
      next
    }
    $0 == "<!-- bootstrap:project:end -->" {
      skipping = 0
    }
    !skipping { print }
  ' "$source_file" >"$destination_file"
}

remove_template_onboarding() {
  local source_file="$1"
  local destination_file="$2"

  awk '
    $0 == "<!-- bootstrap:template-onboarding:start -->" {
      skipping = 1
      next
    }
    $0 == "<!-- bootstrap:template-onboarding:end -->" {
      skipping = 0
      next
    }
    !skipping { print }
  ' "$source_file" >"$destination_file"
}

for managed_file in "${managed_files[@]}"; do
  if [[ ! -f "$repository_root/$managed_file" || -L "$repository_root/$managed_file" ]]; then
    fail "expected ${managed_file} to be a regular, non-symlink file; no files were changed."
  fi
  require_single_marker "$repository_root/$managed_file" "<!-- bootstrap:project:start -->"
  require_single_marker "$repository_root/$managed_file" "<!-- bootstrap:project:end -->"
done
require_optional_marker_pair \
  "$repository_root/README.md" \
  "<!-- bootstrap:template-onboarding:start -->" \
  "<!-- bootstrap:template-onboarding:end -->"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/ai-assisted-sdlc-bootstrap.XXXXXX")"

if [[ ! -d "$repository_root/docs" || -L "$repository_root/docs" ]]; then
  fail "docs must be a regular, non-symlink directory; no files were changed."
fi
if [[ -e "$repository_root/.sdlc" && ( ! -d "$repository_root/.sdlc" || -L "$repository_root/.sdlc" ) ]]; then
  fail ".sdlc exists but is not a regular, non-symlink directory; no files were changed."
fi
if [[ -e "$repository_root/.sdlc/project.conf" && ( ! -f "$repository_root/.sdlc/project.conf" || -L "$repository_root/.sdlc/project.conf" ) ]]; then
  fail ".sdlc/project.conf exists but is not a regular, non-symlink file; no files were changed."
fi
if [[ -e "$repository_root/docs/template-maintainer-onboarding.md" && ( ! -f "$repository_root/docs/template-maintainer-onboarding.md" || -L "$repository_root/docs/template-maintainer-onboarding.md" ) ]]; then
  fail "template-maintainer onboarding exists but is not a regular, non-symlink file; no files were changed."
fi

cat >"$temporary_directory/readme-project.md" <<EOF
# $project_display_name

$project_description

Repository: [$repository_identity](https://github.com/$repository_identity)

## Complete repository setup

Review the bootstrap diff, then commit and push the initial main branch manually. Run \`mise run provision\` in an interactive terminal, review the complete GitHub and optional Railway mutation plan, and type \`APPLY\` only when it is correct. Provisioning uses existing authenticated CLI sessions and reads back the resulting state.
EOF

cat >"$temporary_directory/agents-project.md" <<EOF
# $project_display_name agent instructions

$project_description

- Repository identity: \`$repository_identity\`
- Railway provisioning: $railway_summary

This file is the canonical portable instruction source for Pi, Codex, and compatible agents. Agent-specific files may import or adapt it but must not duplicate its rules.
EOF

cat >"$temporary_directory/context-project.md" <<EOF
# $project_display_name project context

$project_description

- Repository identity: \`$repository_identity\`
- Railway provisioning: $railway_summary

Product discovery has not happened yet. Use \`grill-with-docs\` to establish the project's ubiquitous language before implementation.
EOF

cat >"$temporary_directory/project.conf" <<EOF
repository=$repository_identity
railway=$railway_intent
EOF

render_managed_block "$repository_root/README.md" "$temporary_directory/README.with-onboarding.md" "$temporary_directory/readme-project.md"
remove_template_onboarding "$temporary_directory/README.with-onboarding.md" "$temporary_directory/README.md"
render_managed_block "$repository_root/AGENTS.md" "$temporary_directory/AGENTS.md" "$temporary_directory/agents-project.md"
render_managed_block "$repository_root/CONTEXT.md" "$temporary_directory/CONTEXT.md" "$temporary_directory/context-project.md"

mkdir -p "$temporary_directory/original"
for managed_file in "${managed_files[@]}"; do
  cp -p "$repository_root/$managed_file" "$temporary_directory/original/$managed_file"
done
if [[ -f "$repository_root/docs/template-maintainer-onboarding.md" ]]; then
  onboarding_was_present="true"
  cp -p \
    "$repository_root/docs/template-maintainer-onboarding.md" \
    "$temporary_directory/original/template-maintainer-onboarding.md"
fi
if [[ -d "$repository_root/.sdlc" ]]; then
  sdlc_directory_was_present="true"
fi
if [[ -f "$repository_root/.sdlc/project.conf" ]]; then
  project_config_was_present="true"
  cp -p "$repository_root/.sdlc/project.conf" "$temporary_directory/original/project.conf"
fi

transaction_started="true"

install_atomically() {
  local source_file="$1"
  local destination_file="$2"

  atomic_temporary_file="$(mktemp "${destination_file}.bootstrap.XXXXXX")"
  if [[ -f "$destination_file" ]]; then
    cp -p "$destination_file" "$atomic_temporary_file"
  else
    chmod 0644 "$atomic_temporary_file"
  fi
  cp "$source_file" "$atomic_temporary_file"
  mv "$atomic_temporary_file" "$destination_file"
  atomic_temporary_file=""
}

for managed_file in "${managed_files[@]}"; do
  install_atomically "$temporary_directory/$managed_file" "$repository_root/$managed_file"
done
mkdir -p "$repository_root/.sdlc"
install_atomically "$temporary_directory/project.conf" "$repository_root/.sdlc/project.conf"
rm -f "$repository_root/docs/template-maintainer-onboarding.md"
transaction_committed="true"

printf '\nBootstrap complete for %s.\n' "$repository_identity"
printf 'No repository, credentials, infrastructure, commit, or push was created.\n'
printf 'Review the uncommitted changes with git diff and git status before committing them manually.\n'
