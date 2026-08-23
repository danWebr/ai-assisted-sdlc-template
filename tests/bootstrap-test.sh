#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/.." && pwd -P)"
fixture_root="$script_dir/fixtures/bootstrap-repository"

fail() {
  printf 'Bootstrap behavior test failed: %s\n' "$1" >&2
  exit 1
}

source_git_root="$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "tests must run from an independently extracted Git repository."
source_git_root="$(cd "$source_git_root" && pwd -P)"

if [[ "$source_git_root" != "$source_root" ]]; then
  fail "refusing to run staged scaffold tests inside another repository. Export the scaffold into an independent repository first."
fi

test_workspace="$(mktemp -d "${TMPDIR:-/tmp}/ai-assisted-sdlc-bootstrap-tests.XXXXXX")"
trap 'rm -rf "$test_workspace"' EXIT
trap 'exit 130' HUP INT TERM

fake_bin="$test_workspace/fake-bin"
mkdir -p "$fake_bin"
for command_name in gh railway; do
  cat >"$fake_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"${CLI_INVOCATION_LOG:?}"
exit 97
EOF
  chmod +x "$fake_bin/$command_name"
done

new_repository() {
  local name="$1"
  local origin_url="${2:-}"

  created_repository="$test_workspace/$name"
  mkdir -p "$created_repository/scripts"
  cp -R "$fixture_root/." "$created_repository/"
  cp "$source_root/scripts/bootstrap.sh" "$created_repository/scripts/bootstrap.sh"
  git -C "$created_repository" init -q -b main
  git -C "$created_repository" config user.name "Bootstrap Test"
  git -C "$created_repository" config user.email "bootstrap@example.invalid"
  git -C "$created_repository" add .
  git -C "$created_repository" commit -q -m "test: create bootstrap fixture"
  if [[ -n "$origin_url" ]]; then
    git -C "$created_repository" remote add origin "$origin_url"
  fi
}

run_bootstrap_successfully() {
  local repository="$1"
  local input="$2"
  local output_file="$3"
  local cli_log="$4"

  if ! printf '%s' "$input" | (
    cd "$repository"
    PATH="$fake_bin:$PATH" CLI_INVOCATION_LOG="$cli_log" mise run bootstrap
  ) >"$output_file" 2>&1; then
    cat "$output_file" >&2
    fail "bootstrap unexpectedly failed in ${repository##*/}."
  fi
}

run_bootstrap_expect_failure() {
  local repository="$1"
  local input="$2"
  local output_file="$3"
  local cli_log="$4"

  if printf '%s' "$input" | (
    cd "$repository"
    PATH="$fake_bin:$PATH" CLI_INVOCATION_LOG="$cli_log" mise run bootstrap
  ) >"$output_file" 2>&1; then
    fail "bootstrap unexpectedly succeeded in ${repository##*/}."
  fi
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file."
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "did not expect '$unexpected' in $file."
  fi
}

assert_clean() {
  local repository="$1"
  if [[ -n "$(git -C "$repository" status --short)" ]]; then
    fail "expected ${repository##*/} to remain unchanged."
  fi
}

file_mode() {
  local file="$1"
  stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file"
}

metadata_input=$'\nOrbit Notes\nA calm place to organize project notes.\ny\n'
personalization_output="$test_workspace/personalization.out"
cli_log="$test_workspace/cli-invocations.log"
new_repository "personalization" "git@github.com:octocat/orbit-notes.git"
personalized_repository="$created_repository"

run_bootstrap_successfully "$personalized_repository" "$metadata_input" "$personalization_output" "$cli_log"

assert_contains "$personalized_repository/README.md" "# Orbit Notes"
assert_contains "$personalized_repository/README.md" "A calm place to organize project notes."
assert_contains "$personalized_repository/README.md" "octocat/orbit-notes"
assert_contains "$personalized_repository/README.md" "mise run provision"
assert_contains "$personalized_repository/README.md" "commit and push the initial main branch manually"
assert_not_contains "$personalized_repository/README.md" "Create a project from this template"
assert_not_contains "$personalized_repository/README.md" "bootstrap:template-onboarding"
assert_not_contains "$personalized_repository/README.md" "AI-assisted SDLC template"
assert_contains "$personalized_repository/AGENTS.md" "# Orbit Notes agent instructions"
assert_contains "$personalized_repository/AGENTS.md" "Railway provisioning: requested"
assert_contains "$personalized_repository/CONTEXT.md" "# Orbit Notes project context"
assert_contains "$personalized_repository/.sdlc/project.conf" "repository=octocat/orbit-notes"
assert_contains "$personalized_repository/.sdlc/project.conf" "railway=true"
[[ "$(file_mode "$personalized_repository/README.md")" == "644" ]] ||
  fail "personalization changed README.md permissions."
[[ "$(file_mode "$personalized_repository/AGENTS.md")" == "644" ]] ||
  fail "personalization changed AGENTS.md permissions."
[[ "$(file_mode "$personalized_repository/CONTEXT.md")" == "644" ]] ||
  fail "personalization changed CONTEXT.md permissions."
[[ "$(file_mode "$personalized_repository/.sdlc/project.conf")" == "644" ]] ||
  fail "project configuration permissions are not reviewable defaults."

if [[ -e "$personalized_repository/docs/template-maintainer-onboarding.md" ]]; then
  fail "template-maintainer onboarding was not removed."
fi
if [[ -z "$(git -C "$personalized_repository" status --short)" ]]; then
  fail "personalization did not leave a reviewable working-tree diff."
fi
if [[ "$(git -C "$personalized_repository" rev-list --count HEAD)" != "1" ]]; then
  fail "bootstrap created a commit."
fi
if [[ "$(git -C "$personalized_repository" remote get-url origin)" != "git@github.com:octocat/orbit-notes.git" ]]; then
  fail "bootstrap changed the repository remote."
fi
if [[ -e "$cli_log" ]]; then
  fail "bootstrap invoked a GitHub or Railway CLI."
fi

first_status="$(git -C "$personalized_repository" status --short)"
first_readme="$(git -C "$personalized_repository" hash-object README.md)"
first_agents="$(git -C "$personalized_repository" hash-object AGENTS.md)"
first_context="$(git -C "$personalized_repository" hash-object CONTEXT.md)"
first_config="$(git -C "$personalized_repository" hash-object .sdlc/project.conf)"

rerun_output="$test_workspace/rerun.out"
run_bootstrap_successfully "$personalized_repository" "$metadata_input" "$rerun_output" "$cli_log"

[[ "$(git -C "$personalized_repository" status --short)" == "$first_status" ]] ||
  fail "a second run changed the reviewable diff."
[[ "$(git -C "$personalized_repository" hash-object README.md)" == "$first_readme" ]] ||
  fail "a second run drifted README.md."
[[ "$(git -C "$personalized_repository" hash-object AGENTS.md)" == "$first_agents" ]] ||
  fail "a second run drifted AGENTS.md."
[[ "$(git -C "$personalized_repository" hash-object CONTEXT.md)" == "$first_context" ]] ||
  fail "a second run drifted CONTEXT.md."
[[ "$(git -C "$personalized_repository" hash-object .sdlc/project.conf)" == "$first_config" ]] ||
  fail "a second run drifted project configuration."

canonical_output="$test_workspace/canonical.out"
new_repository "canonical-source" "https://github.com/danWebr/ai-assisted-sdlc-template.git"
canonical_repository="$created_repository"
run_bootstrap_expect_failure "$canonical_repository" "" "$canonical_output" "$cli_log"
assert_contains "$canonical_output" "refusing to personalize the canonical template source"
assert_clean "$canonical_repository"

missing_origin_output="$test_workspace/missing-origin.out"
new_repository "missing-origin"
missing_origin_repository="$created_repository"
run_bootstrap_expect_failure "$missing_origin_repository" "" "$missing_origin_output" "$cli_log"
assert_contains "$missing_origin_output" "origin remote is missing"
assert_clean "$missing_origin_repository"

interrupted_output="$test_workspace/interrupted.out"
new_repository "interrupted" "https://github.com/octocat/interrupted.git"
interrupted_repository="$created_repository"
run_bootstrap_expect_failure "$interrupted_repository" $'\n' "$interrupted_output" "$cli_log"
assert_contains "$interrupted_output" "input ended before personalization was complete"
assert_clean "$interrupted_repository"

symlink_output="$test_workspace/symlink.out"
symlink_target="$test_workspace/symlink-target"
mkdir -p "$symlink_target"
new_repository "symlink" "https://github.com/octocat/symlink.git"
symlink_repository="$created_repository"
ln -s "$symlink_target" "$symlink_repository/.sdlc"
run_bootstrap_expect_failure "$symlink_repository" "$metadata_input" "$symlink_output" "$cli_log"
assert_contains "$symlink_output" ".sdlc exists but is not a regular, non-symlink directory"
if [[ -e "$symlink_target/project.conf" ]]; then
  fail "bootstrap followed .sdlc outside the repository."
fi

rollback_output="$test_workspace/rollback.out"
new_repository "rollback" "https://github.com/octocat/rollback.git"
rollback_repository="$created_repository"
chmod 0555 "$rollback_repository/docs"
run_bootstrap_expect_failure "$rollback_repository" "$metadata_input" "$rollback_output" "$cli_log"
chmod 0755 "$rollback_repository/docs"
assert_clean "$rollback_repository"
if [[ -e "$rollback_repository/.sdlc" ]]; then
  fail "a failed apply left project configuration behind."
fi

printf 'Bootstrap behavior tests passed.\n'
