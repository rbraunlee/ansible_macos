# ansible_macos

Bootstrap a new macOS machine with Homebrew, Ansible, and a dotfiles repository.

A single script (`bootstrap.sh`) prepares the machine and runs an Ansible playbook (`main.yml`) that:

- installs Homebrew formulae and casks
- sets Dock preferences (Finder settings are defined but not yet applied, see [#8](https://github.com/rbraunlee/ansible_macos/issues/8))
- configures the global Git user name and email
- clones the dotfiles repository and symlinks it into `$HOME` with GNU Stow
- installs the Zap zsh plugin manager

## Requirements

- macOS on Apple Silicon. `bootstrap.sh` handles Intel, but the playbook doesn't yet ([#6](https://github.com/rbraunlee/ansible_macos/issues/6)).
- An administrator account. The playbook asks for the sudo password, but no task uses it yet ([#7](https://github.com/rbraunlee/ansible_macos/issues/7)).
- Internet access (Homebrew, Galaxy, GitHub)

`bootstrap.sh` installs everything else it needs: Xcode Command Line Tools, Homebrew, Ansible, and the `community.general` collection.

## Usage

On a fresh Mac, the first `git` command prompts you to install the Xcode Command Line Tools. Accept the prompt, then clone:

```bash
git clone <this-repo-url> ~/ansible_macos
cd ~/ansible_macos
bash bootstrap.sh
```

Run it from the repository root. It calls `main.yml` by relative path, and the file isn't marked executable yet ([#11](https://github.com/rbraunlee/ansible_macos/issues/11)).

The script will:

1. Check for Xcode Command Line Tools and wait while the Apple installer runs, if needed.
2. Install Homebrew, if missing, and load its environment.
3. Install Ansible via Homebrew, if missing.
4. Install the `community.general` Galaxy collection.
5. Run `ansible-playbook main.yml --ask-become-pass`.

To run only the playbook (after the prerequisites exist):

```bash
ansible-playbook main.yml --ask-become-pass
```

## Repository layout

| Path | Purpose |
| --- | --- |
| `bootstrap.sh` | Entry point. Installs prerequisites and runs the playbook. |
| `main.yml` | The playbook. All tasks run against `localhost`. |
| `group_vars/all.yml` | All variables: user identity, packages, macOS settings, dotfiles location, feature flags. |
| `inventory/` | Inventory files. The playbook does not use them; see [Known issues](#known-issues). |
| `ansible.cfg` | Currently empty. |

## Configuration

Edit `group_vars/all.yml` to change what gets installed or configured.

| Key | Description |
| --- | --- |
| `user.name`, `user.email` | Written to the global Git config when `features.configure_git` is `true`. |
| `user.github_username` | **Defined but not yet used.** |
| `brew_bin` | Path the playbook checks to decide whether Homebrew is installed. |
| `setup_brew.formulae` | Command-line packages installed with `brew`. |
| `setup_brew.cask` | GUI applications and fonts installed with `brew install --cask`. Installed with `no-quarantine`. |
| `macos_settings.dock` | Dock autohide, tile size, and show-recents. |
| `macos_settings.finder` | Finder defaults. **Defined but not yet applied by the playbook.** |
| `dotfiles.repo` | Git URL of the dotfiles repository. |
| `dotfiles.dest` | Local clone location (default `~/.dotfiles`). |
| `dotfiles.subdirs` | Directories in the dotfiles repo to scan for stow packages (`common`, `macos`). |
| `dotfiles.config_destination` | Directory created as `~/.config` before stowing. |
| `features.*` | Feature flags. `configure_git` is used. `install_oh_my_zsh` is **defined but not yet used**. |

### Dotfiles layout

The playbook expects the dotfiles repository to contain one directory per application under each of `common/` and `macos/`. Each application directory is treated as a stow package and linked into `$HOME`, so its contents should mirror the paths relative to home (for example `common/nvim/.config/nvim/…`).

## Idempotency

The playbook is designed to be re-run. Homebrew packages and casks are only installed when missing (but `brew update` runs every time, which slows re-runs), `osx_defaults` and `git_config` only change values that differ, and the dotfiles repo is updated in place. Stow is run with `-R` (restow), so existing links are refreshed. Re-runs currently fail if the dotfiles clone has uncommitted changes ([#3](https://github.com/rbraunlee/ansible_macos/issues/3)).

## Known issues

Tracked on [GitHub Issues](https://github.com/rbraunlee/ansible_macos/issues). The main ones:

- [#1](https://github.com/rbraunlee/ansible_macos/issues/1) The Stow task replaces `PATH` with `$HOME`, so `/usr/bin` and `/bin` are missing while stow runs.
- [#2](https://github.com/rbraunlee/ansible_macos/issues/2) The cask install uses `--no-quarantine`, which Homebrew 5.0 deprecated.
- [#3](https://github.com/rbraunlee/ansible_macos/issues/3) Re-runs fail once the dotfiles clone has local edits.
- [#4](https://github.com/rbraunlee/ansible_macos/issues/4) The Stow `changed_when` logic reports the wrong state.
- [#5](https://github.com/rbraunlee/ansible_macos/issues/5) `inventory/vm.ini` is malformed. `host.ini` and `ansible.cfg` are empty.
- [#6](https://github.com/rbraunlee/ansible_macos/issues/6) The playbook's Homebrew install step only works on Apple Silicon and can't run non-interactively.
- [#7](https://github.com/rbraunlee/ansible_macos/issues/7) `--ask-become-pass` is prompted but never used.
- [#8](https://github.com/rbraunlee/ansible_macos/issues/8) The Finder settings are never applied.
- [#9](https://github.com/rbraunlee/ansible_macos/issues/9) `install_oh_my_zsh` and `github_username` are unused.
- [#10](https://github.com/rbraunlee/ansible_macos/issues/10) The Zap installer runs from a predictable `/tmp` path and an unpinned branch.
- [#11](https://github.com/rbraunlee/ansible_macos/issues/11) `bootstrap.sh` isn't executable, depends on the current directory, and doesn't persist brew shellenv.
- [#12](https://github.com/rbraunlee/ansible_macos/issues/12) There are ansible-lint and yamllint findings, and no CI.
- [#13](https://github.com/rbraunlee/ansible_macos/issues/13) Personal identity is hardcoded in tracked vars.

## TODO

- [#14](https://github.com/rbraunlee/ansible_macos/issues/14) Decide whether a Nerd Font patch step is needed. The current cask is already the patched build.
