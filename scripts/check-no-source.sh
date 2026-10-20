#!/usr/bin/env bash
# Fails when anything that looks like application source code is tracked in
# this repository. The deployment kit ships configuration, scripts and docs
# only; the software itself ships as pre-built images.
#
# Usage: scripts/check-no-source.sh   (run from the repository root)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Source and build files of the software itself. Shell, PowerShell, YAML,
# Markdown, env templates and proxy configs are the kit and are allowed.
forbidden='\.(rs|toml|lock|ts|tsx|jsx|js|mjs|cjs|vue|svelte|py|go|java|kt|cs|c|cc|cpp|h|hpp|sql|proto|wasm|map)$'
# .gitleaks.toml is the secret scanner's settings, not code.
allowed_exact='^(\.github/workflows/.*\.ya?ml|\.gitleaks\.toml)$'

bad=$(git ls-files | grep -Ei "$forbidden" | grep -Ev "$allowed_exact" || true)

# A Dockerfile with a build step means somebody is building from source here.
dockerfiles=$(git ls-files | grep -Ei '(^|/)(Dockerfile|Containerfile)[^/]*$' || true)

# Compose files must reference images, never build contexts.
builds=$(git ls-files -z -- '*.yml' '*.yaml' \
  | xargs -0 -r grep -nE '^[[:space:]]+build:' 2>/dev/null || true)

status=0
if [ -n "$bad" ]; then
  echo "Source-like files are not allowed in the deployment kit:" >&2
  echo "$bad" | sed 's/^/  /' >&2
  status=1
fi
if [ -n "$dockerfiles" ]; then
  echo "Dockerfiles are not allowed here (images are built privately):" >&2
  echo "$dockerfiles" | sed 's/^/  /' >&2
  status=1
fi
if [ -n "$builds" ]; then
  echo "Compose files must use 'image:', never 'build:':" >&2
  echo "$builds" | sed 's/^/  /' >&2
  status=1
fi
[ "$status" -eq 0 ] && echo "OK: no source code, Dockerfiles or build contexts tracked."
exit "$status"
