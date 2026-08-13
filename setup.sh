#!/usr/bin/env bash
#
# Setup script for the clickhouse bag.
#
# Clones ClickHouse/agent-skills into a sibling directory (../clickhouse-skills)
# and symlinks every skill into this bag's skills/clickhouse/ folder.
#
# Re-run at any time to pull updates and pick up new skills.
#
# Usage:
#   ./setup.sh            # clone or pull, then symlink
#   ./setup.sh --status   # show what's linked
#
set -euo pipefail

BAG_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_REPO="https://github.com/ClickHouse/agent-skills.git"
SKILLS_DIR="$BAG_DIR/../clickhouse-skills"
SKILLS_TARGET="$BAG_DIR/skills/clickhouse"

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mwarn:\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31merror:\033[0m %s\n" "$*" >&2; exit 1; }

# ── Clone or update ─────────────────────────────────────────────────────────

clone_or_update() {
  if [[ -d "$SKILLS_DIR/.git" ]]; then
    log "Updating clickhouse-skills (git pull)..."
    git -C "$SKILLS_DIR" pull --ff-only --quiet
  else
    log "Cloning ClickHouse/agent-skills -> $SKILLS_DIR ..."
    git clone "$SKILLS_REPO" "$SKILLS_DIR"
  fi
}

# ── Symlink skills ──────────────────────────────────────────────────────────

link_skills() {
  local linked=0
  local skipped=0

  mkdir -p "$SKILLS_TARGET"

  # Skills live under skills/ in the agent-skills repo
  local search_dir="$SKILLS_DIR/skills"
  if [[ ! -d "$search_dir" ]]; then
    # Fallback: skills might be at repo root
    search_dir="$SKILLS_DIR"
  fi

  for skill_dir in "$search_dir"/*/; do
    [[ ! -d "$skill_dir" ]] && continue

    local name
    name="$(basename "$skill_dir")"

    # Skip dotfiles and non-skill directories
    [[ "$name" == .* ]] && continue
    [[ ! -f "$skill_dir/SKILL.md" ]] && continue

    local link_path="$SKILLS_TARGET/$name"

    # Remove stale symlinks
    if [[ -L "$link_path" ]] && [[ ! -e "$link_path" ]]; then
      rm "$link_path"
    fi

    # Create or update symlink
    if [[ -L "$link_path" ]]; then
      local current_target
      current_target="$(readlink "$link_path")"
      if [[ "$current_target" != "$skill_dir" && "$current_target" != "${skill_dir%/}" ]]; then
        rm "$link_path"
        ln -s "$skill_dir" "$link_path"
      fi
    elif [[ -d "$link_path" ]]; then
      warn "Skipping $name — directory exists (not a symlink)"
      skipped=$((skipped + 1))
      continue
    else
      ln -s "$skill_dir" "$link_path"
    fi

    linked=$((linked + 1))
  done

  log "Linked $linked skills ($skipped skipped)"
}

# ── Status ──────────────────────────────────────────────────────────────────

show_status() {
  printf "\n\033[1m%-40s %-10s %s\033[0m\n" "Skill" "Type" "Target"
  printf "%s\n" "$(printf '%.0s─' {1..90})"

  if [[ ! -d "$SKILLS_TARGET" ]]; then
    printf "  (no skills linked — run ./setup.sh first)\n"
    return
  fi

  for item in "$SKILLS_TARGET"/*/; do
    [[ ! -d "$item" ]] && continue
    local name canonical
    name="$(basename "$item")"
    canonical="${item%/}"

    if [[ -L "$canonical" ]]; then
      local target
      target="$(readlink "$canonical")"
      printf "%-40s %-10s %s\n" "$name" "symlink" "$target"
    else
      printf "%-40s %-10s %s\n" "$name" "native" "-"
    fi
  done
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  if [[ "${1:-}" == "--status" ]]; then
    show_status
    exit 0
  fi

  clone_or_update
  link_skills

  printf "\n"
  show_status
  printf "\n\033[1;32mDone.\033[0m Run \`./setup.sh --status\` to check at any time.\n"
}

main "$@"
