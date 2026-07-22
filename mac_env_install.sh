#!/bin/bash
# =============================================================================
# Mac Environment Installer v2 - zsh + iTerm2 + dev tools + eza (ls com ícones)
# Uso local:  bash mac_env_install.sh [--verbose]
# Uso remoto: curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- --verbose
# Requer: macOS (Apple Silicon ou Intel)
# Diferença da v1: instala eza e configura alias ls -> eza --icons no .zshrc
# =============================================================================
set -euo pipefail

# Cores e UI (estilo openclaw_install.sh)
BOLD='\033[1m'
ACCENT='\033[38;2;255;77;77m'
INFO='\033[38;2;136;146;176m'
SUCCESS='\033[38;2;0;229;204m'
WARN='\033[38;2;255;176;32m'
ERROR='\033[38;2;230;57;70m'
MUTED='\033[38;2;90;100;128m'
NC='\033[0m'

TMPFILES=()
cleanup_tmpfiles() {
    local f
    for f in "${TMPFILES[@]:-}"; do
        rm -rf "$f" 2>/dev/null || true
    done
}
trap cleanup_tmpfiles EXIT

mktempfile() {
    local f
    f="$(mktemp)"
    TMPFILES+=("$f")
    echo "$f"
}

# -----------------------------------------------------------------------------
# Download (para Homebrew e gum)
# -----------------------------------------------------------------------------
DOWNLOADER=""
detect_downloader() {
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
        return 0
    fi
    if command -v wget &>/dev/null; then
        DOWNLOADER="wget"
        return 0
    fi
    echo -e "${ERROR}Missing downloader (curl or wget required)${NC}" >&2
    exit 1
}

download_file() {
    local url="$1"
    local output="$2"
    if [[ -z "$DOWNLOADER" ]]; then
        detect_downloader
    fi
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 --retry-connrefused -o "$output" "$url"
        return
    fi
    wget -q --https-only --secure-protocol=TLSv1_2 --tries=3 --timeout=20 -O "$output" "$url"
}

run_remote_bash() {
    local url="$1"
    local tmp
    tmp="$(mktempfile)"
    download_file "$url" "$tmp"
    /bin/bash "$tmp"
}

# -----------------------------------------------------------------------------
# Gum (spinner + UI moderna)
# -----------------------------------------------------------------------------
GUM_VERSION="${MACENV_GUM_VERSION:-0.17.0}"
GUM=""
GUM_STATUS="skipped"
GUM_REASON=""

gum_is_tty() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        return 1
    fi
    if [[ "${TERM:-dumb}" == "dumb" ]]; then
        return 1
    fi
    if [[ -t 2 || -t 1 ]]; then
        return 0
    fi
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        return 0
    fi
    return 1
}

gum_detect_os() {
    case "$(uname -s 2>/dev/null || true)" in
        Darwin) echo "Darwin" ;;
        *) echo "unsupported" ;;
    esac
}

gum_detect_arch() {
    case "$(uname -m 2>/dev/null || true)" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) echo "unknown" ;;
    esac
}

verify_sha256sum_file() {
    local checksums="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum --ignore-missing -c "$checksums" &>/dev/null
        return $?
    fi
    if command -v shasum &>/dev/null; then
        shasum -a 256 --ignore-missing -c "$checksums" &>/dev/null
        return $?
    fi
    return 1
}

bootstrap_gum_temp() {
    GUM=""
    GUM_STATUS="skipped"
    GUM_REASON=""

    case "${MACENV_USE_GUM:-auto}" in
        0|false|False|FALSE|off|OFF|no|NO)
            GUM_REASON="disabled via MACENV_USE_GUM"
            return 1
            ;;
    esac

    if ! gum_is_tty; then
        GUM_REASON="not a TTY"
        return 1
    fi

    if command -v gum &>/dev/null; then
        GUM="gum"
        GUM_STATUS="found"
        GUM_REASON="already installed"
        return 0
    fi

    if [[ "${MACENV_USE_GUM:-auto}" != "1" && "${MACENV_USE_GUM:-auto}" != "true" && "${MACENV_USE_GUM:-auto}" != "TRUE" && "${MACENV_USE_GUM:-auto}" != "auto" ]]; then
        GUM_REASON="invalid MACENV_USE_GUM value: ${MACENV_USE_GUM:-auto}"
        return 1
    fi

    if ! command -v tar &>/dev/null; then
        GUM_REASON="tar not found"
        return 1
    fi

    local os arch asset base gum_tmpdir gum_path
    os="$(gum_detect_os)"
    arch="$(gum_detect_arch)"
    if [[ "$os" == "unsupported" || "$arch" == "unknown" ]]; then
        GUM_REASON="unsupported os/arch ($os/$arch)"
        return 1
    fi

    asset="gum_${GUM_VERSION}_${os}_${arch}.tar.gz"
    base="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}"

    gum_tmpdir="$(mktemp -d)"
    TMPFILES+=("$gum_tmpdir")

    if ! download_file "${base}/${asset}" "$gum_tmpdir/$asset"; then
        GUM_REASON="download failed"
        return 1
    fi

    if ! download_file "${base}/checksums.txt" "$gum_tmpdir/checksums.txt"; then
        GUM_REASON="checksum unavailable or failed"
        return 1
    fi

    if ! (cd "$gum_tmpdir" && verify_sha256sum_file "checksums.txt"); then
        GUM_REASON="checksum verification failed"
        return 1
    fi

    if ! tar -xzf "$gum_tmpdir/$asset" -C "$gum_tmpdir" &>/dev/null; then
        GUM_REASON="extract failed"
        return 1
    fi

    gum_path="$(find "$gum_tmpdir" -type f -name gum 2>/dev/null | head -n1 || true)"
    if [[ -z "$gum_path" ]]; then
        GUM_REASON="gum binary missing after extract"
        return 1
    fi

    chmod +x "$gum_path" &>/dev/null || true
    if [[ ! -x "$gum_path" ]]; then
        GUM_REASON="gum binary is not executable"
        return 1
    fi

    GUM="$gum_path"
    GUM_STATUS="installed"
    GUM_REASON="temp, verified"
    return 0
}

print_gum_status() {
    case "$GUM_STATUS" in
        found)
            ui_success "gum disponível (${GUM_REASON})"
            ;;
        installed)
            ui_success "gum carregado (${GUM_REASON}, v${GUM_VERSION})"
            ;;
        *)
            if [[ -n "$GUM_REASON" ]]; then
                ui_info "gum não usado (${GUM_REASON})"
            fi
            ;;
    esac
}

print_installer_banner() {
    if [[ -n "$GUM" ]]; then
        local title tagline hint card
        title="$("$GUM" style --foreground "#ff4d4d" --bold " Mac Environment Installer v2 ")"
        tagline="$("$GUM" style --foreground "#8892b0" "iTerm2 + Oh My Zsh + Powerlevel10k + pyenv + eza + MesloLGS Nerd Font + .zshrc")"
        hint="$("$GUM" style --foreground "#5a6480" "modo com spinner e etapas")"
        card="$(printf '%s\n%s\n%s' "$title" "$tagline" "$hint")"
        "$GUM" style --border rounded --border-foreground "#ff4d4d" --padding "1 2" "$card"
        echo ""
        return
    fi

    echo -e "${ACCENT}${BOLD}"
    echo "  Mac Environment Installer v2"
    echo -e "${NC}${INFO}  iTerm2 + Oh My Zsh + Powerlevel10k + pyenv + eza + MesloLGS Nerd Font + .zshrc${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# UI (com fallback quando gum não está disponível)
# -----------------------------------------------------------------------------
ui_info() {
    local msg="$*"
    if [[ -n "$GUM" ]]; then
        "$GUM" log --level info "$msg"
    else
        echo -e "${MUTED}·${NC} ${msg}"
    fi
}

ui_warn() {
    local msg="$*"
    if [[ -n "$GUM" ]]; then
        "$GUM" log --level warn "$msg"
    else
        echo -e "${WARN}!${NC} ${msg}"
    fi
}

ui_success() {
    local msg="$*"
    if [[ -n "$GUM" ]]; then
        local mark
        mark="$("$GUM" style --foreground "#00e5cc" --bold "✓")"
        echo "${mark} ${msg}"
    else
        echo -e "${SUCCESS}✓${NC} ${msg}"
    fi
}

ui_error() {
    local msg="$*"
    if [[ -n "$GUM" ]]; then
        "$GUM" log --level error "$msg"
    else
        echo -e "${ERROR}✗${NC} ${msg}"
    fi
}

INSTALL_STAGE_TOTAL=4
INSTALL_STAGE_CURRENT=0

ui_section() {
    local title="$1"
    if [[ -n "$GUM" ]]; then
        "$GUM" style --bold --foreground "#ff4d4d" --padding "1 0" "$title"
    else
        echo ""
        echo -e "${ACCENT}${BOLD}${title}${NC}"
    fi
}

ui_stage() {
    local title="$1"
    INSTALL_STAGE_CURRENT=$((INSTALL_STAGE_CURRENT + 1))
    ui_section "[${INSTALL_STAGE_CURRENT}/${INSTALL_STAGE_TOTAL}] ${title}"
}

is_shell_function() {
    local name="${1:-}"
    [[ -n "$name" ]] && declare -F "$name" &>/dev/null
}

run_with_spinner() {
    local title="$1"
    shift

    if [[ -n "$GUM" ]] && gum_is_tty && ! is_shell_function "${1:-}"; then
        "$GUM" spin --spinner dot --title "$title" -- "$@"
        return $?
    fi

    "$@"
}

run_quiet_step() {
    local title="$1"
    shift

    if [[ "${VERBOSE:-0}" == "1" ]]; then
        run_with_spinner "$title" "$@"
        return $?
    fi

    local log
    log="$(mktempfile)"

    if [[ -n "$GUM" ]] && gum_is_tty && ! is_shell_function "${1:-}"; then
        local cmd_quoted=""
        local log_quoted=""
        printf -v cmd_quoted '%q ' "$@"
        printf -v log_quoted '%q' "$log"
        if run_with_spinner "$title" bash -c "${cmd_quoted}>${log_quoted} 2>&1"; then
            return 0
        fi
    else
        if "$@" >"$log" 2>&1; then
            return 0
        fi
    fi

    ui_error "${title} falhou — execute com --verbose para detalhes"
    if [[ -s "$log" ]]; then
        tail -n 80 "$log" >&2 || true
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Detecção de ambiente
# -----------------------------------------------------------------------------
detect_macos_or_die() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        ui_error "Este script é apenas para macOS."
        exit 1
    fi
    if [[ "$(uname -m)" == "arm64" ]]; then
        BREW_PREFIX="/opt/homebrew"
    else
        BREW_PREFIX="/usr/local"
    fi
    ui_success "macOS detectado (Homebrew: $BREW_PREFIX)"
}

ensure_brew_in_path() {
    if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
        eval "$("$BREW_PREFIX/bin/brew" shellenv)"
    fi
    if ! command -v brew &>/dev/null; then
        ui_error "Homebrew não encontrado no PATH."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Xcode Command Line Tools
# -----------------------------------------------------------------------------
install_xcode_clt() {
    if xcode-select -p &>/dev/null; then
        ui_success "Xcode Command Line Tools já instalado"
        return 0
    fi
    ui_info "Abrindo instalador das Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    ui_warn "Conclua o instalador na janela que abriu e execute este script novamente."
    exit 0
}

# -----------------------------------------------------------------------------
# Homebrew
# -----------------------------------------------------------------------------
install_homebrew() {
    if command -v brew &>/dev/null; then
        ui_success "Homebrew já instalado"
        ensure_brew_in_path
        return 0
    fi
    ui_info "Instalando Homebrew..."
    run_quiet_step "Instalando Homebrew" env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ensure_brew_in_path
    ui_success "Homebrew instalado"
}

# -----------------------------------------------------------------------------
# iTerm2
# -----------------------------------------------------------------------------
install_iterm2() {
    if [[ -d "/Applications/iTerm.app" ]]; then
        ui_success "iTerm2 já instalado"
        return 0
    fi
    ensure_brew_in_path
    run_quiet_step "Instalando iTerm2" brew install --cask iterm2
    ui_success "iTerm2 instalado"
}

# -----------------------------------------------------------------------------
# Oh My Zsh
# -----------------------------------------------------------------------------
install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ui_success "Oh My Zsh já instalado"
        return 0
    fi
    ui_info "Instalando Oh My Zsh (CHSH=no, KEEP_ZSHRC=yes)"
    run_quiet_step "Instalando Oh My Zsh" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ui_success "Oh My Zsh instalado"
}

# -----------------------------------------------------------------------------
# Plugins ZSH (Powerlevel10k, autosuggestions, syntax-highlighting)
# -----------------------------------------------------------------------------
install_zsh_plugins() {
    ensure_brew_in_path
    local to_install=()
    brew list powerlevel10k &>/dev/null    || to_install+=(powerlevel10k)
    brew list zsh-autosuggestions &>/dev/null || to_install+=(zsh-autosuggestions)
    brew list zsh-syntax-highlighting &>/dev/null || to_install+=(zsh-syntax-highlighting)
    if [[ ${#to_install[@]} -eq 0 ]]; then
        ui_success "Plugins ZSH já instalados"
        return 0
    fi
    run_quiet_step "Instalando plugins ZSH" brew install "${to_install[@]}"
    ui_success "Plugins ZSH instalados"
}

# -----------------------------------------------------------------------------
# pyenv
# -----------------------------------------------------------------------------
install_pyenv() {
    ensure_brew_in_path
    if command -v pyenv &>/dev/null; then
        ui_success "pyenv já instalado"
        return 0
    fi
    run_quiet_step "Instalando pyenv" brew install pyenv
    ui_success "pyenv instalado"
}

# -----------------------------------------------------------------------------
# MesloLGS Nerd Font (v3+ — U+F8FF vazio; macOS exibe a maçã via fallback)
# Sempre reinstala via brew para garantir a versão mais recente (3.x).
# A versão antiga "MesloLGS NF" (2.3.3) tem pi-box em U+F8FF e não deve ser usada.
# -----------------------------------------------------------------------------
install_meslo_nerd_font() {
    ensure_brew_in_path

    # Remover cask antigo se presente (MesloLGS NF 2.3.3 que mostra π em U+F8FF)
    local old_ttf="$HOME/Library/Fonts/MesloLGS NF Regular.ttf"
    if [[ -f "$old_ttf" ]]; then
        ui_info "Removendo MesloLGS NF antiga (v2.3.3 — U+F8FF = pi-box)..."
        rm -f "$HOME/Library/Fonts/MesloLGS NF"*.ttf 2>/dev/null || true
        ui_success "Fonte antiga removida"
    fi

    # Instalar / atualizar cask oficial (Nerd Fonts 3.x)
    if brew list --cask font-meslo-lg-nerd-font &>/dev/null; then
        run_quiet_step "Atualizando MesloLGS Nerd Font" brew upgrade --cask font-meslo-lg-nerd-font || true
        ui_success "MesloLGS Nerd Font atualizada (Nerd Fonts 3.x)"
    else
        run_quiet_step "Instalando MesloLGS Nerd Font" brew install --cask font-meslo-lg-nerd-font
        ui_success "MesloLGS Nerd Font instalada (Nerd Fonts 3.x)"
    fi

    ui_info "Fonte a usar no iTerm2/Cursor: MesloLGSNerdFontMono-Regular (sem espaços)"
    ui_info "U+F8FF vazio na v3 → macOS exibe  via fallback de sistema"
}

# -----------------------------------------------------------------------------
# eza (ls moderno com ícones para pastas e arquivos)
# -----------------------------------------------------------------------------
install_eza() {
    ensure_brew_in_path
    if command -v eza &>/dev/null; then
        ui_success "eza já instalado"
        return 0
    fi
    run_quiet_step "Instalando eza" brew install eza
    ui_success "eza instalado (ls com ícones)"
}

# -----------------------------------------------------------------------------
# .zshrc (template: sem API keys reais; inclui alias ls -> eza --icons)
# -----------------------------------------------------------------------------
write_zshrc() {
    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]]; then
        local backup="${zshrc}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$zshrc" "$backup"
        ui_info "Backup do .zshrc em: $backup"
    fi

    cat > "$zshrc" << 'ZSHRC_HEAD'
# =============================================================================
# ZSH Configuration - Versão Limpa e Organizada (gerado por mac_env_install.sh)
# =============================================================================

# -----------------------------------------------------------------------------
# Powerlevel10k Instant Prompt
# -----------------------------------------------------------------------------
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# -----------------------------------------------------------------------------
# Oh My Zsh Configuration
# -----------------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# -----------------------------------------------------------------------------
# PATH Configuration
# -----------------------------------------------------------------------------
# Homebrew (Apple Silicon: /opt/homebrew | Intel: /usr/local)
export PATH="/opt/homebrew/bin:$PATH"
[[ -x /usr/local/bin/brew ]] && export PATH="/usr/local/bin:$PATH"

# Python Environment Manager (pyenv)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# Android Development (descomente e ajuste se usar Android Studio)
# export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
# export PATH="$JAVA_HOME/bin:$PATH"
# export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

# -----------------------------------------------------------------------------
# Language Runtime Initialization
# -----------------------------------------------------------------------------
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

# -----------------------------------------------------------------------------
# API Keys & Tokens (preencha com seus valores no novo Mac)
# -----------------------------------------------------------------------------
# export MAPBOX_DOWNLOADS_TOKEN="seu_token_aqui"
# export OPENAI_API_KEY="sua_chave_aqui"

# -----------------------------------------------------------------------------
# ZSH Plugins (instalados via Homebrew)
# zsh-syntax-highlighting deve ser o ÚLTIMO plugin carregado
# -----------------------------------------------------------------------------
if [[ -f "$(brew --prefix 2>/dev/null)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if [[ -f /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme
elif [[ -f /usr/local/share/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/local/share/powerlevel10k/powerlevel10k.zsh-theme
fi
if [[ -f "$(brew --prefix 2>/dev/null)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# -----------------------------------------------------------------------------
# Powerlevel10k - Execute 'p10k configure' para personalizar o prompt
# -----------------------------------------------------------------------------
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# -----------------------------------------------------------------------------
# eza (ls com ícones) - instalado pelo mac_env_install.sh
# Use 'ls' normalmente; será eza --icons. Para ls original: \ls ou command ls
# -----------------------------------------------------------------------------
if command -v eza &>/dev/null; then
  alias ls='eza --icons'
  alias ll='eza -l --icons'
  alias la='eza -la --icons'
  alias lt='eza --tree --icons'
fi

# =============================================================================
# Fim da Configuração
# =============================================================================
ZSHRC_HEAD

    ui_success ".zshrc escrito em $zshrc"
    ui_warn "API keys (MAPBOX, OPENAI) estão comentadas. Edite ~/.zshrc e preencha se precisar."
}

# -----------------------------------------------------------------------------
# Powerlevel10k: prompt de configuração
# -----------------------------------------------------------------------------
setup_p10k() {
    if [[ -f "$HOME/.p10k.zsh" ]]; then
        ui_success "~/.p10k.zsh já existe"
        return 0
    fi
    ui_info "Na primeira abertura do zsh, o p10k pode perguntar se deseja configurar."
    ui_info "Ou execute manualmente: zsh && p10k configure"
    ui_success "Nada a fazer agora para p10k"
}

# -----------------------------------------------------------------------------
# Resumo e instruções finais
# -----------------------------------------------------------------------------
print_summary() {
    ui_section "Concluído"
    if [[ -n "$GUM" ]]; then
        local content
        content="Próximos passos:
  1. No iTerm2: Settings → Profiles → Text → Font → MesloLGSNerdFontMono-Regular
  2. No Cursor: terminal.integrated.fontFamily → \"MesloLGSNerdFont\"
  3. Abra o iTerm2 (ou Terminal) e rode:  zsh
  4. Se aparecer o assistente do Powerlevel10k, configure ou pule.
  5. ls usa eza com ícones (pastas/arquivos). Árvore: lt ou eza --tree --icons
  6. Edite ~/.zshrc e descomente/preencha API keys se precisar.
  7. Para usar zsh como shell padrão:  chsh -s \$(which zsh)

Fonte: MesloLGSNerdFont (v3.x) — U+F8FF vazio → macOS exibe  via fallback.
Android Studio / JAVA_HOME: se for usar, descomente as linhas no .zshrc."
        "$GUM" style --border rounded --border-foreground "#5a6480" --padding "0 1" "$content"
    else
        echo -e "${INFO}"
        echo "Próximos passos:"
        echo "  1. No iTerm2: Settings → Profiles → Text → Font → MesloLGSNerdFontMono-Regular"
        echo "  2. No Cursor: terminal.integrated.fontFamily → \"MesloLGSNerdFont\""
        echo "  3. Abra o iTerm2 (ou Terminal) e rode:  zsh"
        echo "  4. Se aparecer o assistente do Powerlevel10k, configure ou pule."
        echo "  5. ls usa eza com ícones (pastas/arquivos). Árvore: lt ou eza --tree --icons"
        echo "  6. Edite ~/.zshrc e descomente/preencha API keys se precisar."
        echo "  7. Para usar zsh como shell padrão:  chsh -s \$(which zsh)"
        echo ""
        echo "Fonte: MesloLGSNerdFont (v3.x) — U+F8FF vazio → macOS exibe  via fallback."
        echo "Android Studio / JAVA_HOME: se for usar, descomente as linhas no .zshrc."
        echo -e "${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    bootstrap_gum_temp || true
    print_installer_banner
    print_gum_status
    detect_macos_or_die

    install_xcode_clt

    ui_stage "Preparando ambiente"
    install_homebrew

    ui_stage "Instalando iTerm2 e ferramentas"
    install_iterm2
    install_oh_my_zsh
    install_zsh_plugins
    install_pyenv
    install_eza

    ui_stage "Instalando fontes"
    install_meslo_nerd_font

    ui_stage "Configurando shell"
    write_zshrc
    setup_p10k

    print_summary
}

# Suporta --verbose
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
    esac
done

main
