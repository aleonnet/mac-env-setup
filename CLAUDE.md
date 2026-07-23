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

**Data model** (Bash 3.2): `CATEGORY_DB` and `ITEM_DB` are indexed arrays of `|`-delimited records — `ITEM_DB` has 6 fields: `id|categoria|rótulo|padrão|pacotes|descrição`, where `pacotes` is space-separated `f:formula`/`c:cask`/`c!:cask` entries (used by the upgrade engine; `c!:` marks self-updating casks — Docker, VS Code, Cursor, Android Studio — excluded from upgrade offers because the brew receipt goes stale while the app updates itself) and every reader must `IFS='|' read -r id cat label def pkgs desc`. Item id maps to its function by convention: `install_${id//-/_}`. `ITEM_DB` record order = execution order within a category. Selection state lives in space-separated strings (`SELECTED_ITEMS`, `SELECTED_CATEGORIES`) with `item_selected`/`select_item` helpers; mutually exclusive choices in scalars `PROMPT_ACTIVE` (starship|p10k) and `TERMINAL_CHOICE`.

**Upgrade engine**: `scan_outdated` runs `brew outdated --verbose` (formulae + casks, never `--greedy`) once after the Base stage; `offer_upgrades` shows the card and asks (interactive) or requires `--upgrade` (headless). `run_item`'s skip path (rc 100) checks `item_outdated_summary` and either upgrades (`RESULT_UP`, `ui_up`) or annotates "atualização disponível".

## Conventions every change must respect

- **Install function contract**: return `0` = installed now, `100` = already present (skip), `1` = failed. Presence check first. Every critical command ends with `|| return 1` — errexit is OFF inside `"$fn" || rc=$?` in `run_item`, so unguarded failures are silently swallowed. Item failure must not abort the run.
- **Pipe-safety**: interactivity ONLY through gum reading `< /dev/tty` (`gum_choose_tty`/`gum_confirm_tty`); never raw `read`, never global `exec </dev/tty`, no `sudo`. Every interactive path needs a headless fallback (default profile + warning). Esc/Ctrl-C → exit 130.
- **Casks with manually installed apps**: double check `[[ -d /Applications/X.app ]] || brew list --cask x` (Docker also checks legacy cask `docker` besides `docker-desktop`).
- **UI layer**: user-facing output via `ui_info/ui_warn/ui_success/ui_error/ui_done/ui_skip/ui_up/ui_stage` — all plain ANSI with the connected gutter (`GUT`), each calling `bar_clear` first (a live progress bar may be pinned as the last line; printing without clearing garbles it). gum is ONLY for choose/confirm/style cards (pass `--` before user text there). `run_item` runs each install fn in a `( set +e; MACENV_INNER=1; fn )` subshell under a braille spinner that transforms into the result line — so install fns must not mutate globals the parent needs, and `run_with_spinner` skips gum spin when `MACENV_INNER` is set. Installation work wrapped in `run_quiet_step` (temp-file logs, last 80 lines on failure). Temp files via `mktempfile()`; downloads via `download_file()`.
- **Art direction (Event Horizon)**: amber `#f5b000` signature; blackbody ramp in `BLACKBODY_STOPS` drives `gradient_text`/`rule_gradient`/`progress_orbit_line`/banner. Installer UI must use only universal Unicode (`╭─◆◇▰▱█▓░❯✓`) — Nerd Fonts aren't installed yet when it runs. Everything degrades: gum → plain ANSI → `NO_COLOR`/non-TTY plain text. gum theme is centralized in `apply_gum_theme` (env vars).
- **Generated configs**: `backup_and_install_file` (timestamped backup + overwrite) for `.zshrc` (composed from `zshrc_block_*` conditionals; zsh-syntax-highlighting stays last plugin, prompt init last line) and `starship.toml`. Ghostty config is never overwritten if it exists. `~/.p10k.zsh` is never touched.
- **`ensure_brew_in_path()`** at the start of every brew-dependent function.

When behavior changes, update `README.md` and add a `CHANGELOG.md` entry.
