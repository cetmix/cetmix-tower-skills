#!/usr/bin/env bash
#
# Install the Cetmix Tower skills into a project or into your user config.
#
#   ./install.sh --user               # link into ~/.claude and ~/.cursor (no path allowed)
#   ./install.sh /path/to/project     # link into a project
#   ./install.sh --copy /path/to/proj # copy instead of symlink (Windows, CI, containers)
#   ./install.sh --link /path/to/proj # symlink explicitly (the default; undoes an earlier
#                                     #  --copy on the same command line)
#   ./install.sh --agents /path       # also link AGENTS.md at the target root
#                                     # (with --user the target root is $HOME, so
#                                     #  --user --agents creates $HOME/AGENTS.md)
#   ./install.sh --uninstall --user   # remove a user install
#   ./install.sh --uninstall /path    # remove a project install
#   ./install.sh --force /path        # also replace/remove real (non-symlink) paths
#
# Safety: a destination that is a symlink is replaced without asking (it is ours).
# A destination that is a real file or directory — your own skill of the same name, or a
# previous --copy install — is left untouched and reported, unless you pass --force.
#
# --uninstall never deletes a real AGENTS.md at the target root, not even with --force,
# because it is far more likely to be yours than ours. After a --copy --agents install,
# remove that file by hand; the script says so when it skips it.
#
# Creates:
#   <target>/.claude/skills/cetmix-tower*        -> skills/*        (Claude Code)
#   <target>/.cursor/skills/cetmix-tower*        -> skills/*        (Cursor)
#   <target>/.cursor/rules/cetmix-tower.mdc      -> rules/*.mdc     (Cursor)
#   <target>/AGENTS.md                           -> AGENTS.md       (with --agents)
#
# No paths are baked in: everything is resolved relative to this script at run time.

set -euo pipefail

ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="link"
SCOPE="project"
LINK_AGENTS="no"
ACTION="install"
FORCE="no"
TARGET=""
SKIPPED=0

while [ $# -gt 0 ]; do
    case "$1" in
        --copy)      MODE="copy" ;;
        --link)      MODE="link" ;;
        --user)      SCOPE="user" ;;
        --agents)    LINK_AGENTS="yes" ;;
        --uninstall) ACTION="uninstall" ;;
        --force)     FORCE="yes" ;;
        # Prints the header comment block: everything from line 2 down to the line
        # before `set -euo pipefail`. Derived, so adding a line above cannot desync it.
        -h|--help)   sed -n "2,$(($(grep -n '^set -euo pipefail' "${BASH_SOURCE[0]}" | head -1 | cut -d: -f1) - 2))p" \
                         "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)          echo "Unknown option: $1" >&2; exit 2 ;;
        *)           TARGET="$1" ;;
    esac
    shift
done

if [ "$SCOPE" = "user" ] && [ -n "$TARGET" ]; then
    echo "--user installs into \$HOME (~/.claude, ~/.cursor); it cannot take a path." >&2
    echo "Drop '$TARGET' to install for your user, or drop --user to install into it." >&2
    exit 2
fi

if [ "$SCOPE" = "user" ]; then
    CLAUDE_ROOT="$HOME/.claude"
    CURSOR_ROOT="$HOME/.cursor"
    TARGET_ROOT="$HOME"
else
    if [ -z "$TARGET" ]; then
        echo "Pass a project path, or --user to install into ~/.claude and ~/.cursor." >&2
        echo "See --help." >&2
        exit 2
    fi
    TARGET="$(cd "$TARGET" && pwd)"
    CLAUDE_ROOT="$TARGET/.claude"
    CURSOR_ROOT="$TARGET/.cursor"
    TARGET_ROOT="$TARGET"
fi

# Relative symlink target when python3 is available, absolute otherwise.
relpath() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$2"
    else
        printf '%s\n' "$1"
    fi
}

# Remove a destination that is in our way.
# Symlinks are ours, so they go without asking. Real files and directories are only
# removed with --force: they may be the user's own same-named skill, not a prior install.
# Returns 1 when the destination was left in place.
clear_dest() {
    local dest="$1" what="$2"

    if [ -L "$dest" ]; then
        rm -f "$dest"
        return 0
    fi

    if [ -e "$dest" ]; then
        if [ "$FORCE" = "yes" ]; then
            rm -rf "$dest"
            return 0
        fi
        echo "  SKIPPED $dest"
        echo "          exists and is not a symlink; not $what it."
        echo "          Move it aside, or re-run with --force to replace it."
        SKIPPED=$((SKIPPED + 1))
        return 1
    fi

    return 0
}

install_one() {
    # $1 = source path, $2 = destination path
    local src="$1" dest="$2" dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"

    clear_dest "$dest" "overwriting" || return 0

    if [ "$MODE" = "copy" ]; then
        cp -R "$src" "$dest"
        echo "  copied  $dest"
    else
        ln -s "$(relpath "$src" "$dest_dir")" "$dest"
        echo "  linked  $dest"
    fi
}

uninstall_one() {
    local dest="$1"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        clear_dest "$dest" "removing" || return 0
        echo "  removed $dest"
    fi
}

SKILLS=()
while IFS= read -r d; do SKILLS+=("$d"); done < <(
    find "$ASSETS_DIR/skills" -mindepth 1 -maxdepth 1 -type d | sort
)

RULES=()
while IFS= read -r f; do RULES+=("$f"); done < <(
    find "$ASSETS_DIR/rules" -mindepth 1 -maxdepth 1 -name '*.mdc' | sort
)

if [ "$ACTION" = "uninstall" ]; then
    echo "Removing Cetmix Tower skills from $TARGET_ROOT"
    for s in "${SKILLS[@]}"; do
        name="$(basename "$s")"
        uninstall_one "$CLAUDE_ROOT/skills/$name"
        uninstall_one "$CURSOR_ROOT/skills/$name"
    done
    for r in "${RULES[@]}"; do
        uninstall_one "$CURSOR_ROOT/rules/$(basename "$r")"
    done
    # Only ever remove a symlinked AGENTS.md. A real file at the target root is much more
    # likely to be the user's own than a --copy install of ours, so --force does not apply.
    if [ -L "$TARGET_ROOT/AGENTS.md" ]; then
        uninstall_one "$TARGET_ROOT/AGENTS.md"
    elif [ -e "$TARGET_ROOT/AGENTS.md" ]; then
        echo "  SKIPPED $TARGET_ROOT/AGENTS.md"
        echo "          is a real file, not a symlink. If it came from --copy --agents,"
        echo "          delete it by hand; if it is yours, leave it."
    fi
    echo "Done."
    exit 0
fi

echo "Installing Cetmix Tower skills ($MODE) into $TARGET_ROOT"

echo "Claude Code skills:"
for s in "${SKILLS[@]}"; do
    install_one "$s" "$CLAUDE_ROOT/skills/$(basename "$s")"
done

echo "Cursor skills:"
for s in "${SKILLS[@]}"; do
    install_one "$s" "$CURSOR_ROOT/skills/$(basename "$s")"
done

echo "Cursor rules:"
for r in "${RULES[@]}"; do
    install_one "$r" "$CURSOR_ROOT/rules/$(basename "$r")"
done

if [ "$LINK_AGENTS" = "yes" ]; then
    echo "AGENTS.md:"
    if [ -e "$TARGET_ROOT/AGENTS.md" ] && [ ! -L "$TARGET_ROOT/AGENTS.md" ]; then
        echo "  SKIPPED $TARGET_ROOT/AGENTS.md already exists and is not a symlink."
        echo "          Add this line to it manually:"
        echo "          See this repository's AGENTS.md for Cetmix Tower entity authoring rules."
    else
        install_one "$ASSETS_DIR/AGENTS.md" "$TARGET_ROOT/AGENTS.md"
    fi
fi

if [ "$SKIPPED" -gt 0 ]; then
    echo
    echo "$SKIPPED destination(s) were left untouched because they are real files or"
    echo "directories, not symlinks from a previous install. Re-run with --force to"
    echo "replace them (this also applies when refreshing an earlier --copy install)."
fi

cat <<'EOF'

Done. Next steps:
  - Claude Code: restart the session, then run /doctor or ask "what skills do you have?"
    to confirm the cetmix-tower skills are loaded.
  - Cursor: the rule is Agent Requested by default. To make it always-on, set
    alwaysApply: true in .cursor/rules/cetmix-tower.mdc.
  - Other agents: point them at this repository's AGENTS.md.
EOF
