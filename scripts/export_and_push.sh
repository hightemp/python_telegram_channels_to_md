#!/usr/bin/env bash
set -euo pipefail
# Enable verbose debug if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then set -x; fi

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
echo "[INFO] REPO_DIR=${REPO_DIR}"
echo "[INFO] PWD=$(pwd)"

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

# Подготовим вызов git без зависимости от $HOME/глобальной конфигурации
GIT_CMD=(git -C "${REPO_DIR}" -c safe.directory="${REPO_DIR}")

# Идентичность коммитов через переменные окружения (работает под systemd без записи конфигов)
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-channels-bot}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-bot@example.invalid}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"

# Ensure we are in a git repo or optionally initialize one
if ! "${GIT_CMD[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ "${GIT_AUTO_INIT:-0}" == "1" ]]; then
    echo "[WARN] Not a git repo, initializing (GIT_AUTO_INIT=1) in $(pwd)"
    git -c init.defaultBranch="${GIT_INIT_DEFAULT_BRANCH:-main}" init
    if [[ -n "${GIT_REMOTE_URL:-}" ]]; then
      git remote add "${GIT_REMOTE:-origin}" "${GIT_REMOTE_URL}"
    fi
  else
    echo "[ERROR] Not a git repository: $(pwd). Set GIT_AUTO_INIT=1 and optionally GIT_REMOTE_URL to initialize automatically." >&2
    exit 128
  fi
fi

# Stage all changes
"${GIT_CMD[@]}" add -A

# If nothing staged, exit quietly
if "${GIT_CMD[@]}" diff --cached --quiet; then
  echo "[INFO] No changes to commit"
  exit 0
fi

TS="$(date '+%Y-%m-%d %H:%M:%S %z')"
MSG="chore(export): update channels ${TS}"

echo "[INFO] Committing changes: ${MSG}"
"${GIT_CMD[@]}" commit -m "${MSG}"

# Configure non-interactive SSH for first-time host key acceptance and optional key path
if [[ -z "${GIT_SSH_COMMAND:-}" ]]; then
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"
  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    GIT_SSH_COMMAND="${GIT_SSH_COMMAND} -i ${SSH_KEY_PATH}"
  fi
  export GIT_SSH_COMMAND
fi

REMOTE="${GIT_REMOTE:-origin}"
BRANCH_DEFAULT="$("${GIT_CMD[@]}" rev-parse --abbrev-ref HEAD)"
BRANCH="${GIT_BRANCH:-${BRANCH_DEFAULT}}"
PUSH_TARGET="${GIT_PUSH_URL:-${REMOTE}}"

if [[ -n "${GIT_PUSH_URL:-}" ]]; then
  echo "[INFO] Using push URL: ${GIT_PUSH_URL}"
else
  if ! "${GIT_CMD[@]}" remote get-url "${REMOTE}" >/dev/null 2>&1; then
    echo "[WARN] Remote '${REMOTE}' not found; skipping push"
    exit 0
  fi
fi

echo "[INFO] Pushing to ${PUSH_TARGET} ${BRANCH}"
"${GIT_CMD[@]}" push "${PUSH_TARGET}" "${BRANCH}"

echo "[OK] Export committed and pushed"