# ansible_macos

Bootstrap a new macOS machine with Homebrew, Ansible, and a dotfiles repository.

A single script (`bootstrap.sh`) prepares the machine and runs an Ansible playbook (`main.yml`) that:

- installs Homebrew formulae and casks
- sets Dock and Finder preferences
- configures the global Git user name, email and GitHub username
- clones your dotfiles repository and symlinks it into `$HOME` with GNU Stow
- installs the Zap zsh plugin manager

## Requirements

- macOS on Apple Silicon or Intel. The Homebrew path is picked from the CPU architecture.
- An administrator account. `bootstrap.sh` asks for your sudo password once and passes it to the playbook for casks that need root.
- Internet access (Homebrew, Galaxy, GitHub)

`bootstrap.sh` installs everything else it needs: Xcode Command Line Tools, Homebrew, Ansible, and the collections in `requirements.yml`.

## Usage

On a fresh Mac, the first `git` command prompts you to install the Xcode Command Line Tools. Accept the prompt, then clone:

```bash
git clone <this-repo-url> ~/ansible_macos
cp ~/ansible_macos/vars/local.example.yml ~/ansible_macos/vars/local.yml
open -e ~/ansible_macos/vars/local.yml   # fill in your name, email, GitHub username, dotfiles repo
~/ansible_macos/bootstrap.sh
```

`bootstrap.sh` works from any directory. It will:

1. On a terminal, ask for your sudo password once and check it with `sudo -v`.
2. Install the Xcode Command Line Tools if they're missing. It asks you to press Enter when the Apple installer has finished, or times out after `XCODE_CLT_TIMEOUT` seconds (default 1800) when there is no terminal.
3. Install Homebrew if it's missing, and add `brew shellenv` to `~/.zprofile` (once).
4. Install Ansible via Homebrew, if missing.
5. Install the Galaxy collections from `requirements.yml`.
6. Run `ansible-playbook main.yml`, passing the sudo password without putting it on a command line or on disk.

Extra arguments are passed through to `ansible-playbook`, so a dry run of the playbook is (the prerequisites are still installed, and `~/.zprofile` is still updated):

```bash
./bootstrap.sh --check
```

Other examples: `./bootstrap.sh -v`, `./bootstrap.sh -e update_homebrew=true`. Don't pass `-K`: the script already supplies the password, and a `-K` answer is overridden.

To run only the playbook once the prerequisites exist:

```bash
ansible-playbook main.yml --ask-become-pass
```

Run this way, casks that need sudo don't get the password: Ansible keeps the `-K` value away from tasks. Use `bootstrap.sh` for those.

## Repository layout

| Path | Purpose |
| --- | --- |
| `bootstrap.sh` | Entry point. Installs prerequisites and runs the playbook. |
| `main.yml` | The playbook. All tasks run against the local machine. |
| `group_vars/all.yml` | Generic defaults: packages, macOS settings, dotfiles layout, feature flags. |
| `vars/local.example.yml` | Template for your personal settings. Copy it to `vars/local.yml`, which is git-ignored. |
| `inventory/host.ini` | Inventory: `localhost` over a local connection, using the Python that runs Ansible. |
| `ansible.cfg` | Points Ansible at the inventory. |
| `requirements.yml` | Galaxy collections (`community.general`). |
| `.yamllint`, `.ansible-lint`, `.github/workflows/lint.yml` | Lint configuration and the CI workflow that runs yamllint, ansible-lint, a syntax check and shellcheck on pushes to `main` and on every pull request. |

## Configuration

### Personal settings: `vars/local.yml`

Your identity and dotfiles repo live in the untracked `vars/local.yml`, so they never end up in this public repo. The playbook loads it at the start when it exists. Its values override `group_vars/all.yml`. Dicts are merged, so you only list the keys you change. Values must be written out literally: they can't reference other keys in the same file.

| Key | Description |
| --- | --- |
| `user.name`, `user.email` | Written to the global Git config. Skipped, with a warning, while either is empty. |
| `user.github_username` | Written as `git config --global github.user` when set. |
| `dotfiles.repo` | Git URL of your dotfiles repository. The dotfiles steps are skipped, with a warning, while it is empty. |

Any other key from `group_vars/all.yml` can be overridden here too.

### Defaults: `group_vars/all.yml`

| Key | Description |
| --- | --- |
| `brew_prefix`, `brew_bin` | Homebrew location: `/opt/homebrew` on Apple Silicon, `/usr/local` on Intel. The playbook stops early with a clear message if `brew_bin` is missing. |
| `update_homebrew` | Run `brew update` before installing formulae. Default `false`, so re-runs stay fast. |
| `setup_brew.formulae` | Command-line packages installed with `brew`. |
| `setup_brew.cask` | GUI applications and fonts installed with `brew install --cask`. |
| `macos_settings.dock` | Dock autohide, tile size, and show-recents. |
| `macos_settings.finder` | Show all file extensions, default view style (`icnv`, `Nlsv`, `clmv`, `glyv`), and the path bar. The view style only applies to folders without a saved view. |
| `dotfiles.dest` | Local clone location (default `~/.dotfiles`). |
| `dotfiles.version` | Branch, tag or commit for the first clone (default `main`). |
| `dotfiles.subdirs` | Directories in the dotfiles repo to scan for stow packages (`common`, `macos`). |
| `dotfiles.config_destination` | Directory created as `~/.config` before stowing. |
| `features.configure_git` | Configure Git identity (default `true`). |
| `features.install_zap` | Install the Zap zsh plugin manager (default `true`). |

### Dotfiles layout

The playbook expects the dotfiles repository to contain one directory per application under each of `common/` and `macos/`. Each application directory is treated as a stow package and linked into `$HOME`, so its contents should mirror the paths relative to home (for example `common/nvim/.config/nvim/…`).

## Re-running

The playbook is designed to be re-run, and a second run should report no changes:

- Homebrew formulae and casks are only installed when missing.
- `osx_defaults` and `git_config` only write values that differ. Dock and Finder restart only when a setting changed.
- The dotfiles repo is cloned only when it's missing and is never updated by the playbook, so your local edits and unpushed commits are safe. Run `git pull` in `~/.dotfiles` yourself.
- Stow runs with `-S`, so packages that are already linked are left alone. It doesn't remove links to files you deleted from a package; run `stow -R -d ~/.dotfiles/<subdir> -t ~ <package>` for that.
- Zap is downloaded and installed only when `~/.local/share/zap` is missing. The installer is pinned to a commit and checked against a SHA-256 checksum.

## Known limitations

- Not yet verified end to end on a real Mac. PRs #17, #20 and #23 list what to check there.
- If `XDG_DATA_HOME` is set, the Zap installer puts Zap under it, but the playbook checks `~/.local/share/zap`, so it would reinstall on every run.
- If Touch ID for sudo is enabled, `sudo -v` in `bootstrap.sh` may show a Touch ID prompt instead of reading the typed password.

## TODO

- [#14](https://github.com/rbraunlee/ansible_macos/issues/14) Decide whether a Nerd Font patch step is needed. The current cask is already the patched build.
