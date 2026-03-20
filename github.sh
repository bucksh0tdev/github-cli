#!/usr/bin/env bash
set -euo pipefail

APP_NAME="$(basename "$0")"
DEFAULT_MSG_PUSH="Committed By bucksh0t"
DEFAULT_MSG_WIPE="Wiped By bucksh0t"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_BOLD=$(printf '\033[1m')
  C_DIM=$(printf '\033[2m')
  C_RED=$(printf '\033[31m')
  C_YELLOW=$(printf '\033[33m')
  C_GREEN=$(printf '\033[32m')
  C_BLUE=$(printf '\033[34m')
  C_RESET=$(printf '\033[0m')
else
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_YELLOW=""
  C_GREEN=""
  C_BLUE=""
  C_RESET=""
fi

usage() {
  cat <<USAGE
Usage:
  ${APP_NAME} list
  ${APP_NAME} clone [options] <repository> [directory] [-- <git clone flags...>]
  ${APP_NAME} push [options] [commit message]
  ${APP_NAME} wipe [options] [commit message]
  ${APP_NAME} create [options] <description>
  ${APP_NAME} help

Options (push):
  -m, --message <msg>   Commit message (default: "Committed By bucksh0t")
  -b, --branch <name>   Remote target branch (default: current local branch)
  --force               Force push (overwrites remote history)

Options (wipe):
  -m, --message <msg>   Commit message (default: "Wiped By bucksh0t")
  -b, --branch <name>   Target branch to wipe (default: main)

Options (create):
  -d, --description <t> Repo description (or pass as positional)
  --public              Create a public repo
  --private             Create a private repo (default)

Options (clone):
  -u, --upstream-remote-name <name> Upstream remote name for forks
  --                              Pass remaining flags to git clone

General:
  -h, --help            Show this help
USAGE
}

log_ok()   { printf "%b%s%b\n" "$C_GREEN" "$1" "$C_RESET"; }
log_warn() { printf "%b%s%b\n" "$C_YELLOW" "$1" "$C_RESET"; }
log_err()  { printf "%b%s%b\n" "$C_RED" "$1" "$C_RESET"; }

title() { printf "%b== %s ==%b\n" "$C_BOLD" "$1" "$C_RESET"; }
kv() { printf "  %b%-10s%b %s\n" "$C_DIM" "$1" "$C_RESET" "$2"; }

require_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_err "Not a git repository. Run: git init && git remote add origin <repo-url>"
    exit 1
  fi
}

require_origin() {
  if ! git remote get-url origin >/dev/null 2>&1; then
    log_err "Remote 'origin' not found. Run: git remote add origin <repo-url>"
    exit 1
  fi
}

current_branch() {
  git symbolic-ref --short -q HEAD 2>/dev/null || true
}

resolve_target_branch() {
  local override="$1"
  if [[ -n "$override" ]]; then
    echo "$override"
    return
  fi

  echo "main"
}

repo_info() {
  local top branch remote
  top=$(git rev-parse --show-toplevel)
  branch=$(current_branch)
  remote=$(git remote get-url origin 2>/dev/null || echo "(none)")

  title "Repo"
  kv "Name" "$(basename "$top")"
  kv "Path" "$top"
  if [[ -n "$branch" ]]; then
    kv "Branch" "$branch"
  else
    kv "Branch" "(detached)"
  fi
  kv "Remote" "$remote"
  echo
}

print_status() {
  title "Working Tree"
  if git status --short | grep -q .; then
    git status --short
  else
    echo "(clean)"
  fi
  echo
}

print_staged_summary() {
  title "Staged Summary"
  if git diff --cached --quiet; then
    echo "(no staged changes)"
  else
    git diff --cached --stat
  fi
  echo
}

list_changes() {
  require_git_repo
  repo_info
  print_status
}

PUSH_MSG=""
PUSH_FORCE="false"
PUSH_BRANCH_OVERRIDE=""
WIPE_MSG=""
WIPE_BRANCH_OVERRIDE=""
CREATE_DESC=""
CREATE_VISIBILITY="private"
CLONE_REPO=""
CLONE_DIR=""
declare -a CLONE_GH_FLAGS=()
declare -a CLONE_GIT_FLAGS=()

parse_push_args() {
  local msg="$DEFAULT_MSG_PUSH"
  local msg_set=false
  local force=false
  local branch_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message)
        if [[ $# -lt 2 ]]; then
          log_err "Missing value for $1"
          exit 1
        fi
        msg="$2"
        msg_set=true
        shift 2
        ;;
      -b|--branch)
        if [[ $# -lt 2 ]]; then
          log_err "Missing value for $1"
          exit 1
        fi
        branch_override="$2"
        shift 2
        ;;
      --force)
        force=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -* )
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ "$msg_set" == "true" ]]; then
          log_err "Commit message already set. Use -m/--message or a single positional message."
          exit 1
        fi
        msg="$1"
        msg_set=true
        shift
        ;;
    esac
  done

  PUSH_MSG="$msg"
  PUSH_FORCE="$force"
  PUSH_BRANCH_OVERRIDE="$branch_override"
}

parse_wipe_args() {
  local msg="$DEFAULT_MSG_WIPE"
  local msg_set=false
  local branch_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message)
        if [[ $# -lt 2 ]]; then
          log_err "Missing value for $1"
          exit 1
        fi
        msg="$2"
        msg_set=true
        shift 2
        ;;
      -b|--branch)
        if [[ $# -lt 2 ]]; then
          log_err "Missing value for $1"
          exit 1
        fi
        branch_override="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -* )
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ "$msg_set" == "true" ]]; then
          log_err "Commit message already set. Use -m/--message or a single positional message."
          exit 1
        fi
        msg="$1"
        msg_set=true
        shift
        ;;
    esac
  done

  WIPE_MSG="$msg"
  WIPE_BRANCH_OVERRIDE="$branch_override"
}

parse_create_args() {
  local desc=""
  local desc_set=false
  local visibility="private"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--description)
        if [[ $# -lt 2 ]]; then
          log_err "Missing value for $1"
          exit 1
        fi
        desc="$2"
        desc_set=true
        shift 2
        ;;
      --public)
        visibility="public"
        shift
        ;;
      --private)
        visibility="private"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -* )
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ "$desc_set" == "true" ]]; then
          log_err "Description already set. Use --description or a single positional value."
          exit 1
        fi
        desc="$1"
        desc_set=true
        shift
        ;;
    esac
  done

  if [[ -z "$desc" ]]; then
    log_err "Missing description. Usage: github create \"description\""
    exit 1
  fi

  CREATE_DESC="$desc"
  CREATE_VISIBILITY="$visibility"
}

parse_clone_args() {
  local repo=""
  local dir=""
  local -a gh_flags=()
  local -a git_flags=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--upstream-remote-name)
        if [[ $# -lt 2 ]]; then
          log_err "Missing value for $1"
          exit 1
        fi
        gh_flags+=("$1" "$2")
        shift 2
        ;;
      --)
        shift
        if [[ $# -gt 0 ]]; then
          git_flags+=("$@")
        fi
        break
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -* )
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ -z "$repo" ]]; then
          repo="$1"
          shift
        elif [[ -z "$dir" ]]; then
          dir="$1"
          shift
        else
          log_err "Too many arguments for clone. Usage: github clone <repository> [directory]"
          exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$repo" ]]; then
    log_err "Missing repository. Usage: github clone <repository> [directory]"
    exit 1
  fi

  CLONE_REPO="$repo"
  CLONE_DIR="$dir"
  if [[ ${#gh_flags[@]} -gt 0 ]]; then
    CLONE_GH_FLAGS=("${gh_flags[@]}")
  else
    CLONE_GH_FLAGS=()
  fi
  if [[ ${#git_flags[@]} -gt 0 ]]; then
    CLONE_GIT_FLAGS=("${git_flags[@]}")
  else
    CLONE_GIT_FLAGS=()
  fi
}

infer_clone_dir() {
  local repo="$1"
  local dir
  dir="${repo##*/}"
  dir="${dir%.git}"
  echo "$dir"
}

origin_branch_exists() {
  local branch="$1"
  git show-ref --verify --quiet "refs/remotes/origin/${branch}"
}

detect_origin_default_branch() {
  local origin_head
  origin_head=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n "$origin_head" ]]; then
    echo "${origin_head#origin/}"
    return
  fi

  git for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | sed -n 's#^origin/##p' \
    | grep -v '^HEAD$' \
    | head -n 1
}

has_commits() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

ensure_main_branch() {
  local branch
  branch=$(current_branch)

  if [[ -n "$branch" ]]; then
    if [[ "$branch" != "main" ]]; then
      git branch -M main
    fi
    return
  fi

  if has_commits; then
    git checkout -B main
  else
    git symbolic-ref HEAD refs/heads/main
  fi
}

ensure_initial_commit() {
  if has_commits; then
    return
  fi

  stage_all_changes
  if git diff --cached --quiet; then
    git commit --allow-empty -m "Committed By bucksh0t"
  else
    git commit -m "Committed By bucksh0t"
  fi
}

create_repo() {
  if ! command -v gh >/dev/null 2>&1; then
    log_err "GitHub CLI (gh) is required. Install with: brew install gh"
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    log_err "You are not logged in to gh. Run: gh auth login"
    exit 1
  fi

  parse_create_args "$@"

  local top repo_name create_flag
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    top=$(git rev-parse --show-toplevel)
  else
    top="$PWD"
    git init "$top"
  fi

  cd "$top"
  repo_name=$(basename "$top")

  ensure_main_branch
  ensure_initial_commit

  title "Create Repo"
  kv "Name" "$repo_name"
  kv "Path" "$top"
  kv "Branch" "main"
  kv "Visibility" "$CREATE_VISIBILITY"
  kv "Description" "$CREATE_DESC"
  echo

  if git remote get-url origin >/dev/null 2>&1; then
    log_warn "Remote 'origin' already exists. Skipping gh repo create."
  else
    if [[ "$CREATE_VISIBILITY" == "public" ]]; then
      create_flag="--public"
    else
      create_flag="--private"
    fi

    gh repo create "$repo_name" "$create_flag" --source "$top" --remote origin --description "$CREATE_DESC"
  fi

  log_ok "Repository created and 'origin' is configured. No push was performed."
}

apply_gitignore_to_tracked_files() {
  local -a tracked_ignored=()
  local path

  while IFS= read -r -d '' path; do
    tracked_ignored+=("$path")
  done < <(git ls-files -ci --exclude-standard -z)

  if [[ ${#tracked_ignored[@]} -eq 0 ]]; then
    return
  fi

  title "Ignore Sync"
  kv "Action" "Removing ignored tracked files from index"
  kv "Count" "${#tracked_ignored[@]}"
  git rm -r --cached -- "${tracked_ignored[@]}" >/dev/null
  log_ok ".gitignore now applies to previously tracked files."
  echo
}

stage_all_changes() {
  apply_gitignore_to_tracked_files
  git add -A
}

ensure_push_ready_after_clone() {
  local branch target_branch
  local has_local_head="false"
  branch=$(current_branch)
  target_branch=$(detect_origin_default_branch)

  if [[ -z "$target_branch" ]]; then
    log_err "Could not detect any remote branch under origin after clone."
    exit 1
  fi

  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    has_local_head="true"
  fi

  if [[ -z "$branch" || "$has_local_head" != "true" ]]; then
    git checkout -B "$target_branch" "origin/$target_branch"
    branch="$target_branch"
  elif ! origin_branch_exists "$branch"; then
    if [[ "$branch" != "$target_branch" ]] && origin_branch_exists "$target_branch"; then
      git checkout -B "$target_branch" "origin/$target_branch"
      branch="$target_branch"
    else
      log_warn "No remote branch origin/${branch}. Upstream not set."
      return
    fi
  fi

  if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    if origin_branch_exists "$branch"; then
      git branch --set-upstream-to "origin/$branch" "$branch" >/dev/null
    else
      log_warn "No remote branch origin/${branch}. Upstream not set."
    fi
  fi
}

clone_repo() {
  if ! command -v gh >/dev/null 2>&1; then
    log_err "GitHub CLI (gh) is required. Install with: brew install gh"
    exit 1
  fi

  parse_clone_args "$@"

  local target_dir
  if [[ -n "$CLONE_DIR" ]]; then
    target_dir="$CLONE_DIR"
  else
    target_dir=$(infer_clone_dir "$CLONE_REPO")
  fi

  title "Clone Repo"
  kv "Repository" "$CLONE_REPO"
  kv "Directory" "$target_dir"
  echo

  local -a clone_cmd=(gh repo clone "$CLONE_REPO")
  if [[ -n "$CLONE_DIR" ]]; then
    clone_cmd+=("$CLONE_DIR")
  fi
  if [[ ${#CLONE_GH_FLAGS[@]} -gt 0 ]]; then
    clone_cmd+=("${CLONE_GH_FLAGS[@]}")
  fi
  if [[ ${#CLONE_GIT_FLAGS[@]} -gt 0 ]]; then
    clone_cmd+=(-- "${CLONE_GIT_FLAGS[@]}")
  fi

  "${clone_cmd[@]}"

  if [[ ! -d "$target_dir/.git" ]]; then
    log_err "Clone completed but target repo not found at: $target_dir"
    exit 1
  fi

  cd "$target_dir"
  require_git_repo
  require_origin
  ensure_push_ready_after_clone
  repo_info

  log_ok "Clone ready for 'github push'."
}

push_changes() {
  require_git_repo
  require_origin

  local branch target_branch
  branch=$(current_branch)
  if [[ -z "$branch" ]]; then
    log_err "Detached HEAD. Checkout a branch before pushing."
    exit 1
  fi

  parse_push_args "$@"
  if [[ -n "$PUSH_BRANCH_OVERRIDE" ]]; then
    target_branch="$PUSH_BRANCH_OVERRIDE"
  else
    target_branch="$branch"
  fi

  stage_all_changes

  repo_info
  print_status
  print_staged_summary

  if git diff --cached --quiet; then
    log_warn "No changes to commit."
  else
    git commit -m "$PUSH_MSG"
  fi

  local push_label="origin/${target_branch}"
  if [[ "$PUSH_FORCE" == "true" ]]; then
    log_warn "WARNING: --force will overwrite remote history on ${push_label}."
  fi

  if [[ "$branch" != "$target_branch" ]]; then
    kv "Push From" "$branch"
    kv "Push To" "$push_label"
    echo
  fi

  read -r -p "Push to ${push_label}? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_warn "Push cancelled."
    exit 0
  fi

  if [[ "$branch" == "$target_branch" ]]; then
    if [[ "$PUSH_FORCE" == "true" ]]; then
      git push -u origin "$branch" --force
    else
      git push -u origin "$branch"
    fi
  else
    if [[ "$PUSH_FORCE" == "true" ]]; then
      git push origin "HEAD:${target_branch}" --force
    else
      git push origin "HEAD:${target_branch}"
    fi
  fi

  log_ok "Push completed to ${push_label}."
}

wipe_history() {
  require_git_repo
  require_origin

  local current target_branch
  current=$(current_branch)

  parse_wipe_args "$@"

  target_branch=$(resolve_target_branch "$WIPE_BRANCH_OVERRIDE")
  if [[ -z "$target_branch" ]]; then
    log_err "Could not determine target branch. Use: github wipe --branch <name>"
    exit 1
  fi

  repo_info
  title "Wipe"
  kv "Target" "$target_branch"
  kv "Current" "${current:-"(detached)"}"
  echo

  print_status
  log_warn "This will rewrite history on origin/${target_branch} and cannot be undone."
  read -r -p "Wipe origin/${target_branch}? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_warn "Wipe cancelled."
    exit 0
  fi

  local wipe_branch="__wipe__$(date +%s)"
  git checkout --orphan "$wipe_branch"
  stage_all_changes
  print_staged_summary

  if git diff --cached --quiet; then
    git commit --allow-empty -m "$WIPE_MSG"
  else
    git commit -m "$WIPE_MSG"
  fi

  # Move target branch to the new root commit and clean up temp branch
  git checkout -B "$target_branch"
  git branch -D "$wipe_branch" >/dev/null 2>&1 || true

  git push -u origin HEAD:"$target_branch" --force
  log_ok "History wiped and pushed to ${target_branch}."
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

cmd="$1"
shift

case "$cmd" in
  list)
    if [[ $# -gt 0 ]]; then
      log_err "Unknown arguments for list: $*"
      usage
      exit 1
    fi
    list_changes
    ;;
  clone)
    clone_repo "$@"
    ;;
  push)
    push_changes "$@"
    ;;
  wipe)
    wipe_history "$@"
    ;;
  create)
    create_repo "$@"
    ;;
  help|-h|--help)
    usage
    exit 0
    ;;
  *)
    log_err "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
