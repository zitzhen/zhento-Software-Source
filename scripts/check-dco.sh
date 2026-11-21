#!/usr/bin/env bash
# Verify that every non-merge commit in a revision range carries a valid DCO
# Signed-off-by trailer whose signer matches the author or committer email.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: check-dco.sh <rev-range>" >&2
  exit 1
fi

range="$1"

if ! git rev-parse --verify --quiet HEAD >/dev/null; then
  echo "Error: not a Git repository with a valid HEAD." >&2
  exit 1
fi

mapfile -t commits < <(git rev-list --no-merges "$range")
if (( ${#commits[@]} == 0 )); then
  echo "No commits to check in range: $range"
  exit 0
fi

failures=0
for sha in "${commits[@]}"; do
  short="$(git rev-parse --short "$sha")"
  subject="$(git show -s --format='%s' "$sha")"
  author_email="$(git show -s --format='%ae' "$sha")"
  committer_email="$(git show -s --format='%ce' "$sha")"
  body="$(git show -s --format='%B' "$sha")"

  trailers="$(printf '%s\n' "$body" | git interpret-trailers --parse | grep -i '^Signed-off-by:' || true)"
  if [[ -z "$trailers" ]]; then
    echo "::error::$short $subject - missing Signed-off-by trailer (DCO requirement)"
    failures=$((failures + 1))
    continue
  fi

  valid=0
  while IFS= read -r trailer; do
    signer="${trailer#*:}"
    signer="${signer#"${signer%%[![:space:]]*}"}"
    signer="${signer%"${signer##*[![:space:]]}"}"

    if [[ ! "$signer" =~ ^([^<>]+)\ \<([^>]+)\>$ ]]; then
      continue
    fi
    name="${BASH_REMATCH[1]}"
    email="${BASH_REMATCH[2]}"
    name="${name%"${name##*[![:space:]]}"}"

    [[ -n "$name" && "$email" == *@* ]] || continue
    if [[ "${email,,}" == "${author_email,,}" || "${email,,}" == "${committer_email,,}" ]]; then
      valid=1
      break
    fi
  done <<< "$trailers"

  if (( valid == 0 )); then
    echo "::error::$short $subject - Signed-off-by does not match the commit author or committer (author: $author_email)"
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  echo "DCO check failed: $failures of ${#commits[@]} commit(s) are not properly signed off." >&2
  exit 1
fi

echo "DCO check passed for ${#commits[@]} commit(s)."
