# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file project: `mac_env_install.sh` — a self-contained Bash bootstrap installer for a macOS dev environment (Xcode CLT, Homebrew, iTerm2, Oh My Zsh, Powerlevel10k, zsh plugins, pyenv, eza, MesloLGS Nerd Font v3, generated `~/.zshrc`). All comments and console output are Brazilian Portuguese — keep new comments and UI strings in Portuguese.

The script is distributed for remote execution from the `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- --verbose
```

It must therefore stay **pipe-safe**: no `read`, no interactive prompts, no `sudo`. TTY-dependent behavior (gum UI) must keep its non-TTY fallback.

## Running

```bash
bash mac_env_install.sh [--verbose|-v]   # --verbose streams output instead of temp logs
```

Environment toggles: `MACENV_USE_GUM` (auto/1/0), `MACENV_GUM_VERSION` (default 0.17.0), `NO_COLOR`.

No build/test/lint tooling exists. Validate edits with `bash -n mac_env_install.sh` (and `shellcheck` if available).

## Architecture

Entry point is `main()` at the bottom of the file; execution order: detect macOS/arch (sets `BREW_PREFIX`: `/opt/homebrew` on arm64, `/usr/local` on Intel) → Xcode CLT gate → 4 UI stages: [1] Homebrew → [2] iTerm2, Oh My Zsh, zsh plugins, pyenv, eza → [3] Nerd Font → [4] write `.zshrc` + p10k.

Conventions every change must respect:

- **Idempotency**: each `install_*` function checks presence first and early-returns ("já instalado"). The script must remain safe to re-run. Deliberate exception: `install_meslo_nerd_font` always upgrades and removes legacy v2.3.3 font files (incompatible glyphs).
- **CLT gate**: if Xcode CLT is missing, the script launches the GUI installer and exits 0 — the user re-runs afterward. Everything downstream assumes CLT and brew exist.
- **`ensure_brew_in_path()`** is called at the start of every brew-dependent function (shell state can't be assumed).
- **UI layer**: user-facing output goes through `ui_info`/`ui_warn`/`ui_success`/`ui_error`/`ui_section` — gum when available (fetched to a temp dir with SHA256 verification, never installed permanently), ANSI echo fallback otherwise. Don't call `echo` directly for user-facing messages.
- **Quiet steps**: wrap installation work in `run_quiet_step` (logs to a temp file, dumps the last 80 lines on failure; bypassed by `--verbose`).
- **Temp files**: create via `mktempfile()` so the EXIT trap cleans them up.
- **Downloads**: use `download_file()` (HTTPS-pinned curl/wget with retries).
- **`.zshrc` generation**: `write_zshrc` backs up the existing file to `~/.zshrc.backup.<timestamp>` then **overwrites** (not appends) from a heredoc template; zsh-syntax-highlighting must stay sourced last.

When behavior changes, update `README.md` and add a `CHANGELOG.md` entry.
