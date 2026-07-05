#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/unity-project-check.sh"
valid_fixture="$repo_root/tests/fixtures/valid-unity-project"
tmp_root="$(mktemp -d)"
last_output=""

trap 'rm -rf "$tmp_root"' EXIT

expect_failure() {
  local name="$1"
  shift

  local output="$tmp_root/${name}.txt"
  set +e
  "$@" >"$output" 2>&1
  local status=$?
  set -e

  sed 's#^::#: :#' "$output"

  if [[ "$status" -eq 0 ]]; then
    echo "Expected $name to fail."
    exit 1
  fi

  last_output="$output"
}

expect_output() {
  local pattern="$1"

  if ! grep -Fq "$pattern" "$last_output"; then
    echo "Expected output to contain: $pattern"
    exit 1
  fi
}

copy_valid_fixture() {
  local destination="$1"
  cp -R "$valid_fixture" "$destination"
}

init_git_repo() {
  local project="$1"
  (
    cd "$project"
    git init -q
    git add -A
  )
}

expect_failure missing-project-structure \
  "$checker" --path "$repo_root/tests/fixtures/not-unity-project"
expect_output "Missing required directory: Assets"
expect_output "Missing required file: Packages/manifest.json"
expect_output "Missing required file: ProjectSettings/ProjectVersion.txt"

bad_manifest="$tmp_root/bad-manifest"
copy_valid_fixture "$bad_manifest"
printf '{"dependencies":[]}\n' >"$bad_manifest/Packages/manifest.json"
expect_failure bad-manifest \
  "$checker" --path "$bad_manifest"
expect_output "Unity package manifest must contain a top-level dependencies object."

bad_lock="$tmp_root/bad-packages-lock"
copy_valid_fixture "$bad_lock"
printf '{not-json}\n' >"$bad_lock/Packages/packages-lock.json"
expect_failure bad-packages-lock \
  "$checker" --path "$bad_lock"
expect_output "Invalid JSON"

bad_project_version="$tmp_root/bad-project-version"
copy_valid_fixture "$bad_project_version"
printf 'm_EditorVersionWithRevision: 6000.0.0f1\n' >"$bad_project_version/ProjectSettings/ProjectVersion.txt"
expect_failure bad-project-version \
  "$checker" --path "$bad_project_version"
expect_output "ProjectSettings/ProjectVersion.txt is missing m_EditorVersion."

bad_gitignore="$tmp_root/bad-gitignore"
copy_valid_fixture "$bad_gitignore"
rm "$bad_gitignore/.gitignore"
init_git_repo "$bad_gitignore"
expect_failure bad-gitignore \
  "$checker" --path "$bad_gitignore"
expect_output ".gitignore is missing common Unity or IDE generated-file coverage."

tracked_generated="$tmp_root/tracked-generated"
copy_valid_fixture "$tracked_generated"
(
  cd "$tracked_generated"
  git init -q
  git add -A
  mkdir -p Library
  printf 'generated\n' >Library/generated.asset
  git add -f Library/generated.asset
)
expect_failure tracked-generated \
  "$checker" --path "$tracked_generated"
expect_output "Generated Unity or IDE files are tracked by git."
expect_output "Library/generated.asset"

large_file="$tmp_root/large-file"
copy_valid_fixture "$large_file"
python3 - "$large_file/Large.bin" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(b"0" * (2 * 1024 * 1024))
PY
init_git_repo "$large_file"
expect_failure large-file \
  "$checker" --path "$large_file" --max-file-size-mb 1
expect_output "Tracked files exceed 1 MB."
expect_output "Large.bin"
