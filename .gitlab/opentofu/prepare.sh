#!/bin/sh
set -eu

apk add --no-cache ca-certificates curl git jq unzip
archive=/tmp/tofu.zip
curl --fail --silent --show-error --location \
  https://github.com/opentofu/opentofu/releases/download/v1.13.1/tofu_1.13.1_linux_amd64.zip \
  --output "$archive"
echo "8ccbc6f8ee21d2827715f3c6e08a9b3e0209b1e62057c05067ef117e047c1a80  $archive" | sha256sum -c -
unzip -oq "$archive" tofu -d /usr/local/bin

TF_HTTP_ADDRESS="$CI_API_V4_URL/projects/$CI_PROJECT_ID/terraform/state/$TF_STATE_NAME"
TF_HTTP_LOCK_ADDRESS="$TF_HTTP_ADDRESS/lock"
TF_HTTP_UNLOCK_ADDRESS="$TF_HTTP_ADDRESS/lock"
TF_HTTP_LOCK_METHOD=POST
TF_HTTP_UNLOCK_METHOD=DELETE
TF_HTTP_USERNAME=gitlab-ci-token
TF_HTTP_PASSWORD=$CI_JOB_TOKEN
TF_HTTP_RETRY_WAIT_MIN=5
TF_IN_AUTOMATION=1
export TF_HTTP_ADDRESS TF_HTTP_LOCK_ADDRESS TF_HTTP_UNLOCK_ADDRESS
export TF_HTTP_LOCK_METHOD TF_HTTP_UNLOCK_METHOD TF_HTTP_USERNAME TF_HTTP_PASSWORD
export TF_HTTP_RETRY_WAIT_MIN TF_IN_AUTOMATION

cd "$CI_PROJECT_DIR/$TF_ROOT"
tofu init -input=false -lockfile=readonly -reconfigure
