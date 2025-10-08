#!/bin/bash
set -Eeuo pipefail

# Env vars
: "${PROJECT_DIR:=/app/src}"
: "${PROJECT_GIT_BRANCH:=main}"
: "${PROJECT_GIT_URL:=}"

# Retry settings
: "${CLONE_RETRY_MAX:=5}"
: "${CLONE_RETRY_BASE_DELAY:=2}"

log()  { printf '[create-project] %s\n' "$*"; }
warn() { printf '[create-project][WARN] %s\n' "$*" >&2; }
err()  { printf '[create-project][ERROR] %s\n' "$*" >&2; }

# Remove contents but not the directory itself (safe for bind mounts)
safe_clean_dir() {
  local dir="$1"
  mkdir -p "$dir"
  if [ -d "$dir" ]; then
    log "Cleaning contents of $dir"
    # Use find to include dotfiles and avoid glob pitfalls
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || true
  fi
}

# Get host from git URL
extract_host() {
  local url="$1"
  if [[ "$url" =~ ^git@([^:]+): ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^ssh://[^@]+@([^/]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^https?://([^/]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "github.com"
  fi
}

# Accept SSH host key automatically (no interactive prompt)
ensure_known_host() {
  local host="$1"
  if command -v ssh-keyscan >/dev/null 2>&1; then
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/known_hosts
    if ! ssh-keygen -F "$host" >/dev/null 2>&1; then
      log "Adding $host to known_hosts"
      ssh-keyscan -H "$host" >> ~/.ssh/known_hosts 2>/dev/null || true
    fi
  fi
}

# Clone with exponential backoff
git_clone_with_retries() {
  local url="$1" branch="$2" dir="$3"
  local attempt=1 max="$CLONE_RETRY_MAX" delay="$CLONE_RETRY_BASE_DELAY"
  local ssh_cmd='ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5'

  while (( attempt <= max )); do
    log "git clone -b $branch $url $dir (attempt $attempt/$max)"
    if GIT_SSH_COMMAND="$ssh_cmd" git clone -b "$branch" "$url" "$dir"; then
      log "Clone successful."
      return 0
    fi
    warn "Clone failed; retrying in ${delay}s..."
    sleep "$delay"
    delay=$(( delay * 2 ))
    attempt=$(( attempt + 1 ))
  done

  return 1
}

main() {
  if [ -z "${PROJECT_GIT_URL:-}" ]; then
    log "PROJECT_GIT_URL not set; skipping clone."
    exit 0
  fi

  mkdir -p "$PROJECT_DIR"
  safe_clean_dir "$PROJECT_DIR"
  ensure_known_host "$(extract_host "$PROJECT_GIT_URL")"

  if git_clone_with_retries "$PROJECT_GIT_URL" "$PROJECT_GIT_BRANCH" "$PROJECT_DIR"; then
    sleep 2
    apache2ctl restart
    exit 0
  else
    err "Failed to clone $PROJECT_GIT_URL"
    exit 1
  fi
}

main "$@"




#if [ -n "$PROJECT_GIT_URL" ]; then
#    mkdir -p "$PROJECT_DIR"
#    echo "Removing $PROJECT_DIR"
#    sleep 3
#    [ -d "$PROJECT_DIR" ] && rm -rf "$PROJECT_DIR"
#    sleep $(( RANDOM % 3 + RANDOM % 5 ))
#    echo "Running: git clone -b $PROJECT_GIT_BRANCH $PROJECT_GIT_URL $PROJECT_DIR"
#    git clone -b "$PROJECT_GIT_BRANCH" "$PROJECT_GIT_URL" "$PROJECT_DIR"
#    if [ $? -eq 0 ]; then
#        echo "Clone successful."
#    else
#        echo "Clone failed."
#        exit 1
#    fi
#    apache2ctl restart # this will mess up with supervisord apache2 process start
#fi