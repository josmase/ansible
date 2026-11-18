#!/bin/sh
set -eu

if [ "${CI_COMMIT_BRANCH:-}" != "${CI_DEFAULT_BRANCH:?}" ]; then
  echo 'Apply is permitted only on the default branch.' >&2
  exit 1
fi

remote_ref=$(git ls-remote --exit-code origin "refs/heads/$CI_DEFAULT_BRANCH")
remote_sha=${remote_ref%%[[:space:]]*}
if [ -z "$remote_sha" ] || [ "$remote_sha" != "${CI_COMMIT_SHA:?}" ]; then
  echo 'The default branch has advanced; run and review a new pipeline.' >&2
  exit 1
fi
