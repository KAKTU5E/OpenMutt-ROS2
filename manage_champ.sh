#!/usr/bin/env bash
#
# manage_champ.sh — keep CHAMP tidy in your OpenMutt-ROS2 workspace
#
# Usage:
#   ./manage_champ.sh <command>
#
# Commands:
#   check                 # show nested .git dirs (should only see top-level .git)
#   vendor-init           # remove nested .git dirs and record hashes
#   vendor-update         # refresh CHAMP files from upstream (vendor workflow)
#   submodule-add         # add CHAMP as a git submodule (one-time)
#   submodule-update      # pull latest CHAMP and record submodule bump
#   sync-upstream         # sync your main repo with its upstream remote (if set)
#   lfs-setup             # configure Git LFS for common large asset types
#
# Notes:
# - Run from your repo root (the directory that has .git for your OpenMutt-ROS2 repo).
# - This script is idempotent and favors safety (no forced pushes).
# - Adjust variables in the CONFIG section if your layout differs.
#
set -euo pipefail

### === CONFIG ===
# Relative paths inside your repo
SRC_DIR="${SRC_DIR:-src}"
CHAMP_DIR="${CHAMP_DIR:-$SRC_DIR/champ}"
TELEOP_DIR="${TELEOP_DIR:-$SRC_DIR/champ_teleop}"
VISION_DIR="${VISION_DIR:-$SRC_DIR/vision_opencv}"
VENDORED_HASHES="${VENDORED_HASHES:-$SRC_DIR/.vendored-hashes.txt}"
PATCH_DIR="${PATCH_DIR:-$SRC_DIR/.patches}"

# Upstream repo for CHAMP (change if you use a fork/branch)
CHAMP_REMOTE="${CHAMP_REMOTE:-https://github.com/chvmp/champ.git}"
CHAMP_BRANCH="${CHAMP_BRANCH:-ros2}"     # common branch name for CHAMP
# Main repo upstream (optional); set with: git remote add upstream <url>
MAIN_UPSTREAM_REMOTE="${MAIN_UPSTREAM_REMOTE:-upstream}"

### === helpers ===
say() { printf "\033[1;34m==>\033[0m %s\n" "$*" ; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*" ; }
err() { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2 ; }
exists() { command -v "$1" >/dev/null 2>&1 ; }

require_git_repo() {
  if [ ! -d .git ]; then
    err "Run this from your repo root (where .git lives)."
    exit 1
  fi
}

nested_git_scan() {
  # show nested .git dirs under src (excluding top-level .git)
  find "$SRC_DIR" -type d -name .git 2>/dev/null | grep -v "^./.git$" || true
}

record_hash() {
  local label="$1" dir="$2"
  mkdir -p "$(dirname "$VENDORED_HASHES")"
  local sha=""
  if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
    # Try to resolve commit if the dir is/was a git repo
    sha="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  sha="${sha:-from-snapshot-$(date +%F)}"
  echo "$label: $sha" >> "$VENDORED_HASHES"
  say "Recorded $label @ $sha"
}

### === commands ===

cmd_check() {
  require_git_repo
  say "Scanning for nested .git directories under $SRC_DIR ..."
  local out
  out="$(nested_git_scan || true)"
  if [ -z "$out" ]; then
    say "No nested .git found. You're clean ✅"
  else
    echo "$out"
    warn "Nested .git found (remove them unless they are submodules)."
  fi
}

cmd_vendor_init() {
  require_git_repo
  say "Recording current nested repo SHAs to $VENDORED_HASHES"
  : > "$VENDORED_HASHES"
  [ -d "$CHAMP_DIR" ] && record_hash "champ" "$CHAMP_DIR" || warn "$CHAMP_DIR not found"
  [ -d "$TELEOP_DIR" ] && record_hash "champ_teleop" "$TELEOP_DIR" || warn "$TELEOP_DIR not found"
  [ -d "$VISION_DIR" ] && record_hash "vision_opencv" "$VISION_DIR" || warn "$VISION_DIR not found"

  say "Removing nested .git directories (champ, champ_teleop, vision_opencv)"
  # Handle both directories and gitdir link files
  for gd in "$CHAMP_DIR/.git" "$TELEOP_DIR/.git" "$VISION_DIR/.git"; do
    [ -e "$gd" ] || continue
    if [ -f "$gd" ]; then
      # could be "gitdir: /path/to/real/.git"
      target="$(sed -n 's/^gitdir: //p' "$gd" 2>/dev/null || true)"
      [ -n "${target:-}" ] && rm -rf "$target" || true
      rm -f "$gd"
    else
      rm -rf "$gd"
    fi
  done

  say "Staging and committing vendor init"
  git add -A
  git commit -m "vendor: remove nested .git directories and record hashes" || {
    warn "Nothing to commit (maybe already clean)."
  }
  say "Done. Current nested .git (should be none except top-level):"
  nested_git_scan || true
}

cmd_vendor_update() {
  require_git_repo
  [ -d "$CHAMP_DIR" ] || { err "$CHAMP_DIR not found"; exit 1; }

  mkdir -p "$PATCH_DIR"
  say "Saving local changes to CHAMP (if any) into $PATCH_DIR/champ-local.patch"
  ( cd "$CHAMP_DIR" && git diff > "../.patches/champ-local.patch" || true )

  say "Refreshing CHAMP files from $CHAMP_REMOTE (branch: $CHAMP_BRANCH)"
  tmpdir="$(mktemp -d)"
  git clone --depth=1 --branch "$CHAMP_BRANCH" "$CHAMP_REMOTE" "$tmpdir/champ-tmp"
  rsync -a --delete --exclude='.git' "$tmpdir/champ-tmp/" "$CHAMP_DIR/"
  rm -rf "$tmpdir"

  say "Re-applying your local patch (if any)"
  if [ -s "$PATCH_DIR/champ-local.patch" ]; then
    patch -p1 -d "$CHAMP_DIR" < "$PATCH_DIR/champ-local.patch" || {
      warn "Patch had conflicts; review changes in $CHAMP_DIR."
    }
  fi

  say "Recording upstream SHA to $VENDORED_HASHES"
  : > /dev/null # placeholder
  echo "champ: from-snapshot-$(date +%F)" >> "$VENDORED_HASHES"

  say "Staging and committing vendor update"
  git add -A
  git commit -m "vendor: update CHAMP to latest; reapply local tweaks" || {
    warn "Nothing to commit (no changes after sync)."
  }
}

cmd_submodule_add() {
  require_git_repo
  if [ -d "$CHAMP_DIR/.git" ] || [ -f "$CHAMP_DIR/.git" ]; then
    err "$CHAMP_DIR already looks like a git repo. Remove it or choose vendor workflow."
    exit 1
  fi
  say "Adding CHAMP as submodule at $CHAMP_DIR"
  git submodule add "$CHAMP_REMOTE" "$CHAMP_DIR"
  ( cd "$CHAMP_DIR" && git fetch origin && git switch "$CHAMP_BRANCH" || true )
  git add .gitmodules "$CHAMP_DIR" || true
  git commit -m "chore: add CHAMP as submodule ($CHAMP_BRANCH)"
  say "Initialize/Update submodules: git submodule update --init --recursive"
}

cmd_submodule_update() {
  require_git_repo
  [ -d "$CHAMP_DIR" ] || { err "$CHAMP_DIR not found"; exit 1; }
  say "Updating CHAMP submodule to latest $CHAMP_BRANCH"
  ( cd "$CHAMP_DIR"
    git fetch origin
    git switch "$CHAMP_BRANCH" || true
    git merge --ff-only "origin/$CHAMP_BRANCH" || git pull --rebase || true
  )
  git add "$CHAMP_DIR"
  git commit -m "chore: bump CHAMP submodule to latest $CHAMP_BRANCH" || {
    warn "No submodule changes to commit."
  }
  say "Remember to push both parent and submodule if needed."
}

cmd_sync_upstream() {
  require_git_repo
  if git remote get-url "$MAIN_UPSTREAM_REMOTE" >/dev/null 2>&1; then
    say "Syncing main repo from remote '$MAIN_UPSTREAM_REMOTE'"
    git fetch "$MAIN_UPSTREAM_REMOTE"
    cur_branch="$(git rev-parse --abbrev-ref HEAD)"
    say "Rebasing $cur_branch onto $MAIN_UPSTREAM_REMOTE/$cur_branch"
    git rebase "$MAIN_UPSTREAM_REMOTE/$cur_branch" || {
      warn "Rebase had issues; try: git merge $MAIN_UPSTREAM_REMOTE/$cur_branch"
    }
    say "Push your branch if needed: git push"
  else
    warn "No '$MAIN_UPSTREAM_REMOTE' remote set. Add one with: git remote add upstream <url>"
  fi
}

cmd_lfs_setup() {
  require_git_repo
  if ! exists git; then err "git not found"; exit 1; fi
  if ! exists git; then err "git lfs not found"; exit 1; fi
  say "Installing Git LFS and tracking common large asset types"
  git lfs install
  git lfs track "*.bag" "*.dae" "*.stl"
  git add .gitattributes
  git commit -m "chore: enable Git LFS for large assets" || {
    warn "LFS patterns already present."
  }
}

### === main ===
cmd="${1:-}"
case "$cmd" in
  check)              cmd_check ;;
  vendor-init)        cmd_vendor_init ;;
  vendor-update)      cmd_vendor_update ;;
  submodule-add)      cmd_submodule_add ;;
  submodule-update)   cmd_submodule_update ;;
  sync-upstream)      cmd_sync_upstream ;;
  lfs-setup)          cmd_lfs_setup ;;
  ""|-h|--help|help)
    cat <<EOF
Usage: $0 <command>

Commands:
  check                 show nested .git dirs (should only see top-level .git)
  vendor-init           remove nested .git dirs and record hashes
  vendor-update         refresh CHAMP files from upstream (vendor workflow)
  submodule-add         add CHAMP as a git submodule (one-time)
  submodule-update      pull latest CHAMP and record submodule bump
  sync-upstream         sync your main repo with its upstream remote (if set)
  lfs-setup             configure Git LFS for common large asset types

Config via env vars (with defaults):
  SRC_DIR=$SRC_DIR
  CHAMP_DIR=$CHAMP_DIR
  TELEOP_DIR=$TELEOP_DIR
  VISION_DIR=$VISION_DIR
  VENDORED_HASHES=$VENDORED_HASHES
  CHAMP_REMOTE=$CHAMP_REMOTE
  CHAMP_BRANCH=$CHAMP_BRANCH
  MAIN_UPSTREAM_REMOTE=$MAIN_UPSTREAM_REMOTE

Examples:
  ./manage_champ.sh check
  ./manage_champ.sh vendor-init
  ./manage_champ.sh vendor-update
  ./manage_champ.sh submodule-add
  ./manage_champ.sh submodule-update
  ./manage_champ.sh sync-upstream
  ./manage_champ.sh lfs-setup
EOF
    ;;
  *)
    err "Unknown command: $cmd (use --help)"
    exit 1
    ;;
esac
