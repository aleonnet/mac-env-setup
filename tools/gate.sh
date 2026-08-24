#!/usr/bin/env bash
# =============================================================================
# gate.sh — O portão de qualidade do mac-env-setup: local e CI rodam ISTO.
#
# Antes: as asserções moravam só no ci.yml e "passou local, quebrou no CI"
# era uma classe real de defeito (shellcheck flutuante do brew, extração por
# awk do TOML embutido). Agora o ci.yml chama este script; o que o CI vê é o
# que o desenvolvedor viu.
#
# As duas armadilhas históricas (documentadas no CLAUDE.md) moram aqui:
#   - `! grep -q` NÃO derruba passo sob set -e → ausência se testa com ausente()
#   - `starship print-config` sai 0 até com TOML inválido → toml_valido() greppa
#     "Unable to parse" no stderr
# Asserção nova merece teste de mutação: plante a regressão, veja o portão
# ficar vermelho, desplante.
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$RAIZ"
ALVO="mac_env_install.sh"
SHELLCHECK_VERSION="v0.10.0"

FALHAS=0
titulo() { printf '\n\033[1m── %s\033[0m\n' "$1"; }
ok()     { printf '  [OK]    %s\n' "$1"; }
falha()  { printf '  [ERRO]  %s\n' "$1" >&2; FALHAS=$((FALHAS+1)); }

ausente() {   # ausente <regex> <arquivo> <mensagem>
    if grep -q "$1" "$2"; then falha "$3"; return 1; fi
    return 0
}
toml_valido() {   # <arquivo> — print-config sai 0 mesmo com erro
    if STARSHIP_CONFIG="$1" starship print-config 2>&1 >/dev/null | grep -q 'Unable to parse'; then
        falha "TOML inválido em $1"; return 1
    fi
    return 0
}

# ── sintaxe com o bash 3.2 do sistema ────────────────────────────────────────
titulo "sintaxe (bash 3.2 do sistema)"
if /bin/bash -n "$ALVO"; then ok "bash -n limpo"; else falha "bash -n reprovou"; fi

# ── shellcheck FIXADO (a versão flutuante do brew foi a causa raiz da classe
#    local≠CI; binário oficial, em cache por versão) ─────────────────────────
titulo "shellcheck $SHELLCHECK_VERSION"
acha_shellcheck() {
    local cache="${TMPDIR:-/tmp}/shellcheck-$SHELLCHECK_VERSION"
    if [ -x "$cache/shellcheck" ]; then printf '%s' "$cache/shellcheck"; return 0; fi
    local os arch
    case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) return 1 ;; esac
    case "$(uname -m)" in arm64|aarch64) arch=aarch64 ;; *) arch=x86_64 ;; esac
    mkdir -p "$cache" || return 1
    curl -fsSL --proto '=https' --tlsv1.2 \
        "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.${os}.${arch}.tar.xz" \
        | tar -xJf - --strip-components=1 -C "$cache" "shellcheck-${SHELLCHECK_VERSION}/shellcheck" 2>/dev/null || return 1
    chmod +x "$cache/shellcheck" 2>/dev/null || return 1
    printf '%s' "$cache/shellcheck"
}
if SC="$(acha_shellcheck)"; then
    if "$SC" -S warning "$ALVO" tools/*.sh; then ok "sem achados (nível warning)"
    else falha "shellcheck reprovou"; fi
else
    falha "não consegui obter o shellcheck $SHELLCHECK_VERSION"
fi

# ── cópias embutidas idênticas às fontes ─────────────────────────────────────
titulo "templates embutidos"
if ./tools/embed.sh --check >/dev/null 2>&1; then ok "cópias idênticas às fontes"
else falha "template embutido diverge — rode ./tools/embed.sh"; fi

# ── python dos templates compila ─────────────────────────────────────────────
titulo "py_compile nos templates"
py_ok=1
for f in templates/*.py; do
    [ -f "$f" ] || continue
    python3 -m py_compile "$f" 2>/dev/null || { falha "py_compile: $f"; py_ok=0; }
done
[ "$py_ok" = "1" ] && ok "python dos templates compila"

# ── dry-runs headless (perfis, categorias, flags) ────────────────────────────
titulo "dry-runs headless"
dr_ok=1
for p in completo terminal dev mobile; do
    MACENV_USE_GUM=0 /bin/bash "$ALVO" --dry-run --profile "$p" > /dev/null || { falha "dry-run --profile $p"; dr_ok=0; }
done
MACENV_USE_GUM=0 NO_COLOR=1 /bin/bash "$ALVO" --dry-run --categories terminal,dev > /dev/null || { falha "dry-run --categories"; dr_ok=0; }
MACENV_USE_GUM=0 /bin/bash "$ALVO" --dry-run --yes > /dev/null || { falha "dry-run --yes"; dr_ok=0; }
MACENV_USE_GUM=0 /bin/bash "$ALVO" --list > /dev/null || { falha "--list"; dr_ok=0; }
MACENV_USE_GUM=0 /bin/bash "$ALVO" --help > /dev/null || { falha "--help"; dr_ok=0; }
[ "$dr_ok" = "1" ] && ok "perfis, categorias, --yes, --list, --help"

# ── pipe-safety (curl | bash simulado) ───────────────────────────────────────
titulo "pipe-safety"
if cat "$ALVO" | MACENV_USE_GUM=0 /bin/bash -s -- --dry-run --profile dev > /dev/null; then
    ok "cat | bash -s dry-run"
else
    falha "quebrou vindo do cano"
fi

# ── categoria inválida deve falhar ───────────────────────────────────────────
titulo "categoria inválida"
if MACENV_USE_GUM=0 /bin/bash "$ALVO" --dry-run --categories nao-existe > /dev/null 2>&1; then
    falha "categoria inexistente foi aceita"
else
    ok "recusada com exit != 0"
fi

# ── dry-run sob PTY (caminhos de animação/TTY) ───────────────────────────────
titulo "dry-run sob PTY"
if MACENV_USE_GUM=0 python3 - <<'PY' >/dev/null 2>&1
import os, pty, sys
os.environ.setdefault("TERM", "xterm-256color")
status = pty.spawn(["/bin/bash", "mac_env_install.sh", "--dry-run", "--profile", "terminal"])
sys.exit(1 if status and os.waitstatus_to_exitcode(status) else 0)
PY
then ok "animação/TTY sem quebrar"; else falha "dry-run sob PTY"; fi

# ── biblioteca: o script menos as 2 últimas linhas (parse_args + main) ───────
LIB="$(mktemp)"
sed '$d' "$ALVO" | sed '$d' > "$LIB"
trap 'rm -f "$LIB"' EXIT

# ── geração de configs em HOME falso ─────────────────────────────────────────
titulo "configs em HOME falso (.zshrc)"
FAKE="$(mktemp -d)"
zsh_ok=1
if HOME="$FAKE" MACENV_LIB="$LIB" /bin/bash -c '
    set -euo pipefail
    source "$MACENV_LIB"
    GUM=""
    apply_categories terminal dev android
    PROMPT_ACTIVE=p10k
    write_zshrc
    PROMPT_ACTIVE=starship
    write_zshrc
' >/dev/null 2>&1; then
    zsh -n "$FAKE/.zshrc" || { falha ".zshrc gerado não passa em zsh -n"; zsh_ok=0; }
    grep -q 'starship init zsh' "$FAKE/.zshrc" || { falha "sem starship init no .zshrc"; zsh_ok=0; }
    ausente 'Suas adições' "$FAKE/.zshrc" "sem tail anterior não deveria haver a seção" || zsh_ok=0
    grep -q '\[\[ -d "\$PYENV_ROOT/bin" \]\] && export PATH' "$FAKE/.zshrc" || { falha "guarda do pyenv no PATH sumiu"; zsh_ok=0; }
    ausente 'virtualenv-init'  "$FAKE/.zshrc" "pyenv-virtualenv voltou ao .zshrc gerado" || zsh_ok=0
    ausente 'PYENV_VIRTUALENV' "$FAKE/.zshrc" "variável do pyenv-virtualenv voltou" || zsh_ok=0
    [ "$zsh_ok" = "1" ] && ok ".zshrc: p10k e starship gerados, guardas presentes"
else
    falha "write_zshrc morreu no HOME falso"
fi

# ── starship: presets + patch de venv + fallback ─────────────────────────────
titulo "starship (presets, venv, fallback)"
if ! command -v starship >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then brew install starship >/dev/null 2>&1 || true; fi
fi
if command -v starship >/dev/null 2>&1; then
    st_ok=1
    for preset in tokyo-night catppuccin-powerline; do
        H="$FAKE/$preset"; mkdir -p "$H"
        if ! HOME="$H" MACENV_LIB="$LIB" MACENV_CI_PRESET="$preset" /bin/bash -c '
            set -euo pipefail
            source "$MACENV_LIB"
            GUM=""
            STARSHIP_PRESET="$MACENV_CI_PRESET"
            detect_macos_or_die >/dev/null
            write_starship_config >/dev/null
        ' >/dev/null 2>&1; then falha "write_starship_config ($preset)"; st_ok=0; continue; fi
        cfg="$H/.config/starship.toml"
        grep -qxF '$python\' "$cfg" || { falha "$preset: \$python fora do format"; st_ok=0; }
        [ "$(grep -c '^\[python\]$' "$cfg")" = "1" ] || { falha "$preset: tabela [python] duplicada/ausente"; st_ok=0; }
        grep -q 'detect_env_vars = \["VIRTUAL_ENV"\]' "$cfg" || { falha "$preset: detect_env_vars sumiu"; st_ok=0; }
        ausente '#\$virtualenv' "$cfg" "$preset: '#' do preset deveria ter saído" || st_ok=0
        if [ "$preset" = "tokyo-night" ]; then
            grep -q 'f5b000' "$cfg" || { falha "tokyo-night sem o âmbar no venv"; st_ok=0; }
            grep -A1 -xF '$nodejs\' "$cfg" | grep -qxF '$python\' || { falha "âncora \$nodejs quebrada"; st_ok=0; }
        else
            grep -q 'bg:green bold' "$cfg" || { falha "catppuccin sem o realce"; st_ok=0; }
        fi
        toml_valido "$cfg" || st_ok=0
        STARSHIP_CONFIG="$cfg" VIRTUAL_ENV=/tmp/proj/.venv starship prompt | grep -q '(\.venv)' \
            || { falha "$preset: venv ativo não aparece no prompt"; st_ok=0; }
        STARSHIP_CONFIG="$cfg" starship prompt > "$FAKE/render-sem-venv.txt"
        ausente '\.venv' "$FAKE/render-sem-venv.txt" "$preset: prompt sem venv citou .venv" || st_ok=0
        cp "$cfg" "$cfg.before"
        MACENV_LIB="$LIB" MACENV_CI_PRESET="$preset" /bin/bash -c '
            set -euo pipefail
            source "$MACENV_LIB"
            GUM=""
            starship_patch_venv "$1" "$MACENV_CI_PRESET" >/dev/null
        ' _ "$cfg" >/dev/null 2>&1 || { falha "$preset: 2a passada do patch morreu"; st_ok=0; }
        diff -q "$cfg.before" "$cfg" >/dev/null || { falha "$preset: patch não é idempotente"; st_ok=0; }
    done
    # Fallback: direto da FONTE (o embed --check garante a cópia idêntica) —
    # a extração por awk do CI antigo morreu com a segmentação.
    fb="templates/starship_fallback.toml"
    [ -s "$fb" ] || { falha "fallback vazio"; st_ok=0; }
    toml_valido "$fb" || st_ok=0
    grep -q 'fg:amber' "$fb" || { falha "fallback sem o âmbar"; st_ok=0; }
    ausente '^symbol = ""$' "$fb" "símbolo vazio: glifo Nerd Font perdido" || st_ok=0
    ausente '^\[\](' "$fb" "seta de powerline vazia no fallback" || st_ok=0
    STARSHIP_CONFIG="$fb" VIRTUAL_ENV=/tmp/proj/.venv starship prompt | grep -q '(\.venv)' \
        || { falha "fallback: venv não aparece"; st_ok=0; }
    [ "$st_ok" = "1" ] && ok "2 presets patchados e idempotentes + fallback válido, direto da fonte"
else
    falha "starship indisponível (e sem brew para instalar)"
fi

# ── fonte Nerd no iTerm2 (gate por presença + nomes PostScript) ──────────────
titulo "iTerm2 (perfil dinâmico)"
it_ok=1
grep -v '^[[:space:]]*#' "$ALVO" > "$FAKE/sem-comentarios.sh"
grep -q 'MesloLGSNFM-Regular' "$FAKE/sem-comentarios.sh" || { falha "nome PostScript Meslo sumiu"; it_ok=0; }
grep -q 'JetBrainsMonoNFM-Regular' "$FAKE/sem-comentarios.sh" || { falha "nome PostScript JetBrains sumiu"; it_ok=0; }
ausente 'NerdFontMono-Regular' "$FAKE/sem-comentarios.sh" "nome de arquivo onde vai nome PostScript" || it_ok=0
mkdir -p "$FAKE/stubbin"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/stubbin/defaults"
chmod +x "$FAKE/stubbin/defaults"
dyn() { echo "$1/Library/Application Support/iTerm2/DynamicProfiles/macenv.json"; }
run_it() {   # run_it <home> <iterm-app> <selected_items>
    HOME="$1" MACENV_LIB="$LIB" MACENV_CI_APP="$2" MACENV_CI_ITEMS="$3" PATH="$FAKE/stubbin:$PATH" \
    /bin/bash -c '
        set -euo pipefail
        source "$MACENV_LIB"
        GUM=""
        ITERM_APP="$MACENV_CI_APP"
        SELECTED_ITEMS="$MACENV_CI_ITEMS"
        configure_iterm2_font >/dev/null
    ' >/dev/null 2>&1
}
H="$FAKE/noapp"; mkdir -p "$H"
run_it "$H" "$H/NaoExiste.app" " font-jetbrains " || true
[ -f "$(dyn "$H")" ] && { falha "criou perfil sem iTerm2 presente"; it_ok=0; }
H="$FAKE/jb"; mkdir -p "$H/iTerm.app"
run_it "$H" "$H/iTerm.app" " font-jetbrains " || { falha "configure_iterm2_font morreu (jetbrains)"; it_ok=0; }
d="$(dyn "$H")"
if [ -f "$d" ]; then
    python3 -m json.tool "$d" > /dev/null || { falha "macenv.json inválido"; it_ok=0; }
    grep -q 'JetBrainsMonoNFM-Regular' "$d" || { falha "perfil sem a fonte JetBrains"; it_ok=0; }
    ausente 'NerdFontMono-Regular' "$d" "perfil dinâmico com nome de arquivo" || it_ok=0
    grep -q '"Dynamic Profile Parent Name": "Default"' "$d" || { falha "sem herança do perfil Default"; it_ok=0; }
    grep -q '"Name": "MacEnv"' "$d" || { falha "perfil sem o nome MacEnv"; it_ok=0; }
else
    falha "perfil dinâmico não foi criado"; it_ok=0
fi
H="$FAKE/meslo"; mkdir -p "$H/iTerm.app"
run_it "$H" "$H/iTerm.app" " font-meslo " || { falha "configure_iterm2_font morreu (meslo)"; it_ok=0; }
d="$(dyn "$H")"
grep -q 'MesloLGSNFM-Regular' "$d" 2>/dev/null || { falha "perfil sem a fonte Meslo"; it_ok=0; }
ausente 'MesloLGSNerdFontMono-Regular' "$d" "perfil com o nome de arquivo antigo" || it_ok=0
printf '{ "Profiles": [ { "Name": "MacEnv", "Normal Font": "MARCADOR-CI" } ] }\n' > "$d"
run_it "$H" "$H/iTerm.app" " font-meslo " || true
grep -q 'MARCADOR-CI' "$d" || { falha "perfil dinâmico existente foi sobrescrito"; it_ok=0; }
[ "$it_ok" = "1" ] && ok "gate por presença, nomes PostScript, herança do Default, preservação"

rm -rf "$FAKE"

printf '\n'
if [ "$FALHAS" = "0" ]; then
    printf 'RESULTADO: portão limpo\n'
else
    printf 'RESULTADO: %s checagem(ns) falharam\n' "$FALHAS"
    exit 1
fi
