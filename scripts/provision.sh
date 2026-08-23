#!/usr/bin/env bash
set -euo pipefail

workflow_labels=(
  'needs-triage|d4c5f9|A human or triage agent has not classified the request.'
  'needs-info|fbca04|The request cannot advance without reporter input.'
  'ready-for-agent|0e8a16|A bounded ticket is ready for explicit human-triggered work.'
  'ready-for-human|1d76db|A specification, decision, or result needs human judgment.'
  'wontfix|ffffff|The request will not be pursued.'
  'wayfinder:map|5319e7|A Wayfinder decision map.'
  'wayfinder:research|0075ca|A bounded Wayfinder research task.'
  'wayfinder:prototype|c5def5|A bounded Wayfinder prototype task.'
  'wayfinder:grilling|d93f0b|A bounded Wayfinder grilling task.'
  'wayfinder:task|bfd4f2|A bounded Wayfinder implementation task.'
)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "$script_dir/.." && pwd -P)"
temporary_directory=""
action_tokens=()
action_descriptions=()
verification_failures=()
dev_ruleset_id=""
main_ruleset_id=""
railway_project_id=""
railway_workspace_id=""
railway_workspace_name=""

cleanup() {
  local exit_status="$?"
  trap - EXIT HUP INT TERM
  if [[ -n "$temporary_directory" ]]; then
    rm -rf "$temporary_directory"
  fi
  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'Provisioning failed: %s\n' "$1" >&2
  exit 1
}

if [[ ! -t 0 || ! -t 1 ]]; then
  fail "an interactive terminal is required. Run 'mise run provision' directly so the complete plan can be reviewed and confirmed."
fi

for required_command in git gh jq; do
  command -v "$required_command" >/dev/null 2>&1 ||
    fail "required command '$required_command' is not installed. Follow its official installation guidance, then retry."
done

git_root="$(git -C "$repository_root" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "this directory is not an extracted Git repository. Create, clone, and bootstrap a repository from the template first."
git_root="$(cd "$git_root" && pwd -P)"

if [[ "$git_root" != "$repository_root" ]]; then
  fail "refusing to provision from a scaffold nested inside another repository. Export the scaffold into an independent repository first."
fi

project_config="$repository_root/.sdlc/project.conf"
[[ -f "$project_config" ]] ||
  fail "bootstrap configuration is missing. Run 'mise run bootstrap', review and commit its diff, push main, then retry."

configured_repository=""
railway_intent=""
while IFS='=' read -r config_key config_value; do
  case "$config_key" in
    repository)
      configured_repository="$config_value"
      ;;
    railway)
      railway_intent="$config_value"
      ;;
  esac
done <"$project_config"

[[ "$configured_repository" == */* && "$configured_repository" != */*/* ]] ||
  fail "bootstrap configuration does not contain a valid owner/name repository identity. Rerun bootstrap before provisioning."
[[ "$railway_intent" == "true" || "$railway_intent" == "false" ]] ||
  fail "bootstrap configuration does not contain a valid Railway intent. Rerun bootstrap before provisioning."

origin_url="$(git -C "$repository_root" remote get-url origin 2>/dev/null)" ||
  fail "the origin remote is missing. Provisioning only targets the repository recorded by bootstrap."

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
    fail "origin '$origin_url' is not a GitHub repository."
    ;;
esac
repository_identity="${repository_identity%.git}"
repository_identity="${repository_identity#/}"

if [[ "$(printf '%s' "$repository_identity" | tr '[:upper:]' '[:lower:]')" != \
  "$(printf '%s' "$configured_repository" | tr '[:upper:]' '[:lower:]')" ]]; then
  fail "origin '$repository_identity' does not match bootstrap configuration '$configured_repository'. No platform state was changed."
fi

repository_name="${repository_identity#*/}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/ai-assisted-sdlc-provision.XXXXXX")"

if ! gh auth status >/dev/null 2>&1; then
  fail "GitHub CLI is not authenticated. Run 'gh auth login' yourself, then retry; provisioning never accepts or stores a token."
fi

authenticated_repository="$(
  gh repo view "$repository_identity" --json nameWithOwner --jq .nameWithOwner 2>/dev/null
)" || fail "the authenticated GitHub CLI session cannot read '$repository_identity'. Check repository access, then retry."
if [[ "$(printf '%s' "$authenticated_repository" | tr '[:upper:]' '[:lower:]')" != \
  "$(printf '%s' "$repository_identity" | tr '[:upper:]' '[:lower:]')" ]]; then
  fail "GitHub CLI resolved '$authenticated_repository' instead of '$repository_identity'."
fi

repository_state_file="$temporary_directory/github-repository.json"
gh api "repos/$repository_identity" >"$repository_state_file" 2>"$temporary_directory/github-repository.err" ||
  fail "could not read GitHub repository settings: $(cat "$temporary_directory/github-repository.err")"

main_ref_file="$temporary_directory/github-main-ref.json"
gh api "repos/$repository_identity/git/ref/heads/main" >"$main_ref_file" 2>"$temporary_directory/github-main.err" ||
  fail "remote branch 'main' does not exist. Commit and push the bootstrapped repository before provisioning."
main_sha="$(jq -er '.object.sha' "$main_ref_file")" ||
  fail "GitHub returned an unreadable main branch reference."

dev_exists="false"
if gh api "repos/$repository_identity/git/ref/heads/dev" \
  >"$temporary_directory/github-dev-ref.json" 2>"$temporary_directory/github-dev.err"; then
  dev_exists="true"
fi

desired_repository_settings_file="$temporary_directory/desired-repository-settings.json"
jq -n \
  '{allow_squash_merge: true, allow_merge_commit: true, allow_rebase_merge: false}' \
  >"$desired_repository_settings_file"

current_repository_settings="$(
  jq -Sc '{allow_squash_merge, allow_merge_commit, allow_rebase_merge}' "$repository_state_file"
)"
desired_repository_settings="$(jq -Sc . "$desired_repository_settings_file")"

labels_file="$temporary_directory/github-labels.json"
gh label list --repo "$repository_identity" --limit 1000 --json name,color,description \
  >"$labels_file" 2>"$temporary_directory/github-labels.err" ||
  fail "could not read GitHub labels: $(cat "$temporary_directory/github-labels.err")"
jq -e 'type == "array"' "$labels_file" >/dev/null 2>&1 ||
  fail "GitHub returned an unreadable label list."

original_nonworkflow_labels_file="$temporary_directory/original-nonworkflow-labels.json"
workflow_label_names_file="$temporary_directory/workflow-label-names.json"
printf '%s\n' "${workflow_labels[@]}" | cut -d '|' -f 1 | jq -Rsc 'split("\n")[:-1]' \
  >"$workflow_label_names_file"
jq --slurpfile names "$workflow_label_names_file" \
  '[.[] | select((.name as $name | $names[0] | index($name)) == null)] | sort_by(.name)' \
  "$labels_file" >"$original_nonworkflow_labels_file"

write_ruleset_payload() {
  local branch="$1"
  local allowed_merge_methods="$2"
  local destination="$3"

  jq -n \
    --arg name "Release train: $branch" \
    --arg ref "refs/heads/$branch" \
    --argjson methods "$allowed_merge_methods" \
    '{
      name: $name,
      target: "branch",
      enforcement: "active",
      bypass_actors: [],
      conditions: {ref_name: {include: [$ref], exclude: []}},
      rules: [
        {type: "deletion"},
        {type: "non_fast_forward"},
        {
          type: "pull_request",
          parameters: {
            allowed_merge_methods: $methods,
            dismiss_stale_reviews_on_push: false,
            require_code_owner_review: false,
            require_last_push_approval: false,
            required_approving_review_count: 0,
            required_review_thread_resolution: true
          }
        },
        {
          type: "required_status_checks",
          parameters: {
            do_not_enforce_on_create: false,
            required_status_checks: [{context: "Verify"}],
            strict_required_status_checks_policy: false
          }
        }
      ]
    }' >"$destination"
}

dev_ruleset_file="$temporary_directory/desired-dev-ruleset.json"
main_ruleset_file="$temporary_directory/desired-main-ruleset.json"
write_ruleset_payload "dev" '["squash"]' "$dev_ruleset_file"
write_ruleset_payload "main" '["merge", "squash"]' "$main_ruleset_file"

read_github_ruleset_summaries() {
  local destination="$1"
  local pages_file="${destination%.json}-pages.json"
  local error_file="${destination%.json}.err"

  gh api --paginate --slurp "repos/$repository_identity/rulesets?per_page=100" \
    >"$pages_file" 2>"$error_file" ||
    fail "could not read GitHub rulesets: $(cat "$error_file")"
  jq 'add' "$pages_file" >"$destination"
  jq -e 'type == "array"' "$destination" >/dev/null 2>&1 ||
    fail "GitHub returned an unreadable ruleset list."
}

ruleset_summaries_file="$temporary_directory/github-rulesets.json"
read_github_ruleset_summaries "$ruleset_summaries_file"

ruleset_details_directory="$temporary_directory/github-ruleset-details"
mkdir -p "$ruleset_details_directory"
while IFS= read -r ruleset_id; do
  gh api "repos/$repository_identity/rulesets/$ruleset_id" \
    >"$ruleset_details_directory/$ruleset_id.json" \
    2>"$temporary_directory/github-ruleset-$ruleset_id.err" ||
    fail "could not inspect GitHub ruleset '$ruleset_id': $(cat "$temporary_directory/github-ruleset-$ruleset_id.err")"
done < <(jq -r '.[].id' "$ruleset_summaries_file")

add_action() {
  action_tokens+=("$1")
  action_descriptions+=("$2")
}

normalize_ruleset() {
  local ruleset_file="$1"
  jq -Sc '
    {
      name,
      target,
      enforcement,
      bypass_actors:(.bypass_actors // []),
      conditions:{
        ref_name:{
          include:(.conditions.ref_name.include | sort),
          exclude:(.conditions.ref_name.exclude | sort)
        }
      },
      rules:(
        [.rules[] |
          if .type == "pull_request" then
            {
              type,
              parameters:{
                allowed_merge_methods:(.parameters.allowed_merge_methods | sort),
                dismiss_stale_reviews_on_push:.parameters.dismiss_stale_reviews_on_push,
                require_code_owner_review:.parameters.require_code_owner_review,
                require_last_push_approval:.parameters.require_last_push_approval,
                required_approving_review_count:.parameters.required_approving_review_count,
                required_review_thread_resolution:.parameters.required_review_thread_resolution
              }
            }
          elif .type == "required_status_checks" then
            {
              type,
              parameters:{
                do_not_enforce_on_create:.parameters.do_not_enforce_on_create,
                required_status_checks:(
                  [.parameters.required_status_checks[] | {context}] | sort_by(.context)
                ),
                strict_required_status_checks_policy:.parameters.strict_required_status_checks_policy
              }
            }
          else
            {type}
          end
        ] | sort_by(.type)
      )
    }' "$ruleset_file"
}

ruleset_is_release_protection_for() {
  local ruleset_file="$1"
  local branch="$2"
  local branch_ref="refs/heads/$branch"

  jq -e \
    --arg branch "$branch" \
    --arg branch_ref "$branch_ref" \
    '
      .target == "branch" and
      .enforcement == "active" and
      ((.bypass_actors // []) | length == 0) and
      (
        .conditions.ref_name.include |
        any(. == $branch_ref or . == "~ALL" or ($branch == "main" and . == "~DEFAULT_BRANCH"))
      ) and
      (
        .conditions.ref_name.exclude |
        all(. != $branch_ref and . != "~ALL" and ($branch != "main" or . != "~DEFAULT_BRANCH"))
      ) and
      ([.rules[].type] | contains(["deletion", "non_fast_forward", "pull_request", "required_status_checks"])) and
      any(.rules[]; .type == "required_status_checks" and any(.parameters.required_status_checks[]; .context == "Verify"))
    ' "$ruleset_file" >/dev/null 2>&1
}

inspect_ruleset() {
  local branch="$1"
  local desired_file="$2"
  local name="Release train: $branch"
  local match_count
  local ruleset_id
  local existing_file
  local desired_normalized
  local existing_normalized
  local overlapping_names=()
  local candidate_file
  local candidate_id
  local candidate_name

  match_count="$(jq --arg name "$name" '[.[] | select(.name == $name)] | length' "$ruleset_summaries_file")"
  if [[ "$match_count" -gt 1 ]]; then
    fail "multiple GitHub rulesets are named '$name'. Remove or rename the duplicate manually before retrying."
  fi

  for candidate_file in "$ruleset_details_directory"/*.json; do
    [[ -e "$candidate_file" ]] || continue
    candidate_id="$(jq -er '.id' "$candidate_file")"
    candidate_name="$(jq -er '.name' "$candidate_file")"
    if [[ "$candidate_name" == "$name" ]]; then
      continue
    fi
    if ruleset_is_release_protection_for "$candidate_file" "$branch"; then
      overlapping_names+=("$candidate_name ($candidate_id)")
    fi
  done
  if ((${#overlapping_names[@]} > 0)); then
    fail "GitHub already has another release-protection ruleset targeting '$branch': ${overlapping_names[*]}. Reconcile it manually so provisioning does not create overlapping rules."
  fi
  if [[ "$match_count" == "0" ]]; then
    add_action "github:ruleset:create:$branch" "Create '$name' with no bypass, pull requests, Verify, deletion protection, and force-push protection"
    return
  fi

  ruleset_id="$(jq -er --arg name "$name" '.[] | select(.name == $name) | .id' "$ruleset_summaries_file")"
  existing_file="$ruleset_details_directory/$ruleset_id.json"

  desired_normalized="$(normalize_ruleset "$desired_file")"
  existing_normalized="$(normalize_ruleset "$existing_file")"
  if [[ "$desired_normalized" != "$existing_normalized" ]]; then
    add_action "github:ruleset:update:$branch" "Update '$name' to the protected release-train policy"
  fi

  if [[ "$branch" == "dev" ]]; then
    dev_ruleset_id="$ruleset_id"
  else
    main_ruleset_id="$ruleset_id"
  fi
}

if [[ "$dev_exists" != "true" ]]; then
  add_action "github:branch:create:dev" "Create branch dev from main at $main_sha"
fi
if [[ "$current_repository_settings" != "$desired_repository_settings" ]]; then
  add_action "github:repository:update" "Enable squash and merge commits; disable rebase merges"
fi

for label_definition in "${workflow_labels[@]}"; do
  IFS='|' read -r label_name label_color label_description <<<"$label_definition"
  label_matches="$(jq --arg name "$label_name" '[.[] | select(.name == $name)] | length' "$labels_file")"
  if [[ "$label_matches" -gt 1 ]]; then
    fail "GitHub returned duplicate labels named '$label_name'. Resolve the duplicate manually before retrying."
  fi
  if [[ "$label_matches" == "0" ]]; then
    add_action \
      "github:label:create:$label_name" \
      "Create workflow label $label_name with color #$label_color and description '$label_description'"
    continue
  fi
  current_label="$(
    jq -Sc --arg name "$label_name" \
      '.[] | select(.name == $name) | {color:(.color | ascii_downcase), description:(.description // "")}' \
      "$labels_file"
  )"
  desired_label="$(
    jq -nSc --arg color "$label_color" --arg description "$label_description" \
      '{color:($color | ascii_downcase), description:$description}'
  )"
  if [[ "$current_label" != "$desired_label" ]]; then
    add_action \
      "github:label:update:$label_name" \
      "Update workflow label $label_name to color #$label_color and description '$label_description'"
  fi
done

inspect_ruleset "dev" "$dev_ruleset_file"
inspect_ruleset "main" "$main_ruleset_file"

railway_projects_query="query ProvisionProjects(\$after: String) { projects(first: 100, after: \$after) { edges { cursor node { id name workspaceId } } pageInfo { hasNextPage endCursor } } }"
railway_project_identity_query="query ProvisionProjectIdentity(\$id: String!) { project(id: \$id) { id name workspaceId } }"
railway_project_environments_query="query ProvisionProjectEnvironments(\$id: String!, \$after: String) { project(id: \$id) { id environments(first: 100, after: \$after) { edges { cursor node { id name } } pageInfo { hasNextPage endCursor } } } }"
railway_project_services_query="query ProvisionProjectServices(\$id: String!, \$after: String) { project(id: \$id) { id services(first: 100, after: \$after) { edges { cursor node { id name } } pageInfo { hasNextPage endCursor } } } }"
railway_project_buckets_query="query ProvisionProjectBuckets(\$id: String!, \$after: String) { project(id: \$id) { id buckets(first: 100, after: \$after) { edges { cursor node { id name } } pageInfo { hasNextPage endCursor } } } }"
railway_environment_resources_query="query ProvisionEnvironmentResources(\$projectId: String!, \$environmentId: String!, \$after: String) { environment(id: \$environmentId, projectId: \$projectId) { id volumeInstances(first: 100, after: \$after) { edges { cursor node { id } } pageInfo { hasNextPage endCursor } } } }"
railway_environment_rename_mutation="mutation ProvisionEnvironmentRename(\$id: String!, \$input: EnvironmentRenameInput!) { environmentRename(id: \$id, input: \$input) }"
railway_environment_create_mutation="mutation ProvisionEnvironmentCreate(\$input: EnvironmentCreateInput!) { environmentCreate(input: \$input) { id name } }"

read_railway_projects() {
  local after_cursor=""
  local next_cursor
  local page_file="$temporary_directory/railway-projects-page.json"
  local combined_file="$temporary_directory/railway-projects-edges.json"
  local updated_file="$temporary_directory/railway-projects-edges-updated.json"

  printf '[]\n' >"$combined_file"
  while :; do
    railway api "$railway_projects_query" \
      --variables "$(jq -cn --arg after "$after_cursor" '{after:(if $after == "" then null else $after end)}')" \
      --compact >"$page_file" \
      2>"$temporary_directory/railway-projects.err" ||
      fail "could not read Railway projects with the existing CLI session: $(cat "$temporary_directory/railway-projects.err")"
    if ! jq -e '.data.projects.edges | type == "array"' "$page_file" >/dev/null 2>&1 ||
      ! jq -e '.data.projects.pageInfo.hasNextPage | type == "boolean"' "$page_file" >/dev/null 2>&1; then
      fail "Railway returned an unreadable project list."
    fi
    jq -s '.[0] + .[1].data.projects.edges' "$combined_file" "$page_file" >"$updated_file"
    mv "$updated_file" "$combined_file"
    if [[ "$(jq -r '.data.projects.pageInfo.hasNextPage' "$page_file")" != "true" ]]; then
      break
    fi
    next_cursor="$(jq -er '.data.projects.pageInfo.endCursor' "$page_file")" ||
      fail "Railway project pagination did not return a continuation cursor."
    [[ "$next_cursor" != "$after_cursor" ]] || fail "Railway project pagination returned the same cursor twice."
    after_cursor="$next_cursor"
  done
  jq -n --slurpfile edges "$combined_file" '{data:{projects:{edges:$edges[0]}}}' \
    >"$temporary_directory/railway-projects.json"
}

read_railway_project_connection() {
  local query="$1"
  local connection="$2"
  local project_id="$3"
  local destination="$4"
  local after_cursor=""
  local next_cursor
  local page_file="$temporary_directory/railway-$connection-page.json"
  local updated_file="$temporary_directory/railway-$connection-updated.json"

  printf '[]\n' >"$destination"
  while :; do
    railway api "$query" \
      --variables "$(
        jq -cn --arg id "$project_id" --arg after "$after_cursor" \
          '{id:$id,after:(if $after == "" then null else $after end)}'
      )" \
      --compact >"$page_file" \
      2>"$temporary_directory/railway-$connection.err" ||
      fail "could not read Railway project $connection: $(cat "$temporary_directory/railway-$connection.err")"
    jq -e --arg connection "$connection" \
      '.data.project.id and (.data.project[$connection].edges | type == "array") and (.data.project[$connection].pageInfo.hasNextPage | type == "boolean")' \
      "$page_file" >/dev/null 2>&1 || fail "Railway returned unreadable $connection for project '$repository_name'."
    jq -s --arg connection "$connection" '.[0] + .[1].data.project[$connection].edges' \
      "$destination" "$page_file" >"$updated_file"
    mv "$updated_file" "$destination"
    if [[ "$(jq -r --arg connection "$connection" '.data.project[$connection].pageInfo.hasNextPage' "$page_file")" != "true" ]]; then
      break
    fi
    next_cursor="$(jq -er --arg connection "$connection" '.data.project[$connection].pageInfo.endCursor' "$page_file")" ||
      fail "Railway $connection pagination did not return a continuation cursor."
    [[ "$next_cursor" != "$after_cursor" ]] || fail "Railway $connection pagination returned the same cursor twice."
    after_cursor="$next_cursor"
  done
}

read_railway_project() {
  local project_id="$1"
  local identity_file="$temporary_directory/railway-project-identity.json"
  local environments_file="$temporary_directory/railway-environments.json"
  local services_file="$temporary_directory/railway-services.json"
  local buckets_file="$temporary_directory/railway-buckets.json"

  railway api "$railway_project_identity_query" \
    --variables "$(jq -cn --arg id "$project_id" '{id:$id}')" \
    --compact >"$identity_file" \
    2>"$temporary_directory/railway-project.err" ||
    fail "could not read Railway project '$repository_name': $(cat "$temporary_directory/railway-project.err")"
  jq -e --arg workspace_id "$railway_workspace_id" \
    '.data.project.id and .data.project.name and .data.project.workspaceId == $workspace_id' \
    "$identity_file" >/dev/null 2>&1 ||
    fail "Railway returned unreadable state for project '$repository_name'."
  read_railway_project_connection "$railway_project_environments_query" "environments" "$project_id" "$environments_file"
  read_railway_project_connection "$railway_project_services_query" "services" "$project_id" "$services_file"
  read_railway_project_connection "$railway_project_buckets_query" "buckets" "$project_id" "$buckets_file"
  jq -n \
    --slurpfile identity "$identity_file" \
    --slurpfile environments "$environments_file" \
    --slurpfile services "$services_file" \
    --slurpfile buckets "$buckets_file" \
    '{data:{project:{id:$identity[0].data.project.id,name:$identity[0].data.project.name,workspaceId:$identity[0].data.project.workspaceId,environments:{edges:$environments[0]},services:{edges:$services[0]},buckets:{edges:$buckets[0]}}}}' \
    >"$temporary_directory/railway-project.json"
}

read_railway_environment_resources() {
  local project_id="$1"
  local environment_id="$2"
  local destination="$3"
  local after_cursor=""
  local next_cursor
  local page_file="$temporary_directory/railway-environment-resources-page.json"
  local volumes_file="$temporary_directory/railway-environment-volumes.json"
  local updated_file="$temporary_directory/railway-environment-volumes-updated.json"

  printf '[]\n' >"$volumes_file"
  while :; do
    railway api "$railway_environment_resources_query" \
      --variables "$(
        jq -cn --arg project_id "$project_id" --arg environment_id "$environment_id" --arg after "$after_cursor" \
          '{projectId:$project_id,environmentId:$environment_id,after:(if $after == "" then null else $after end)}'
      )" \
      --compact >"$page_file" \
      2>"$temporary_directory/railway-environment-resources.err" ||
      fail "could not inspect Railway environment resources: $(cat "$temporary_directory/railway-environment-resources.err")"
    jq -e '.data.environment.id and (.data.environment.volumeInstances.edges | type == "array") and (.data.environment.volumeInstances.pageInfo.hasNextPage | type == "boolean")' \
      "$page_file" >/dev/null 2>&1 || fail "Railway returned unreadable environment resource state."
    jq -s '.[0] + .[1].data.environment.volumeInstances.edges' "$volumes_file" "$page_file" >"$updated_file"
    mv "$updated_file" "$volumes_file"
    if [[ "$(jq -r '.data.environment.volumeInstances.pageInfo.hasNextPage' "$page_file")" != "true" ]]; then
      break
    fi
    next_cursor="$(jq -er '.data.environment.volumeInstances.pageInfo.endCursor' "$page_file")" ||
      fail "Railway volume pagination did not return a continuation cursor."
    [[ "$next_cursor" != "$after_cursor" ]] || fail "Railway volume pagination returned the same cursor twice."
    after_cursor="$next_cursor"
  done
  jq -n --arg environment_id "$environment_id" --slurpfile volumes "$volumes_file" \
    '{environment:{id:$environment_id,volumeInstances:{edges:$volumes[0]}}}' \
    >"$destination"
  jq -e '.environment.id and (.environment.volumeInstances.edges | type == "array")' \
    "$destination" >/dev/null 2>&1 ||
    fail "Railway returned unreadable environment resource state."
}

collect_railway_topology_problems() {
  local project_file="$temporary_directory/railway-project.json"
  local bucket_count
  local environment_id
  local environment_name
  local resources_file
  local volume_count

  railway_topology_problems=()
  bucket_count="$(jq '.data.project.buckets.edges | length' "$project_file")"
  if [[ "$bucket_count" != "0" ]]; then
    railway_topology_problems+=("$bucket_count bucket(s)")
  fi

  while IFS=$'\t' read -r environment_id environment_name; do
    resources_file="$temporary_directory/railway-resources-$environment_id.json"
    read_railway_environment_resources "$railway_project_id" "$environment_id" "$resources_file"
    volume_count="$(jq '.environment.volumeInstances.edges | length' "$resources_file")"
    if [[ "$volume_count" != "0" ]]; then
      railway_topology_problems+=("$volume_count volume(s) in $environment_name")
    fi
  done < <(
    jq -r '.data.project.environments.edges[].node | [.id, .name] | @tsv' "$project_file"
  )
}

inspect_railway_project() {
  local project_file="$temporary_directory/railway-project.json"
  local service_count
  local environment_names
  local unexpected_environments
  local prod_count
  local production_count
  local dev_count

  service_count="$(jq '.data.project.services.edges | length' "$project_file")"
  if [[ "$service_count" != "0" ]]; then
    fail "Railway project '$repository_name' already contains services. Initial provisioning never guesses, changes, or adds application topology."
  fi
  collect_railway_topology_problems
  if ((${#railway_topology_problems[@]} > 0)); then
    fail "Railway project '$repository_name' already contains deferred topology: ${railway_topology_problems[*]}. Initial provisioning will not change or delete it."
  fi

  environment_names="$(jq -c '[.data.project.environments.edges[].node.name]' "$project_file")"
  unexpected_environments="$(
    jq -r '[.data.project.environments.edges[].node.name | select(. != "dev" and . != "prod" and . != "production")] | join(", ")' \
      "$project_file"
  )"
  if [[ -n "$unexpected_environments" ]]; then
    fail "Railway project '$repository_name' has environments outside the minimal plan: $unexpected_environments. Reconcile them manually before retrying."
  fi

  prod_count="$(jq '[.data.project.environments.edges[].node.name | select(. == "prod")] | length' "$project_file")"
  production_count="$(jq '[.data.project.environments.edges[].node.name | select(. == "production")] | length' "$project_file")"
  dev_count="$(jq '[.data.project.environments.edges[].node.name | select(. == "dev")] | length' "$project_file")"

  if [[ "$prod_count" -gt 1 || "$production_count" -gt 1 || "$dev_count" -gt 1 ]]; then
    fail "Railway project '$repository_name' contains duplicate release environments: $environment_names. Reconcile them manually before retrying."
  fi
  if [[ "$prod_count" == "1" && "$production_count" == "1" ]]; then
    fail "Railway project '$repository_name' contains both 'production' and 'prod'. Provisioning will not delete either; reconcile them manually before retrying."
  fi
  if [[ "$prod_count" == "0" && "$production_count" == "1" ]]; then
    add_action "railway:environment:rename:prod" "Rename Railway environment production to prod (main release train)"
  elif [[ "$prod_count" == "0" ]]; then
    add_action "railway:environment:create:prod" "Create empty Railway environment prod (main release train)"
  fi
  if [[ "$dev_count" == "0" ]]; then
    add_action "railway:environment:create:dev" "Create empty Railway environment dev (dev release train)"
  fi
}

if [[ "$railway_intent" == "true" ]]; then
  command -v railway >/dev/null 2>&1 ||
    fail "Railway was selected during bootstrap, but the Railway CLI is not installed. Follow Railway's official agent setup, authenticate with 'railway login', then retry."
  if ! railway whoami --json >"$temporary_directory/railway-whoami.json" \
    2>"$temporary_directory/railway-whoami.err"; then
    fail "Railway CLI is not authenticated. Run 'railway login' yourself, then retry; provisioning never accepts or stores a token."
  fi

  jq -e '.workspaces | type == "array" and length > 0 and all(.[]; (.id | type == "string") and (.name | type == "string"))' \
    "$temporary_directory/railway-whoami.json" >/dev/null 2>&1 ||
    fail "Railway returned no readable workspaces for the authenticated account."
  printf '\nAvailable Railway workspaces:\n'
  jq -r '.workspaces[] | "- \(.name) (\(.id))"' "$temporary_directory/railway-whoami.json"
  printf 'Type the exact Railway workspace ID to target: '
  if ! IFS= read -r railway_workspace_id; then
    fail "input ended before a Railway workspace was selected; no platform state was changed."
  fi
  railway_workspace_matches="$(
    jq --arg id "$railway_workspace_id" '[.workspaces[] | select(.id == $id)] | length' \
      "$temporary_directory/railway-whoami.json"
  )"
  [[ "$railway_workspace_matches" == "1" ]] ||
    fail "the entered Railway workspace ID is not one of the authenticated account's workspaces; no platform state was changed."
  railway_workspace_name="$(
    jq -er --arg id "$railway_workspace_id" '.workspaces[] | select(.id == $id) | .name' \
      "$temporary_directory/railway-whoami.json"
  )"

  read_railway_projects
  railway_project_matches="$(
    jq --arg name "$repository_name" --arg workspace_id "$railway_workspace_id" \
      '[.data.projects.edges[].node | select(.name == $name and .workspaceId == $workspace_id)] | length' \
      "$temporary_directory/railway-projects.json"
  )"
  if [[ "$railway_project_matches" -gt 1 ]]; then
    fail "more than one Railway project is named '$repository_name' in workspace '$railway_workspace_name' ($railway_workspace_id). Provisioning cannot choose safely; rename or remove duplicates manually."
  fi
  if [[ "$railway_project_matches" == "0" ]]; then
    add_action "railway:project:create" "Create Railway project $repository_name in workspace $railway_workspace_name ($railway_workspace_id) with no application services or data resources"
    add_action "railway:environment:rename:prod" "Rename its initial production environment to prod (main release train)"
    add_action "railway:environment:create:dev" "Create empty Railway environment dev (dev release train)"
  else
    railway_project_id="$(
      jq -er --arg name "$repository_name" --arg workspace_id "$railway_workspace_id" \
        '.data.projects.edges[].node | select(.name == $name and .workspaceId == $workspace_id) | .id' \
        "$temporary_directory/railway-projects.json"
    )"
    printf "Selected existing Railway project %s (%s) in workspace %s (%s).\n" \
      "$repository_name" "$railway_project_id" "$railway_workspace_name" "$railway_workspace_id"
    printf 'Inspect that project in Railway, confirm it has no shared variables, then type the exact project ID to continue: '
    if ! IFS= read -r confirmed_railway_project_id; then
      fail "input ended before the existing Railway project was confirmed; no platform state was changed."
    fi
    [[ "$confirmed_railway_project_id" == "$railway_project_id" ]] ||
      fail "the Railway project ID was not confirmed; no platform state was changed."
    read_railway_project "$railway_project_id"
    inspect_railway_project
  fi
fi

printf '\nComplete provisioning plan for %s\n' "$repository_identity"
printf '%s\n' '------------------------------------------------------------'
if [[ "$railway_intent" == "true" ]]; then
  printf 'Railway target: workspace %s (%s)' "$railway_workspace_name" "$railway_workspace_id"
  if [[ -n "$railway_project_id" ]]; then
    printf ', project %s (%s)' "$repository_name" "$railway_project_id"
  fi
  printf '\n'
fi
if ((${#action_tokens[@]} == 0)); then
  printf 'No mutations are required. Existing state will be read back and verified.\n'
else
  for action_index in "${!action_descriptions[@]}"; do
    printf '%2d. %s\n' "$((action_index + 1))" "${action_descriptions[$action_index]}"
  done
fi

action_is_planned() {
  local requested_action="$1"
  local planned_action
  for planned_action in "${action_tokens[@]}"; do
    if [[ "$planned_action" == "$requested_action" ]]; then
      return 0
    fi
  done
  return 1
}

if action_is_planned "github:ruleset:create:dev" || action_is_planned "github:ruleset:update:dev"; then
  printf '\nExact GitHub ruleset payload for dev:\n'
  jq . "$dev_ruleset_file"
fi
if action_is_planned "github:ruleset:create:main" || action_is_planned "github:ruleset:update:main"; then
  printf '\nExact GitHub ruleset payload for main:\n'
  jq . "$main_ruleset_file"
fi
printf '\nSafety boundaries:\n'
printf '%s\n' '- Existing GitHub labels not managed by this workflow are preserved.'
printf '%s\n' '- No tokens, credentials, environment values, or production data are written.'
if [[ "$railway_intent" == "true" ]]; then
  printf '%s\n' '- Railway stops at one repository-named project and empty dev/prod environments.'
  printf '%s\n' '- No services, databases, storage, domains, variables, regions, scaling, or migrations are created.'
  printf '%s\n' '- Existing shared variables are confirmed by the human in Railway; provisioning never retrieves their secret values.'
else
  printf '%s\n' '- Railway was not selected during bootstrap and will not be contacted.'
fi

if ((${#action_tokens[@]} > 0)); then
  printf '\nType APPLY to perform this plan, or anything else to cancel: '
  if ! IFS= read -r confirmation; then
    fail "input ended before confirmation; nothing was changed."
  fi
  if [[ "$confirmation" != "APPLY" ]]; then
    printf 'Provisioning cancelled; nothing was changed.\n'
    exit 0
  fi
fi

label_definition_for() {
  local requested_name="$1"
  local label_definition
  for label_definition in "${workflow_labels[@]}"; do
    if [[ "${label_definition%%|*}" == "$requested_name" ]]; then
      printf '%s\n' "$label_definition"
      return 0
    fi
  done
  return 1
}

refresh_railway_project_id() {
  read_railway_projects
  railway_project_id="$(
    jq -er --arg name "$repository_name" --arg workspace_id "$railway_workspace_id" \
      '.data.projects.edges[].node | select(.name == $name and .workspaceId == $workspace_id) | .id' \
      "$temporary_directory/railway-projects.json"
  )" || fail "Railway project '$repository_name' was not visible after creation. Retry provisioning; existing-state detection will continue safely."
}

for action_token in "${action_tokens[@]}"; do
  case "$action_token" in
    github:branch:create:dev)
      jq -n --arg sha "$main_sha" '{ref:"refs/heads/dev", sha:$sha}' \
        >"$temporary_directory/create-dev.json"
      gh api --method POST "repos/$repository_identity/git/refs" \
        --input "$temporary_directory/create-dev.json" >/dev/null ||
        fail "could not create GitHub branch 'dev'. Retry after resolving the reported GitHub error."
      ;;
    github:repository:update)
      gh api --method PATCH "repos/$repository_identity" \
        --input "$desired_repository_settings_file" >/dev/null ||
        fail "could not configure GitHub merge behavior. Retry after resolving the reported GitHub error."
      ;;
    github:label:create:* | github:label:update:*)
      label_name="${action_token#github:label:create:}"
      label_name="${label_name#github:label:update:}"
      label_definition="$(label_definition_for "$label_name")" ||
        fail "internal label plan error for '$label_name'."
      IFS='|' read -r _ label_color label_description <<<"$label_definition"
      label_arguments=(
        "$label_name"
        --repo "$repository_identity"
        --color "$label_color"
        --description "$label_description"
      )
      if [[ "$action_token" == github:label:update:* ]]; then
        label_arguments+=(--force)
      fi
      gh label create "${label_arguments[@]}" >/dev/null ||
        fail "could not create or update GitHub label '$label_name'. Retry provisioning after resolving the GitHub error."
      ;;
    github:ruleset:create:* | github:ruleset:update:*)
      branch="${action_token##*:}"
      if [[ "$branch" == "dev" ]]; then
        ruleset_file="$dev_ruleset_file"
        ruleset_id="$dev_ruleset_id"
      else
        ruleset_file="$main_ruleset_file"
        ruleset_id="$main_ruleset_id"
      fi
      if [[ "$action_token" == github:ruleset:create:* ]]; then
        gh api --method POST "repos/$repository_identity/rulesets" \
          --input "$ruleset_file" >/dev/null ||
          fail "could not create GitHub ruleset for '$branch'. Retry provisioning after resolving the GitHub error."
      else
        gh api --method PATCH "repos/$repository_identity/rulesets/$ruleset_id" \
          --input "$ruleset_file" >/dev/null ||
          fail "could not update GitHub ruleset for '$branch'. Retry provisioning after resolving the GitHub error."
      fi
      ;;
    railway:project:create)
      railway init --name "$repository_name" --workspace "$railway_workspace_id" --json \
        >"$temporary_directory/railway-project-create.json" ||
        fail "could not create Railway project '$repository_name'. Retry provisioning; the project list is checked before every apply."
      refresh_railway_project_id
      ;;
    railway:environment:rename:prod)
      if [[ -z "$railway_project_id" ]]; then
        refresh_railway_project_id
      fi
      read_railway_project "$railway_project_id"
      production_environment_id="$(
        jq -er '.data.project.environments.edges[].node | select(.name == "production") | .id' \
          "$temporary_directory/railway-project.json"
      )" || fail "Railway project '$repository_name' has no initial 'production' environment to rename. Retry to inspect the new state safely."
      railway api "$railway_environment_rename_mutation" \
        --variables "$(
          jq -cn --arg id "$production_environment_id" --arg name "prod" \
            '{id:$id,input:{name:$name}}'
        )" \
        --compact >/dev/null ||
        fail "could not rename Railway environment 'production' to 'prod'. Retry provisioning; existing environments are checked before every apply."
      ;;
    railway:environment:create:dev | railway:environment:create:prod)
      environment_name="${action_token##*:}"
      if [[ -z "$railway_project_id" ]]; then
        refresh_railway_project_id
      fi
      railway api "$railway_environment_create_mutation" \
        --variables "$(
          jq -cn --arg project_id "$railway_project_id" --arg name "$environment_name" \
            '{input:{projectId:$project_id,name:$name}}'
        )" \
        --compact >/dev/null ||
        fail "could not create Railway environment '$environment_name'. Retry provisioning; existing environments are checked before every apply."
      ;;
    *)
      fail "internal mutation plan error '$action_token'."
      ;;
  esac
done

add_verification_failure() {
  verification_failures+=("$1")
}

verify_ruleset() {
  local branch="$1"
  local desired_file="$2"
  local summaries_file="$3"
  local name="Release train: $branch"
  local match_count
  local ruleset_id
  local actual_file

  match_count="$(jq --arg name "$name" '[.[] | select(.name == $name)] | length' "$summaries_file")"
  if [[ "$match_count" != "1" ]]; then
    add_verification_failure "expected exactly one GitHub ruleset '$name'"
    return
  fi
  ruleset_id="$(jq -er --arg name "$name" '.[] | select(.name == $name) | .id' "$summaries_file")"
  actual_file="$temporary_directory/verified-$branch-ruleset.json"
  if ! gh api "repos/$repository_identity/rulesets/$ruleset_id" >"$actual_file" 2>/dev/null; then
    add_verification_failure "could not read back GitHub ruleset '$name'"
    return
  fi
  if [[ "$(normalize_ruleset "$desired_file")" != "$(normalize_ruleset "$actual_file")" ]]; then
    add_verification_failure "GitHub ruleset '$name' does not match the protected release-train policy"
  fi
}

verified_repository_file="$temporary_directory/verified-github-repository.json"
if ! gh api "repos/$repository_identity" >"$verified_repository_file" 2>/dev/null; then
  add_verification_failure "could not read back GitHub repository settings"
elif [[ "$(jq -Sc '{allow_squash_merge, allow_merge_commit, allow_rebase_merge}' "$verified_repository_file")" != \
  "$desired_repository_settings" ]]; then
  add_verification_failure "GitHub merge behavior does not enable squash/merge commits while disabling rebase"
fi

for protected_branch in main dev; do
  if ! gh api "repos/$repository_identity/git/ref/heads/$protected_branch" >/dev/null 2>&1; then
    add_verification_failure "GitHub branch '$protected_branch' is missing"
  fi
done

verified_labels_file="$temporary_directory/verified-github-labels.json"
if ! gh label list --repo "$repository_identity" --limit 1000 --json name,color,description \
  >"$verified_labels_file" 2>/dev/null; then
  add_verification_failure "could not read back GitHub labels"
else
  for label_definition in "${workflow_labels[@]}"; do
    IFS='|' read -r label_name label_color label_description <<<"$label_definition"
    verified_label_count="$(
      jq --arg name "$label_name" '[.[] | select(.name == $name)] | length' "$verified_labels_file"
    )"
    if [[ "$verified_label_count" != "1" ]]; then
      add_verification_failure "expected exactly one GitHub label '$label_name'"
      continue
    fi
    verified_label="$(
      jq -Sc --arg name "$label_name" \
        '.[] | select(.name == $name) | {color:(.color | ascii_downcase), description:(.description // "")}' \
        "$verified_labels_file"
    )"
    expected_label="$(
      jq -nSc --arg color "$label_color" --arg description "$label_description" \
        '{color:($color | ascii_downcase), description:$description}'
    )"
    if [[ "$verified_label" != "$expected_label" ]]; then
      add_verification_failure "GitHub label '$label_name' metadata does not match the plan"
    fi
  done

  verified_nonworkflow_labels_file="$temporary_directory/verified-nonworkflow-labels.json"
  jq --slurpfile names "$workflow_label_names_file" \
    '[.[] | select((.name as $name | $names[0] | index($name)) == null)] | sort_by(.name)' \
    "$verified_labels_file" >"$verified_nonworkflow_labels_file"
  if [[ "$(jq -Sc . "$original_nonworkflow_labels_file")" != \
    "$(jq -Sc . "$verified_nonworkflow_labels_file")" ]]; then
    add_verification_failure "GitHub labels outside the managed workflow set were not preserved"
  fi
fi

verified_ruleset_summaries_file="$temporary_directory/verified-github-rulesets.json"
read_github_ruleset_summaries "$verified_ruleset_summaries_file"
verify_ruleset "dev" "$dev_ruleset_file" "$verified_ruleset_summaries_file"
verify_ruleset "main" "$main_ruleset_file" "$verified_ruleset_summaries_file"

if [[ "$railway_intent" == "true" ]]; then
  read_railway_projects
  verified_railway_matches="$(
    jq --arg name "$repository_name" --arg workspace_id "$railway_workspace_id" \
      '[.data.projects.edges[].node | select(.name == $name and .workspaceId == $workspace_id)] | length' \
      "$temporary_directory/railway-projects.json"
  )"
  if [[ "$verified_railway_matches" != "1" ]]; then
    add_verification_failure "expected exactly one Railway project named '$repository_name' in workspace '$railway_workspace_name' ($railway_workspace_id)"
  else
    railway_project_id="$(
      jq -er --arg name "$repository_name" --arg workspace_id "$railway_workspace_id" \
        '.data.projects.edges[].node | select(.name == $name and .workspaceId == $workspace_id) | .id' \
        "$temporary_directory/railway-projects.json"
    )"
    read_railway_project "$railway_project_id"
    if [[ "$(jq '.data.project.services.edges | length' "$temporary_directory/railway-project.json")" != "0" ]]; then
      add_verification_failure "Railway project '$repository_name' contains services, which may include applications, databases, domains, regions, or other deferred topology"
    fi
    collect_railway_topology_problems
    for railway_topology_problem in "${railway_topology_problems[@]}"; do
      add_verification_failure "Railway project '$repository_name' contains deferred topology: $railway_topology_problem"
    done
    verified_environments="$(
      jq -Sc '[.data.project.environments.edges[].node.name] | sort' \
        "$temporary_directory/railway-project.json"
    )"
    if [[ "$verified_environments" != '["dev","prod"]' ]]; then
      add_verification_failure "Railway project '$repository_name' environments are $verified_environments instead of [\"dev\",\"prod\"]"
    fi
  fi
fi

if ((${#verification_failures[@]} > 0)); then
  printf 'Provisioning failed: read-back verification found %d problem(s):\n' \
    "${#verification_failures[@]}" >&2
  for verification_failure in "${verification_failures[@]}"; do
    printf '  - %s\n' "$verification_failure" >&2
  done
  printf 'Fix the reported state or permissions, then rerun provisioning. Existing-state detection makes the retry safe.\n' >&2
  exit 1
fi

printf '\nProvisioning verified successfully.\n'
printf 'GitHub protects dev and main with pull requests and the stable Verify check.\n'
if [[ "$railway_intent" == "true" ]]; then
  printf 'Railway contains one empty project with dev -> dev and prod -> main release intent.\n'
fi
printf 'No credentials, application topology, production data, commit, push, or merge was created.\n'
