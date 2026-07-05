#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: unity-project-check.sh [options]

Options:
  --path <path>                         Repository-relative Unity project path. Default: .
  --require-assets <true|false>         Require Assets/. Default: true
  --require-packages <true|false>       Require Packages/ and manifest.json. Default: true
  --require-project-settings <true|false>
                                        Require ProjectSettings/ and ProjectVersion.txt. Default: true
  --check-package-lock <true|false>     Validate packages-lock.json when present. Default: true
  --fail-on-tracked-generated <true|false>
                                        Fail when generated Unity or IDE files are tracked. Default: true
  -h, --help                            Show this help.
USAGE
}

project_path="."
require_assets="true"
require_packages="true"
require_project_settings="true"
check_package_lock="true"
fail_on_tracked_generated="true"

normalize_bool() {
  case "$1" in
    true|True|TRUE|1|yes|Yes|YES) echo "true" ;;
    false|False|FALSE|0|no|No|NO) echo "false" ;;
    *)
      echo "Invalid boolean value: $1" >&2
      exit 2
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      project_path="${2:?Missing value for --path}"
      shift 2
      ;;
    --require-assets)
      require_assets="$(normalize_bool "${2:?Missing value for --require-assets}")"
      shift 2
      ;;
    --require-packages)
      require_packages="$(normalize_bool "${2:?Missing value for --require-packages}")"
      shift 2
      ;;
    --require-project-settings)
      require_project_settings="$(normalize_bool "${2:?Missing value for --require-project-settings}")"
      shift 2
      ;;
    --check-package-lock)
      check_package_lock="$(normalize_bool "${2:?Missing value for --check-package-lock}")"
      shift 2
      ;;
    --fail-on-tracked-generated)
      fail_on_tracked_generated="$(normalize_bool "${2:?Missing value for --fail-on-tracked-generated}")"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

errors=0

error() {
  echo "::error::$*"
  errors=$((errors + 1))
}

notice() {
  echo "::notice::$*"
}

require_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    error "Missing required directory: $dir"
  fi
}

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    error "Missing required file: $file"
  fi
}

validate_manifest_json() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return
  fi

  python3 - "$file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"::error file={path}::Invalid JSON: {exc}")
    sys.exit(1)

if not isinstance(data, dict):
    print(f"::error file={path}::Unity package manifest must be a JSON object.")
    sys.exit(1)

dependencies = data.get("dependencies")
if not isinstance(dependencies, dict):
    print(f"::error file={path}::Unity package manifest must contain a top-level dependencies object.")
    sys.exit(1)
PY
}

validate_json_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return
  fi

  python3 - "$file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    with path.open("r", encoding="utf-8") as handle:
        json.load(handle)
except Exception as exc:
    print(f"::error file={path}::Invalid JSON: {exc}")
    sys.exit(1)
PY
}

if [[ ! -d "$project_path" ]]; then
  error "Project path does not exist or is not a directory: $project_path"
else
  cd "$project_path"

  if [[ "$require_assets" == "true" ]]; then
    require_dir "Assets"
  fi

  if [[ "$require_packages" == "true" ]]; then
    require_dir "Packages"
    require_file "Packages/manifest.json"

    if ! validate_manifest_json "Packages/manifest.json"; then
      errors=$((errors + 1))
    fi
  elif [[ -f "Packages/manifest.json" ]]; then
    if ! validate_manifest_json "Packages/manifest.json"; then
      errors=$((errors + 1))
    fi
  fi

  if [[ "$check_package_lock" == "true" && -f "Packages/packages-lock.json" ]]; then
    if ! validate_json_file "Packages/packages-lock.json"; then
      errors=$((errors + 1))
    fi
  fi

  if [[ "$require_project_settings" == "true" ]]; then
    require_dir "ProjectSettings"
    require_file "ProjectSettings/ProjectVersion.txt"

    if [[ -f "ProjectSettings/ProjectVersion.txt" ]] && ! grep -q '^m_EditorVersion:' "ProjectSettings/ProjectVersion.txt"; then
      error "ProjectSettings/ProjectVersion.txt is missing m_EditorVersion."
    fi
  fi

  if [[ "$fail_on_tracked_generated" == "true" ]]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      tracked_generated="$(
        git ls-files -- \
          'Library/*' \
          'Temp/*' \
          'Obj/*' \
          'Build/*' \
          'Builds/*' \
          'Logs/*' \
          'UserSettings/*' \
          '.idea/*' \
          '.vs/*' \
          '*.csproj' \
          '*.sln' \
          '*.unityproj'
      )"

      if [[ -n "$tracked_generated" ]]; then
        error "Generated Unity or IDE files are tracked by git."
        printf '%s\n' "$tracked_generated"
      fi
    else
      notice "Skipping tracked generated-file check because this path is not inside a git work tree."
    fi
  fi
fi

if [[ "$errors" -gt 0 ]]; then
  echo "Unity project check failed with $errors issue(s)."
  exit 1
fi

echo "Unity project check passed."
