#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/.." && pwd -P)"

fail() {
  printf 'Provisioning behavior test failed: %s\n' "$1" >&2
  exit 1
}

source_git_root="$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "tests must run from an independently extracted Git repository."
source_git_root="$(cd "$source_git_root" && pwd -P)"

if [[ "$source_git_root" != "$source_root" ]]; then
  fail "refusing to run staged scaffold tests inside another repository. Export the scaffold into an independent repository first."
fi

for required_command in git jq mise script; do
  command -v "$required_command" >/dev/null 2>&1 ||
    fail "required test command '$required_command' is not installed."
done

test_workspace="$(mktemp -d "${TMPDIR:-/tmp}/ai-assisted-sdlc-provision-tests.XXXXXX")"
trap 'rm -rf "$test_workspace"' EXIT
trap 'exit 130' HUP INT TERM

fake_bin="$test_workspace/fake-bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

state_file="${FAKE_GH_STATE:?}"
mutation_log="${FAKE_MUTATION_LOG:?}"

write_state() {
  local filter="$1"
  shift
  local temporary_state
  temporary_state="$(mktemp "${state_file}.XXXXXX")"
  jq "$filter" "$@" "$state_file" >"$temporary_state"
  mv "$temporary_state" "$state_file"
}

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi

if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
  jq -r '.repository' "$state_file"
  exit 0
fi

if [[ "${1:-}" == "label" && "${2:-}" == "list" ]]; then
  jq -c '.labels' "$state_file"
  exit 0
fi

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  label_name="$3"
  label_color=""
  label_description=""
  force="false"
  shift 3
  while (($#)); do
    case "$1" in
      --color)
        label_color="$2"
        shift 2
        ;;
      --description)
        label_description="$2"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "$force" == "true" ]]; then
    printf 'github:label:update:%s\n' "$label_name" >>"$mutation_log"
  else
    printf 'github:label:create:%s\n' "$label_name" >>"$mutation_log"
  fi

  if [[ "${FAKE_SKIP_LABEL_PERSISTENCE:-}" != "$label_name" ]]; then
    write_state \
      'del(.labels[] | select(.name == $name)) | .labels += [{name: $name, color: $color, description: $description}]' \
      --arg name "$label_name" \
      --arg color "$label_color" \
      --arg description "$label_description"
  fi
  exit 0
fi

if [[ "${1:-}" != "api" ]]; then
  printf 'Unexpected fake gh invocation: %s\n' "$*" >&2
  exit 91
fi

shift
method="GET"
endpoint=""
input_file=""
slurp="false"
while (($#)); do
  case "$1" in
    --method)
      method="$2"
      shift 2
      ;;
    --input)
      input_file="$2"
      shift 2
      ;;
    --header | -H)
      shift 2
      ;;
    --paginate)
      shift
      ;;
    --slurp)
      slurp="true"
      shift
      ;;
    *)
      if [[ -z "$endpoint" ]]; then
        endpoint="$1"
      fi
      shift
      ;;
  esac
done
endpoint="${endpoint%%\?*}"

case "$method:$endpoint" in
  GET:repos/*/git/ref/heads/main)
    jq -e '.branches.main == true' "$state_file" >/dev/null || exit 1
    printf '{"object":{"sha":"main-sha"}}\n'
    ;;
  GET:repos/*/git/ref/heads/dev)
    jq -e '.branches.dev == true' "$state_file" >/dev/null || exit 1
    printf '{"object":{"sha":"main-sha"}}\n'
    ;;
  GET:repos/*/rulesets)
    if [[ "$slurp" == "true" ]]; then
      jq -c '[[.rulesets[] | {id, name, target, enforcement}]]' "$state_file"
    else
      jq -c '[.rulesets[] | {id, name, target, enforcement}]' "$state_file"
    fi
    ;;
  GET:repos/*/rulesets/*)
    ruleset_id="${endpoint##*/}"
    jq -ce --argjson id "$ruleset_id" '.rulesets[] | select(.id == $id)' "$state_file"
    ;;
  GET:repos/*)
    jq -c '.settings' "$state_file"
    ;;
  POST:repos/*/git/refs)
    printf 'github:branch:create:dev\n' >>"$mutation_log"
    write_state '.branches.dev = true'
    printf '{"ref":"refs/heads/dev"}\n'
    ;;
  PATCH:repos/*/rulesets/*)
    ruleset_id="${endpoint##*/}"
    printf 'github:ruleset:update:%s\n' "$(jq -r '.name' "$input_file")" >>"$mutation_log"
    temporary_payload="$(mktemp "${state_file}.payload.XXXXXX")"
    jq --argjson id "$ruleset_id" '. + {id: $id}' "$input_file" >"$temporary_payload"
    write_state \
      'del(.rulesets[] | select(.id == $id)) | .rulesets += [$payload[0]]' \
      --argjson id "$ruleset_id" \
      --slurpfile payload "$temporary_payload"
    rm -f "$temporary_payload"
    ;;
  POST:repos/*/rulesets)
    ruleset_name="$(jq -r '.name' "$input_file")"
    printf 'github:ruleset:create:%s\n' "$ruleset_name" >>"$mutation_log"
    next_id="$(jq '[.rulesets[].id] | max // 0 | . + 1' "$state_file")"
    temporary_payload="$(mktemp "${state_file}.payload.XXXXXX")"
    jq --argjson id "$next_id" '. + {id: $id}' "$input_file" >"$temporary_payload"
    write_state '.rulesets += [$payload[0]]' --slurpfile payload "$temporary_payload"
    rm -f "$temporary_payload"
    ;;
  PATCH:repos/*)
    printf 'github:repository:update\n' >>"$mutation_log"
    write_state '.settings = (.settings * $payload[0])' --slurpfile payload "$input_file"
    ;;
  *)
    printf 'Unexpected fake gh api invocation: %s %s\n' "$method" "$endpoint" >&2
    exit 92
    ;;
esac
FAKE_GH
chmod +x "$fake_bin/gh"

cat >"$fake_bin/railway" <<'FAKE_RAILWAY'
#!/usr/bin/env bash
set -euo pipefail

state_file="${FAKE_RAILWAY_STATE:?}"
mutation_log="${FAKE_MUTATION_LOG:?}"

write_state() {
  local filter="$1"
  shift
  local temporary_state
  temporary_state="$(mktemp "${state_file}.XXXXXX")"
  jq "$filter" "$@" "$state_file" >"$temporary_state"
  mv "$temporary_state" "$state_file"
}

if [[ "${1:-}" == "whoami" && "${2:-}" == "--json" ]]; then
  printf '{"id":"owner-id","name":"Repository Owner","workspaces":[{"id":"workspace-id","name":"Personal Workspace"},{"id":"other-workspace-id","name":"Other Workspace"}]}\n'
  exit 0
fi

if [[ "${1:-}" == "init" ]]; then
  project_name=""
  workspace_id=""
  shift
  while (($#)); do
    case "$1" in
      --name)
        project_name="$2"
        shift 2
        ;;
      --workspace)
        workspace_id="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  [[ -n "$project_name" && -n "$workspace_id" ]] || exit 93
  printf 'railway:project:create:%s:%s\n' "$workspace_id" "$project_name" >>"$mutation_log"
  write_state \
    '.projects += [{id: "railway-project", name: $name, workspaceId: $workspace_id, buckets: {edges: []}, services: {edges: []}, environments: {edges: [{node: {id: "production-environment", name: "production", volumeInstances: {edges: []}, variables: {}}}]}}]' \
    --arg name "$project_name" \
    --arg workspace_id "$workspace_id"
  printf '{"id":"railway-project","name":"%s","workspaceId":"%s"}\n' "$project_name" "$workspace_id"
  exit 0
fi

if [[ "${1:-}" != "api" ]]; then
  printf 'Unexpected fake railway invocation: %s\n' "$*" >&2
  exit 93
fi

query="${2:-}"
variables='{}'
if [[ "$query" == *"variables("* ]]; then
  printf 'Provisioning attempted to retrieve Railway variable values.\n' >&2
  exit 94
fi
shift 2
while (($#)); do
  case "$1" in
    --variables)
      variables="$2"
      shift 2
      ;;
    --compact)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

case "$query" in
  *"query ProvisionProjects"*)
    after="$(jq -r '.after // "0"' <<<"$variables")"
    jq -c --argjson start "$after" '
      .projects as $items |
      ($items[$start:($start + 1)]) as $page |
      ($start + ($page | length)) as $next |
      {data: {projects: {
        edges: [range(0; $page | length) as $offset | {cursor: (($start + $offset + 1) | tostring), node: $page[$offset]}],
        pageInfo: {hasNextPage: ($next < ($items | length)), endCursor: ($next | tostring)}
      }}}
    ' "$state_file"
    ;;
  *"query ProvisionProjectEnvironments"* | *"query ProvisionProjectServices"* | *"query ProvisionProjectBuckets"*)
    case "$query" in
      *"query ProvisionProjectEnvironments"*) connection="environments" ;;
      *"query ProvisionProjectServices"*) connection="services" ;;
      *) connection="buckets" ;;
    esac
    project_id="$(jq -r '.id' <<<"$variables")"
    after="$(jq -r '.after // "0"' <<<"$variables")"
    jq -ce --arg id "$project_id" --arg connection "$connection" --argjson start "$after" '
      (.projects[] | select(.id == $id)) as $project |
      ([$project[$connection].edges[].node]) as $items |
      ($items[$start:($start + 1)]) as $page |
      ($start + ($page | length)) as $next |
      {data: {project: ({id: $project.id} + {($connection): {
        edges: [range(0; $page | length) as $offset | {cursor: (($start + $offset + 1) | tostring), node: $page[$offset]}],
        pageInfo: {hasNextPage: ($next < ($items | length)), endCursor: ($next | tostring)}
      }})}}
    ' "$state_file"
    ;;
  *"query ProvisionProjectIdentity"*)
    project_id="$(jq -r '.id' <<<"$variables")"
    jq -ce --arg id "$project_id" \
      '{data: {project: (.projects[] | select(.id == $id) | {id, name, workspaceId})}}' "$state_file"
    ;;
  *"query ProvisionEnvironmentResources"*)
    project_id="$(jq -r '.projectId' <<<"$variables")"
    environment_id="$(jq -r '.environmentId' <<<"$variables")"
    after="$(jq -r '.after // "0"' <<<"$variables")"
    jq -ce --arg project_id "$project_id" --arg environment_id "$environment_id" --argjson start "$after" \
      '{
        data: {
          environment: (
            .projects[] |
            select(.id == $project_id) |
            .environments.edges[].node |
            select(.id == $environment_id) |
            . as $environment |
            ([$environment.volumeInstances.edges[].node]) as $items |
            ($items[$start:($start + 1)]) as $page |
            ($start + ($page | length)) as $next |
            {id, volumeInstances: {
              edges: [range(0; $page | length) as $offset | {cursor: (($start + $offset + 1) | tostring), node: $page[$offset]}],
              pageInfo: {hasNextPage: ($next < ($items | length)), endCursor: ($next | tostring)}
            }}
          )
        }
      }' "$state_file"
    ;;
  *"mutation ProvisionEnvironmentRename"*)
    environment_id="$(jq -r '.id' <<<"$variables")"
    environment_name="$(jq -r '.input.name' <<<"$variables")"
    printf 'railway:environment:rename:%s\n' "$environment_name" >>"$mutation_log"
    write_state \
      '(.projects[].environments.edges[].node | select(.id == $id)).name = $name' \
      --arg id "$environment_id" \
      --arg name "$environment_name"
    printf '{"data":{"environmentRename":true}}\n'
    ;;
  *"mutation ProvisionEnvironmentCreate"*)
    project_id="$(jq -r '.input.projectId' <<<"$variables")"
    environment_name="$(jq -r '.input.name' <<<"$variables")"
    printf 'railway:environment:create:%s\n' "$environment_name" >>"$mutation_log"
    write_state \
      '(.projects[] | select(.id == $project_id)).environments.edges += [{node: {id: ($name + "-environment"), name: $name, volumeInstances: {edges: []}, variables: {}}}]' \
      --arg project_id "$project_id" \
      --arg name "$environment_name"
    jq -c --arg name "$environment_name" \
      '{data: {environmentCreate: {id: ($name + "-environment"), name: $name}}}' <<<"{}"
    ;;
  *)
    printf 'Unexpected fake railway api query: %s\n' "$query" >&2
    exit 94
    ;;
esac
FAKE_RAILWAY
chmod +x "$fake_bin/railway"

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

assert_json() {
  local file="$1"
  local filter="$2"
  jq -e "$filter" "$file" >/dev/null || fail "expected $filter in $file."
}

new_repository() {
  local name="$1"

  created_repository="$test_workspace/$name"
  mkdir -p "$created_repository/scripts" "$created_repository/.sdlc"
  cp "$source_root/scripts/provision.sh" "$created_repository/scripts/provision.sh"
  cp "$source_root/mise.toml" "$created_repository/mise.toml"
  printf 'repository=octocat/orbit-notes\nrailway=true\n' >"$created_repository/.sdlc/project.conf"
  printf '# Orbit Notes\n' >"$created_repository/README.md"
  git -C "$created_repository" init -q -b main
  git -C "$created_repository" config user.name "Provision Test"
  git -C "$created_repository" config user.email "provision@example.invalid"
  git -C "$created_repository" add .
  git -C "$created_repository" commit -q -m "test: create provision fixture"
  git -C "$created_repository" remote add origin git@github.com:octocat/orbit-notes.git
}

seed_platform_state() {
  github_state="$test_workspace/github-state.json"
  railway_state="$test_workspace/railway-state.json"
  mutation_log="$test_workspace/mutations.log"

  cat >"$github_state" <<'JSON'
{
  "repository": "octocat/orbit-notes",
  "settings": {
    "allow_squash_merge": false,
    "allow_merge_commit": false,
    "allow_rebase_merge": true
  },
  "branches": {"main": true, "dev": false},
  "labels": [
    {"name": "bug", "color": "d73a4a", "description": "Something is not working"},
    {"name": "enhancement", "color": "a2eeef", "description": "New feature or request"}
  ],
  "rulesets": []
}
JSON
  printf '{"projects":[]}\n' >"$railway_state"
  : >"$mutation_log"
}

runner="$test_workspace/run-provision"
status_file="$test_workspace/provision-status"
cat >"$runner" <<'RUNNER'
#!/usr/bin/env bash
set +e
cd "${REPOSITORY_UNDER_TEST:?}" || exit 95
mise run provision
provision_status="$?"
printf '%s\n' "$provision_status" >"${PROVISION_STATUS_FILE:?}"
exit "$provision_status"
RUNNER
chmod +x "$runner"

run_provision_tty() {
  local repository="$1"
  local input="$2"
  local output_file="$3"
  local skip_label="${4:-}"

  rm -f "$status_file"
  if script --version >/dev/null 2>&1; then
    printf '%s' "$input" | env \
      PATH="$fake_bin:$PATH" \
      FAKE_GH_STATE="$github_state" \
      FAKE_RAILWAY_STATE="$railway_state" \
      FAKE_MUTATION_LOG="$mutation_log" \
      FAKE_SKIP_LABEL_PERSISTENCE="$skip_label" \
      REPOSITORY_UNDER_TEST="$repository" \
      PROVISION_STATUS_FILE="$status_file" \
      script -qec "$runner" /dev/null >"$output_file" 2>&1 || true
  else
    printf '%s' "$input" | env \
      PATH="$fake_bin:$PATH" \
      FAKE_GH_STATE="$github_state" \
      FAKE_RAILWAY_STATE="$railway_state" \
      FAKE_MUTATION_LOG="$mutation_log" \
      FAKE_SKIP_LABEL_PERSISTENCE="$skip_label" \
      REPOSITORY_UNDER_TEST="$repository" \
      PROVISION_STATUS_FILE="$status_file" \
      script -q /dev/null "$runner" >"$output_file" 2>&1 || true
  fi

  [[ -f "$status_file" ]] || fail "provisioning did not report an exit status."
  provision_status="$(cat "$status_file")"
}

new_repository "provisioning"
repository="$created_repository"
seed_platform_state

cancelled_output="$test_workspace/cancelled.out"
run_provision_tty "$repository" $'workspace-id\nCANCEL\n' "$cancelled_output"
[[ "$provision_status" == "0" ]] || fail "cancelling the mutation plan failed."
assert_contains "$cancelled_output" "Complete provisioning plan"
assert_contains "$cancelled_output" "Create branch dev from main"
assert_contains "$cancelled_output" "Create Railway project orbit-notes"
assert_contains "$cancelled_output" "Personal Workspace (workspace-id)"
assert_contains "$cancelled_output" "color #d4c5f9"
assert_contains "$cancelled_output" '"allowed_merge_methods"'
assert_contains "$cancelled_output" "Type APPLY to perform this plan"
assert_contains "$cancelled_output" "Provisioning cancelled; nothing was changed."
[[ ! -s "$mutation_log" ]] || fail "cancelling the plan performed a mutation."

noninteractive_output="$test_workspace/noninteractive.out"
if printf 'APPLY\n' | (
  cd "$repository"
  PATH="$fake_bin:$PATH" \
    FAKE_GH_STATE="$github_state" \
    FAKE_RAILWAY_STATE="$railway_state" \
    FAKE_MUTATION_LOG="$mutation_log" \
    mise run provision
) >"$noninteractive_output" 2>&1; then
  fail "provisioning accepted non-interactive input."
fi
assert_contains "$noninteractive_output" "interactive terminal"
[[ ! -s "$mutation_log" ]] || fail "the non-interactive refusal performed a mutation."

applied_output="$test_workspace/applied.out"
run_provision_tty "$repository" $'workspace-id\nAPPLY\n' "$applied_output"
[[ "$provision_status" == "0" ]] || fail "applying the mutation plan failed."
assert_contains "$applied_output" "Provisioning verified successfully."
assert_contains "$mutation_log" "github:branch:create:dev"
assert_contains "$mutation_log" "github:repository:update"
assert_contains "$mutation_log" "github:label:create:needs-triage"
assert_contains "$mutation_log" "github:label:create:wayfinder:task"
assert_contains "$mutation_log" "github:ruleset:create:Release train: dev"
assert_contains "$mutation_log" "github:ruleset:create:Release train: main"
assert_contains "$mutation_log" "railway:project:create:workspace-id:orbit-notes"
assert_contains "$mutation_log" "railway:environment:rename:prod"
assert_contains "$mutation_log" "railway:environment:create:dev"
assert_not_contains "$mutation_log" "railway:service"
assert_not_contains "$mutation_log" "railway:database"
assert_not_contains "$mutation_log" "railway:volume"
assert_json "$github_state" '.branches.dev == true'
assert_json "$github_state" '[.labels[].name] | length == 12 and contains(["bug", "enhancement", "needs-triage", "needs-info", "ready-for-agent", "ready-for-human", "wontfix", "wayfinder:map", "wayfinder:research", "wayfinder:prototype", "wayfinder:grilling", "wayfinder:task"])'
assert_json "$github_state" '.rulesets | length == 2'
assert_json "$railway_state" '.projects | length == 1'
assert_json "$railway_state" '.projects[0].name == "orbit-notes"'
assert_json "$railway_state" '.projects[0].workspaceId == "workspace-id"'
assert_json "$railway_state" '[.projects[0].environments.edges[].node.name] | sort == ["dev", "prod"]'
assert_json "$railway_state" '.projects[0].services.edges | length == 0'
assert_json "$railway_state" '.projects[0].buckets.edges | length == 0'

wrong_project_output="$test_workspace/wrong-project.out"
: >"$mutation_log"
run_provision_tty "$repository" $'workspace-id\nwrong-project-id\n' "$wrong_project_output"
[[ "$provision_status" != "0" ]] || fail "an unconfirmed Railway project ID was accepted."
assert_contains "$wrong_project_output" "Railway project ID was not confirmed"
[[ ! -s "$mutation_log" ]] || fail "project-ID refusal performed a mutation."

# Simulate an interruption after most mutations were applied. A retry should
# fill only the missing label and environment without duplicating existing state.
temporary_state="$(mktemp "${github_state}.XXXXXX")"
jq 'del(.labels[] | select(.name == "ready-for-human"))' "$github_state" >"$temporary_state"
mv "$temporary_state" "$github_state"
temporary_state="$(mktemp "${railway_state}.XXXXXX")"
jq 'del(.projects[0].environments.edges[] | select(.node.name == "dev"))' "$railway_state" >"$temporary_state"
mv "$temporary_state" "$railway_state"
: >"$mutation_log"

retry_output="$test_workspace/retry.out"
run_provision_tty "$repository" $'workspace-id\nrailway-project\nAPPLY\n' "$retry_output"
[[ "$provision_status" == "0" ]] || fail "retrying a partial apply failed."
[[ "$(wc -l <"$mutation_log" | tr -d ' ')" == "2" ]] ||
  fail "retry performed mutations beyond the two missing resources."
assert_contains "$mutation_log" "github:label:create:ready-for-human"
assert_contains "$mutation_log" "railway:environment:create:dev"
assert_json "$github_state" '[.labels[] | select(.name == "ready-for-human")] | length == 1'
assert_json "$railway_state" '[.projects[0].environments.edges[].node.name] | sort == ["dev", "prod"]'

: >"$mutation_log"
rerun_output="$test_workspace/rerun.out"
run_provision_tty "$repository" $'workspace-id\nrailway-project\n' "$rerun_output"
[[ "$provision_status" == "0" ]] || fail "verifying existing state on rerun failed."
assert_contains "$rerun_output" "No mutations are required."
assert_contains "$rerun_output" "Provisioning verified successfully."
[[ ! -s "$mutation_log" ]] || fail "a completed rerun repeated mutations."

# A service on a later Railway connection page is still treated as deferred topology.
clean_railway_state="$(mktemp "${railway_state}.clean.XXXXXX")"
cp "$railway_state" "$clean_railway_state"
temporary_state="$(mktemp "${railway_state}.XXXXXX")"
jq '.projects[0].services.edges += [
  {node: {id: "service-id-1", name: "existing-service-1"}},
  {node: {id: "service-id-2", name: "existing-service-2"}}
]' "$railway_state" >"$temporary_state"
mv "$temporary_state" "$railway_state"
services_output="$test_workspace/services.out"
run_provision_tty "$repository" $'workspace-id\nrailway-project\n' "$services_output"
[[ "$provision_status" != "0" ]] || fail "paginated Railway services were accepted."
assert_contains "$services_output" "already contains services"
[[ ! -s "$mutation_log" ]] || fail "service refusal performed a mutation."
mv "$clean_railway_state" "$railway_state"

# Existing non-secret deferred topology is reported instead of being silently accepted or changed.
temporary_state="$(mktemp "${railway_state}.XXXXXX")"
jq '
  .projects[0].buckets.edges += [
    {node: {id: "bucket-id-1", name: "existing-bucket-1"}},
    {node: {id: "bucket-id-2", name: "existing-bucket-2"}}
  ] |
  (.projects[0].environments.edges[].node | select(.name == "prod")).volumeInstances.edges += [
    {node: {id: "volume-id-1"}},
    {node: {id: "volume-id-2"}}
  ] |
  (.projects[0].environments.edges[].node | select(.name == "prod")).variables.SECRET_VALUE = "must-not-appear"
' \
  "$railway_state" >"$temporary_state"
mv "$temporary_state" "$railway_state"
: >"$mutation_log"
topology_output="$test_workspace/topology.out"
run_provision_tty "$repository" $'workspace-id\nrailway-project\n' "$topology_output"
[[ "$provision_status" != "0" ]] || fail "existing Railway topology was accepted."
assert_contains "$topology_output" "already contains deferred topology"
assert_contains "$topology_output" "2 bucket(s)"
assert_contains "$topology_output" "2 volume(s)"
assert_not_contains "$topology_output" "must-not-appear"
[[ ! -s "$mutation_log" ]] || fail "topology refusal performed a mutation."

# Railway project discovery follows every page before deciding whether creation is safe.
seed_platform_state
temporary_state="$(mktemp "${railway_state}.XXXXXX")"
jq '.projects = [
  {id: "duplicate-1", name: "orbit-notes", workspaceId: "workspace-id"},
  {id: "duplicate-2", name: "orbit-notes", workspaceId: "workspace-id"}
]' "$railway_state" >"$temporary_state"
mv "$temporary_state" "$railway_state"
duplicate_projects_output="$test_workspace/duplicate-projects.out"
run_provision_tty "$repository" $'workspace-id\n' "$duplicate_projects_output"
[[ "$provision_status" != "0" ]] || fail "paginated duplicate Railway projects were accepted."
assert_contains "$duplicate_projects_output" "more than one Railway project"
[[ ! -s "$mutation_log" ]] || fail "duplicate-project refusal performed a mutation."

# A same-named project in another workspace is never reused as the target.
seed_platform_state
temporary_state="$(mktemp "${railway_state}.XXXXXX")"
jq '.projects = [{id: "other-project", name: "orbit-notes", workspaceId: "other-workspace-id"}]' \
  "$railway_state" >"$temporary_state"
mv "$temporary_state" "$railway_state"
other_workspace_output="$test_workspace/other-workspace.out"
run_provision_tty "$repository" $'workspace-id\nCANCEL\n' "$other_workspace_output"
[[ "$provision_status" == "0" ]] || fail "workspace-scoped project discovery failed."
assert_contains "$other_workspace_output" "Create Railway project orbit-notes in workspace Personal Workspace (workspace-id)"
assert_contains "$other_workspace_output" "Provisioning cancelled; nothing was changed."
[[ ! -s "$mutation_log" ]] || fail "workspace-scoped cancellation performed a mutation."

# A differently named release-protection ruleset is detected before another is created.
seed_platform_state
temporary_state="$(mktemp "${github_state}.XXXXXX")"
jq '.rulesets += [{
  id: 99,
  name: "Existing dev protection",
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: {ref_name: {include: ["refs/heads/dev"], exclude: []}},
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "pull_request", parameters: {}},
    {type: "required_status_checks", parameters: {required_status_checks: [{context: "Verify"}]}}
  ]
}]' "$github_state" >"$temporary_state"
mv "$temporary_state" "$github_state"
overlapping_rules_output="$test_workspace/overlapping-rules.out"
run_provision_tty "$repository" $'\n' "$overlapping_rules_output"
[[ "$provision_status" != "0" ]] || fail "overlapping release protection was accepted."
assert_contains "$overlapping_rules_output" "another release-protection ruleset"
assert_contains "$overlapping_rules_output" "Existing dev protection"
[[ ! -s "$mutation_log" ]] || fail "overlapping-rules refusal performed a mutation."

seed_platform_state
verification_failure_output="$test_workspace/verification-failure.out"
run_provision_tty \
  "$repository" \
  $'workspace-id\nAPPLY\n' \
  "$verification_failure_output" \
  "ready-for-human"
[[ "$provision_status" != "0" ]] || fail "read-back drift did not fail provisioning."
assert_contains "$verification_failure_output" "Provisioning failed: read-back verification"
assert_contains "$verification_failure_output" "ready-for-human"

printf 'Provisioning behavior tests passed.\n'
