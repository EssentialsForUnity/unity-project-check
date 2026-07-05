# Unity Project Check

Reusable GitHub Actions workflow for basic Unity project repository checks.

This is intentionally lightweight. It validates that a repository looks like a Unity project without launching Unity, restoring packages, compiling scripts, or running tests.

## Usage

Add a workflow to the consuming repository:

```yaml
name: Unity Project Check

on:
  push:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  structure:
    uses: EssentialsForUnity/unity-project-check/.github/workflows/unity-project-check.yml@main
```

You can also call the action directly when you want normal action-style version pinning:

```yaml
name: Unity Project Check

on:
  push:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  structure:
    name: Check Unity project structure
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Unity project check
        uses: EssentialsForUnity/unity-project-check@main
```

Optional inputs:

```yaml
jobs:
  structure:
    uses: EssentialsForUnity/unity-project-check/.github/workflows/unity-project-check.yml@main
    with:
      path: .
      require-assets: true
      require-packages: true
      require-project-settings: true
      check-package-lock: true
      fail-on-tracked-generated: true
      check-gitignore: true
      check-large-files: true
      max-file-size-mb: 100
      checker-repository: EssentialsForUnity/unity-project-check
      checker-ref: main
```

## What Gets Checked

By default the checker verifies:

- `Assets/` exists.
- `Packages/` exists.
- `Packages/manifest.json` exists, parses as JSON, and has a top-level `dependencies` object.
- `Packages/packages-lock.json` parses as JSON when present.
- `ProjectSettings/` exists.
- `ProjectSettings/ProjectVersion.txt` exists and contains `m_EditorVersion:`.
- Common Unity-generated and IDE files are not tracked in git.
- Common Unity-generated and IDE files are covered by `.gitignore`.
- Tracked files do not exceed the configured size limit.

The tracked generated-file check covers:

```text
Library/, Temp/, Obj/, Build/, Builds/, Logs/, UserSettings/, .idea/, .vs/,
*.csproj, *.sln, *.unityproj
```

The `.gitignore` coverage check uses `git check-ignore` against representative generated paths such as `Library/`, `Temp/`, `.idea/`, `.vs/`, `*.csproj`, and `*.sln`. The large-file check defaults to `100 MB`.

## What This Does Not Do

This does not replace a Unity compile, package restore, scene validation, asmdef validation, analyzers, or tests. Pair it with the shared C# syntax check or a real Unity CI job when you need stronger validation.
