#!/bin/bash

set -Eeo pipefail

die() {
  echo ::error::${@}
  exit 1
}

gpgb() {
  /gpg-wrapper "${@}"
}

if [ -z "${INPUT_GITHUB_TOKEN}" ]; then
  die "The INPUT_GITHUB_TOKEN env var is missing."
fi

if [ -z "${GITHUB_EVENT_PATH}" ]; then
  die "The GITHUB_EVENT_PATH env var is missing."
fi

if [ -z "${GITHUB_REF}" ]; then
  die "The GITHUB_REF env var is missing."
fi

gpg_key_id=""
if [ -n "${INPUT_GPG_KEY}" ]; then
  if [ -n "${INPUT_GPG_KEY_ID}" ]; then
    gpg_key_id="${INPUT_GPG_KEY_ID}"
  else
    gpg_key_id=$(echo "${INPUT_GPG_KEY}" \
                 | gpgb --import --import-options show-only --with-colons \
                 | grep '^sec:' \
                 | cut -f 5 -d':')

    if [[ $(echo "${gpg_key_id}" | wc -l) -gt 1 ]]; then
      die "Multiple keys found in INPUT_GPG_KEY, please specify " \
          "the key id via INPUT_GPG_KEY_ID".
    fi

    echo "key_id=${gpg_key_id}"
  fi

  echo "${INPUT_GPG_KEY}" \
    | gpgb --import
fi

if [ -n "${INPUT_SSH_KEY}" ]; then
  mkdir -p "${HOME}/.ssh"
  echo "${INPUT_SSH_KEY}" > "${HOME}/.ssh/id_rsa"
  chmod 600 "${HOME}/.ssh/id_rsa"
fi

if [ -z "${INPUT_TAG_NAME}" ]; then
  die "The INPUT_TAG_NAME env var is missing."
fi

URI="https://api.github.com"
AUTH_HEADER="Authorization: token ${INPUT_GITHUB_TOKEN}"
API_HEADER="Accept: application/vnd.github.v3+json"

jqr() {
  jq --raw-output "${@}"
}

jqevent() {
  jqr "${@}" "${GITHUB_EVENT_PATH}"
}

get() {
  curl -sSL -X GET -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}${1}"
}

user=$(get /user)

login=$(echo "${user}" | jqr .login)
username=$(echo "${user}" | jqr .name)
email=$(echo "${user}" | jqr .email)
pr_sha=$(jqevent .pull_request.head.sha)
base_ref=$(jqevent .pull_request.base.ref)
message="${INPUT_TAG_MESSAGE}"
if [ -z "${message}" ]; then
  message="$(jqevent .pull_request.title)

$(jqevent .pull_request.body)"
fi

git config user.name "${username}"
git config user.email "${email}"
git config gpg.program "/gpg-wrapper"

if [ -n "${gpg_key_id}" ]; then
  git config commit.gpgsign true
  git config user.signingkey "${gpg_key_id}"
fi

git fetch origin "${GITHUB_REF}"
echo "${message}" \
  | git tag --sign --file=- "${INPUT_TAG_NAME}" "${pr_sha}"
url=$(git config remote.origin.url)
url="https://${login}:${INPUT_GITHUB_TOKEN}@${url#https://}"
git push --follow-tags "${url}" "${pr_sha}":"${base_ref}"
