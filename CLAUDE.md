# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file project: `mac_env_install.sh` — a category-based macOS dev-environment installer in Bash with an interactive selector (gum) and the "Event Horizon" amber art direction. All comments and console output are Brazilian Portuguese — keep new comments and UI strings in Portuguese.

Distributed for remote execution from the `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- [--profile dev|--dry-run|...]
```

**Bash 3.2 constraint**: the script runs under macOS system `/bin/bash` — no `declare -A`, no `readarray`, no `${var,,}`. Test with `/bin/bash`, never only Homebrew bash.

## Running / testing

```bash
bash mac_env_install.sh --list                      # catalog
bash mac_env_install.sh --dry-run --profile dev     # plan without installing
cat mac_env_install.sh | /bin/bash -s -- --dry-run --profile completo   # pipe-safety check
bash -n mac_env_install.sh                          # syntax (also run shellcheck if available)
```

Flags: `--profile completo|terminal|dev|mobile`, `--categories a,b,c`, `--all`, `--yes`, `--dry-run`, `--list`, `--verbose`. Env: `MACENV_USE_GUM`, `MACENV_GUM_VERSION`, `NO_COLOR`. Never run a real install during development — `--dry-run` only; config generation can be tested against a fake `$HOME` (source the script minus the final `parse_args`/`main` lines).

## Architecture

Flow in `main()`: gum bootstrap → banner → `resolve_selection` (flags headless, else gum selector via `/dev/tty`) → `compute_stages` → manifest + confirm → CLT gate (exits 0 asking re-run) → stage Base (Homebrew) → one stage per selected category (`run_category` → `run_item`) → stage Configurações (`.zshrc` + starship/p10k + ghostty config, only when the `terminal` category is selected) → `print_final_report`.

**Data model** (Bash 3.2): `CATEGORY_DB` and `ITEM_DB` are indexed arrays of `|`-delimited records (`id|categoria|rótulo|padrão`). Item id maps to its function by convention: `install_${id//-/_}`. `ITEM_DB` record order = execution order within a category. Selection state lives in space-separated strings (`SELECTED_ITEMS`, `SELECTED_CATEGORIES`) with `item_selected`/`select_item` helpers; mutually exclusive choices in scalars `PROMPT_ACTIVE` (starship|p10k) and `TERMINAL_CHOICE`.

## Conventions every change must respect

- **Install function contract**: return `0` = installed now, `100` = already present (skip), `1` = failed. Presence check first. Every critical command ends with `|| return 1` — errexit is OFF inside `"$fn" || rc=$?` in `run_item`, so unguarded failures are silently swallowed. Item failure must not abort the run.
- **Pipe-safety**: interactivity ONLY through gum reading `< /dev/tty` (`gum_choose_tty`/`gum_confirm_tty`); never raw `read`, never global `exec </dev/tty`, no `sudo`. Every interactive path needs a headless fallback (default profile + warning). Esc/Ctrl-C → exit 130.
- **Casks with manually installed apps**: double check `[[ -d /Applications/X.app ]] || brew list --cask x` (Docker also checks legacy cask `docker` besides `docker-desktop`).
- **UI layer**: user-facing output via `ui_info/ui_warn/ui_success/ui_error/ui_done/ui_skip/ui_stage` — gum messages need `--` before the text (messages starting with `-` break gum's flag parsing). Installation work wrapped in `run_quiet_step` (temp-file logs, last 80 lines on failure). Temp files via `mktempfile()`; downloads via `download_file()`.
- **Art direction (Event Horizon)**: amber `#f5b000` signature; blackbody ramp in `BLACKBODY_STOPS` drives `gradient_text`/`rule_gradient`/`progress_orbit_line`/banner. Installer UI must use only universal Unicode (`╭─◆◇▰▱█▓░❯✓`) — Nerd Fonts aren't installed yet when it runs. Everything degrades: gum → plain ANSI → `NO_COLOR`/non-TTY plain text. gum theme is centralized in `apply_gum_theme` (env vars).
- **Generated configs**: `backup_and_install_file` (timestamped backup + overwrite) for `.zshrc` (composed from `zshrc_block_*` conditionals; zsh-syntax-highlighting stays last plugin, prompt init last line) and `starship.toml`. Ghostty config is never overwritten if it exists. `~/.p10k.zsh` is never touched.
- **`ensure_brew_in_path()`** at the start of every brew-dependent function.

When behavior changes, update `README.md` and add a `CHANGELOG.md` entry.
