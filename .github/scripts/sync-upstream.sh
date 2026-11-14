#!/usr/bin/env bash
# Mirror the latest declauding-v* release of oaustegard/claude-skills into this repository.
#
# Splits the upstream declauding/ directory into its own history, merges it into the current
# branch, points README links that leave the directory at the upstream tag, and creates the tag
# vX.Y.Z. Pushing and the GitHub release are left to the caller.
#
# Usage: sync-upstream.sh [--sign]
#   --sign  sign the tag with the committer's key (local use; CI tags are unsigned)
#
# Outputs (appended to $GITHUB_OUTPUT when set): version, upstream_tag, notes_file.
# Prints "already mirrored" and creates nothing when the latest version is already tagged here.
set -euo pipefail

UPSTREAM_URL="https://github.com/oaustegard/claude-skills"
PREFIX="declauding"

tag_flag=(-a)
if [[ "${1:-}" == "--sign" ]]; then
  tag_flag=(-s)
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --no-checkout "$UPSTREAM_URL.git" "$work/upstream"
upstream_tag="$(git -C "$work/upstream" tag -l "$PREFIX-v*" | sort -V | tail -n 1)"
if [[ -z "$upstream_tag" ]]; then
  echo "no $PREFIX-v* tag upstream" >&2
  exit 1
fi
version="${upstream_tag#"$PREFIX-"}"

if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
  echo "$version already mirrored"
  exit 0
fi

split="$(git -C "$work/upstream" subtree split --quiet --prefix="$PREFIX" "$upstream_tag")"
git -C "$work/upstream" branch -f split-out "$split"
git fetch --quiet "$work/upstream" "+split-out:refs/heads/upstream"

# Upstream wins any conflict; the README links are rewritten again right after.
git merge --quiet --no-edit -X theirs -m "Merge upstream $upstream_tag" refs/heads/upstream

# ../<skill> links point at sibling skills that this repository does not contain.
sed -E -i \
  -e "s#\]\(\.\./([^)]+)\)#](${UPSTREAM_URL}/tree/${upstream_tag}/\1)#g" \
  -e "s#(${UPSTREAM_URL}/tree/)${PREFIX}-v[0-9][^/]*/#\1${upstream_tag}/#g" \
  README.md
if ! git diff --quiet -- README.md; then
  git commit --quiet -m "docs: point README links at upstream $upstream_tag" -- README.md
fi

git tag "${tag_flag[@]}" -m "$version" "$version"

notes_file="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/${PREFIX}-${version}-notes.md"
{
  echo "Mirror of [$PREFIX $version]($UPSTREAM_URL/releases/tag/$upstream_tag) from oaustegard/claude-skills."
  echo
  awk -v head="## [${version#v}]" '
    index($0, head) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found && (started || NF) { started = 1; print }
  ' CHANGELOG.md
} >"$notes_file"

echo "mirrored $upstream_tag as $version"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$version"
    echo "upstream_tag=$upstream_tag"
    echo "notes_file=$notes_file"
  } >>"$GITHUB_OUTPUT"
fi
