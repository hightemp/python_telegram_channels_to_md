#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   export_and_push.sh [REPO_DIR]
#
# Runs download_channels.py, then commits and pushes any changes in the repo.

REPO_DIR="${1:-}"

if [[ -z "${REPO_DIR}" ]]; then
  # Resolve repo root relative to this script location
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

cd "${REPO_DIR}"

# Choose Python interpreter
if [[ -x ".venv/bin/python" ]]; then
  PYTHON=".venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "[ERROR] python3 not found" >&2
  exit 1
fi

echo "[INFO] Running export with ${PYTHON}"
"${PYTHON}" download_channels.py

# Allow running under different users (e.g., systemd system scope)
git config --global --add safe.directory "${REPO_DIR}" 2>/dev/null || true

# Ensure git identity is set (repo-local fallback if not configured globally)
if ! git config --get user.name >/dev/null 2>&1; then
  git config user.name "channels-bot"
fi
if ! git config --get user.email >/dev/null 2>&1; then
  git config user.email "bot@example.invalid"
fi

# Stage all changes
git add -A

# If nothing staged, exit quietly
if git diff --cached --quiet; then
  echo "[INFO] No changes to commit"
  exit 0
fi

TS="$(date '+%Y-%m-%d %H:%M:%S %z')"
MSG="chore(export): update channels ${TS}"

echo "[INFO] Committing changes: ${MSG}"
git commit -m "${MSG}"

REMOTE="${GIT_REMOTE:-origin}"
BRANCH_DEFAULT="$(git rev-parse --abbrev-ref HEAD)"
BRANCH="${GIT_BRANCH:-${BRANCH_DEFAULT}}"

if ! git remote get-url "${REMOTE}" >/dev/null 2>&1; then
  echo "[WARN] Remote '${REMOTE}' not found; skipping push"
  exit 0
fi

echo "[INFO] Pushing to ${REMOTE} ${BRANCH}"
git push "${REMOTE}" "${BRANCH}"

echo "[OK] Export committed and pushed"