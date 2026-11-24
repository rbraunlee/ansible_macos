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
#
# On a terminal it asks for your sudo password once, checks it with sudo, and
# hands it to the playbook as ansible_become_password, which Homebrew casks
# that need root use. Without a terminal it falls back to --ask-become-pass.

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

# The sudo password, asked for once. It stays in this shell (never exported,
# never on a command line, never on disk) and only ansible-playbook gets it,
# through its own environment (see step 5).
BECOME_PASS=""
SUDO_TRIES=3

# Feed BECOME_PASS to `sudo -v` on stdin. That checks it and refreshes the
# sudo timestamp, so the Homebrew installer does not ask again. sudo's error
# messages go to stdout, for the caller to show.
sudo_validate() {
    printf '%s\n' "$BECOME_PASS" | sudo -S -p '' -v 2>&1
}

ask_sudo_password() {
    local attempt sudo_err="" nl=$'\n'
    # Forget any cached sudo timestamp, so the check below tests the password.
    sudo -k
    for (( attempt = 1; attempt <= SUDO_TRIES; attempt++ )); do
        BECOME_PASS=""
        if ! IFS= read -r -s -p "[SUDO] Password for $(id -un) (for sudo and Homebrew casks): " BECOME_PASS; then
            echo >&2
            die "No password entered."
        fi
        echo >&2
        if [[ -z "$BECOME_PASS" ]]; then
            echo "[SUDO] The password is empty." >&2
        elif sudo_err="$(sudo_validate)"; then
            echo "[DONE] sudo password accepted."
            return 0
        else
            echo "[SUDO] sudo rejected the password (attempt $attempt of $SUDO_TRIES)." >&2
        fi
    done
    BECOME_PASS=""
    die "No valid sudo password after $SUDO_TRIES attempts.${sudo_err:+ Last sudo message: ${sudo_err##*"$nl"}}"
}

echo "--- Starting macOS Bootstrap ---"

if [[ -t 0 ]]; then
    ask_sudo_password
else
    echo "[WARN] No terminal on stdin, so the sudo password is not asked for up front."
    echo "       ansible-playbook will ask for it (--ask-become-pass), but Homebrew casks"
    echo "       will not get it and casks that need sudo may fail."
fi

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
    # Refresh the sudo timestamp (it lapses during a long Xcode install) so the
    # installer's own sudo call does not prompt. Failure here is harmless: the
    # installer then just asks itself.
    if [[ -n "$BECOME_PASS" ]]; then
        sudo_validate > /dev/null || true
    fi
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
# Extra args come last, so a user's own -e or -K still wins.
if [[ -n "$BECOME_PASS" ]]; then
    # -K would not help here: ansible-core keeps that value away from tasks,
    # so homebrew_cask's sudo_password could never see it. Instead the password
    # goes into ansible-playbook's environment only (the VAR=value prefix does
    # not export it from this shell), and ansible_become_password reads it
    # with the env lookup. It is not on any command line and not on disk. A
    # lookup result is not templated again, so a password containing "{{" is
    # safe.
    BOOTSTRAP_BECOME_PASS="$BECOME_PASS" ansible-playbook main.yml \
        -e '{"ansible_become_password": "{{ lookup(\"ansible.builtin.env\", \"BOOTSTRAP_BECOME_PASS\") }}"}' \
        ${1+"$@"}
else
    ansible-playbook main.yml --ask-become-pass ${1+"$@"}
fi
BECOME_PASS=""
unset BECOME_PASS

echo "--- Bootstrap Complete ---"
