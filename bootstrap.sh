#!/bin/bash
#
# Bootstrap a fresh Mac: Xcode Command Line Tools, Homebrew, Ansible and the
# Galaxy collections in requirements.yml, then run main.yml.
#
# Usage: ./bootstrap.sh [extra ansible-playbook args]
#   e.g. ./bootstrap.sh --check -v
#        ./bootstrap.sh --tags dock
#
# Works from any directory: it changes to the directory that holds this script.

set -euo pipefail

# Resolve symlinks by hand: macOS ships bash 3.2 and older readlink has no -f.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    link_dir="$(cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink -- "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" == /* ]] || SCRIPT_PATH="$link_dir/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
cd -- "$SCRIPT_DIR"

# How long to wait for the Xcode CLT installer when there is no terminal to
# prompt on (seconds).
XCODE_CLT_TIMEOUT="${XCODE_CLT_TIMEOUT:-1800}"

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

echo "--- Starting macOS Bootstrap ---"

# 1. Xcode Command Line Tools
if ! xcode-select -p &> /dev/null; then
    echo "[SETUP] Installing Xcode Command Line Tools..."
    # Fails if an install is already pending; the checks below cover that.
    xcode-select --install || true

    if [[ -t 0 ]]; then
        echo "[WAIT] Finish the Apple installation dialog."
        read -r -p "       Press Enter once the installer has finished... "
    else
        echo "[WAIT] Waiting up to ${XCODE_CLT_TIMEOUT}s for the Apple installation dialog to finish..."
        waited=0
        until xcode-select -p &> /dev/null || (( waited >= XCODE_CLT_TIMEOUT )); do
            sleep 5
            waited=$(( waited + 5 ))
        done
    fi

    if ! xcode-select -p &> /dev/null; then
        die "Xcode Command Line Tools are still missing. Install them with 'xcode-select --install' and re-run this script."
    fi
    echo "[DONE] Xcode Command Line Tools installed."
fi

# 2. Homebrew
# Look at the known prefixes directly: on a fresh Apple Silicon shell brew is
# installed but not yet on PATH, so `command -v brew` alone is not enough.
find_brew() {
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    command -v brew 2> /dev/null
}

if BREW_BIN="$(find_brew)"; then
    echo "[SKIP] Homebrew already installed at $BREW_BIN."
else
    echo "[INSTALL] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    BREW_BIN="$(find_brew)" || die "Homebrew installation finished but no brew binary was found."
fi

# Activate Homebrew for this script.
eval "$("$BREW_BIN" shellenv)"

# Persist it for login shells. The dotfiles do not ship a .zprofile and their
# .zshrc expects brew to already be on PATH, so this layer owns it.
ZPROFILE="$HOME/.zprofile"
SHELLENV_LINE="eval \"\$($BREW_BIN shellenv)\""
if [[ -f "$ZPROFILE" ]] && grep -qF -- "$SHELLENV_LINE" "$ZPROFILE"; then
    echo "[SKIP] Homebrew shellenv already in $ZPROFILE."
else
    echo "[SETUP] Adding Homebrew shellenv to $ZPROFILE..."
    printf '\n# Added by ansible_macos bootstrap.sh\n%s\n' "$SHELLENV_LINE" >> "$ZPROFILE"
fi

# 3. Ansible
if ! command -v ansible-playbook &> /dev/null; then
    echo "[INSTALL] Installing Ansible via Homebrew..."
    brew install ansible
else
    echo "[SKIP] Ansible already installed."
fi

# 4. Galaxy collections (pinned in requirements.yml)
echo "[GALAXY] Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r requirements.yml

# 5. Playbook
echo "[RUN] Executing Ansible Playbook..."
# ${1+"$@"}: bash 3.2 (macOS /bin/bash) treats an empty "$@" as unbound under set -u.
ansible-playbook main.yml --ask-become-pass ${1+"$@"}

echo "--- Bootstrap Complete ---"
