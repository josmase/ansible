#!/bin/sh
set -eu
set -o pipefail

: "${TOFU_MR_COMMENT_TOKEN:?Missing project-scoped MR comment token}"
: "${CI_MERGE_REQUEST_IID:?Missing merge request ID}"
umask 077
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

{
  printf '### OpenTofu plan: `%s`\n\n' "$TF_STATE_NAME"
  printf 'Commit `%s` · [Plan job](%s)\n\n' "$CI_COMMIT_SHORT_SHA" "$CI_JOB_URL"
  tofu show -json plan.cache | jq -r -f "$CI_PROJECT_DIR/.gitlab/opentofu/plan_summary.jq"
  printf '\nOnly resource actions and addresses are shown; values are omitted.\n'
} > "$tmpdir/body"
jq -n --rawfile body "$tmpdir/body" '{body: $body}' > "$tmpdir/payload.json"
printf 'header = "PRIVATE-TOKEN: %s"\n' "$TOFU_MR_COMMENT_TOKEN" > "$tmpdir/curl.conf"
curl --fail --silent --show-error --config "$tmpdir/curl.conf" \
  --header 'Content-Type: application/json' --request POST \
  --data-binary "@$tmpdir/payload.json" \
  "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests/$CI_MERGE_REQUEST_IID/notes" \
  --output /dev/null
printf 'Posted the OpenTofu plan summary to the merge request.\n'
