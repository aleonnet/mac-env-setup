#!/bin/bash
# =============================================================================
# Mac Environment Installer v3 — instalador por categorias com seletor
# Uso local:  bash mac_env_install.sh [opções]
# Uso remoto: curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- [opções]
# Opções:     --profile completo|terminal|dev|mobile · --categories a,b,c
#             --all · --yes · --dry-run · --list · --verbose · --help
# Requer:     macOS (Apple Silicon ou Intel)
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Cores — paleta "Event Horizon" (âmbar #f5b000, assinatura do ghostty-blackhole)
# Rampa blackbody: brasa -> âmbar -> branco-quente
# -----------------------------------------------------------------------------
BLACKBODY_STOPS="7a3b00 c47800 f5b000 ffd75e fff3c4"

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    COLOR_OK=1
    BOLD='\033[1m'
    ACCENT='\033[38;2;245;176;0m'       # âmbar assinatura #f5b000
    INFO='\033[38;2;136;146;176m'       # text-secondary #8892b0
    SUCCESS='\033[38;2;0;229;204m'      # cyan-bright   #00e5cc
    WARN='\033[38;2;255;176;32m'        # âmbar-quente
    ERROR='\033[38;2;230;57;70m'        # coral-mid     #e63946
    MUTED='\033[38;2;90;100;128m'       # text-muted    #5a6480
    NC='\033[0m'
else
    COLOR_OK=0
    BOLD='' ACCENT='' INFO='' SUCCESS='' WARN='' ERROR='' MUTED='' NC=''
fi
ANIM_OK="$COLOR_OK"

TMPFILES=()
cleanup_tmpfiles() {
    local f
    for f in "${TMPFILES[@]:-}"; do
        rm -rf "$f" 2>/dev/null || true
    done
    if [[ -t 1 ]]; then
        tput cnorm 2>/dev/null || true
    fi
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

apply_gum_theme() {
    [[ -n "$GUM" ]] || return 0
    export GUM_CHOOSE_CURSOR="❯ "
    export GUM_CHOOSE_CURSOR_FOREGROUND="#f5b000"
    export GUM_CHOOSE_HEADER_FOREGROUND="#8892b0"
    export GUM_CHOOSE_SELECTED_FOREGROUND="#f5b000"
    export GUM_CHOOSE_SELECTED_PREFIX="◆ "
    export GUM_CHOOSE_UNSELECTED_PREFIX="◇ "
    export GUM_CHOOSE_CURSOR_PREFIX="◇ "
    export GUM_CONFIRM_PROMPT_FOREGROUND="#f5b000"
    export GUM_CONFIRM_SELECTED_BACKGROUND="#f5b000"
    export GUM_CONFIRM_SELECTED_FOREGROUND="#000000"
    export GUM_SPIN_SPINNER_FOREGROUND="#f5b000"
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

# -----------------------------------------------------------------------------
# Primitivas de arte — gradiente truecolor sobre a rampa blackbody
# -----------------------------------------------------------------------------
R=0 G=0 B=0
hex_to_rgb() {
    local h="${1#\#}"
    R=$((16#${h:0:2}))
    G=$((16#${h:2:2}))
    B=$((16#${h:4:2}))
}

# ramp_rgb_at <pos 0..1000> — interpola a rampa e define R,G,B
ramp_rgb_at() {
    local pos="$1"
    local stops=($BLACKBODY_STOPS)
    local n=${#stops[@]}
    local span=$((n - 1))
    local scaled=$((pos * span))
    local seg=$((scaled / 1000))
    local frac=$((scaled % 1000))
    if [[ $seg -ge $span ]]; then
        seg=$((span - 1))
        frac=1000
    fi
    local r1 g1 b1
    hex_to_rgb "${stops[$seg]}"
    r1=$R; g1=$G; b1=$B
    hex_to_rgb "${stops[$((seg + 1))]}"
    R=$((r1 + (R - r1) * frac / 1000))
    G=$((g1 + (G - g1) * frac / 1000))
    B=$((b1 + (B - b1) * frac / 1000))
}

# gradient_render <texto> [fase 0..1999] — gradiente horizontal, sem newline.
# A fase desloca a rampa (espelhada em 1000) para o efeito shimmer.
gradient_render() {
    local text="$1"
    local phase="${2:-0}"
    local len=${#text}
    if [[ "$COLOR_OK" != "1" || $len -le 1 ]]; then
        printf '%s' "$text"
        return 0
    fi
    local i ch esc out="" p
    for ((i = 0; i < len; i++)); do
        ch="${text:$i:1}"
        if [[ "$ch" == " " ]]; then
            out+=" "
            continue
        fi
        p=$(((i * 1000 / (len - 1) + phase) % 2000))
        if [[ $p -gt 1000 ]]; then
            p=$((2000 - p))
        fi
        ramp_rgb_at "$p"
        printf -v esc '\033[38;2;%d;%d;%dm' "$R" "$G" "$B"
        out+="${esc}${ch}"
    done
    printf '%s\033[0m' "$out"
}

gradient_text() {
    gradient_render "$1" "${2:-0}"
    printf '\n'
}

# shimmer_line <texto> — a luz da rampa percorre o texto (âmbar -> branco-quente)
shimmer_line() {
    local text="$1"
    if [[ "$ANIM_OK" != "1" ]]; then
        gradient_text "$text"
        return 0
    fi
    local phase
    for phase in 0 180 360 540 720 900 1080 1260 1440; do
        printf '\r'
        gradient_render "$text" "$phase"
        sleep 0.045
    done
    printf '\r'
    gradient_render "$text"
    printf '\n'
}

# reveal_sweep <texto> — revelação esquerda->direita (ignição)
reveal_sweep() {
    local text="$1"
    if [[ "$ANIM_OK" != "1" ]]; then
        gradient_text "$text"
        return 0
    fi
    local len=${#text} k
    for k in 1 2 3 4; do
        printf '\r'
        gradient_render "${text:0:$((len * k / 5))}"
        sleep 0.03
    done
    printf '\r'
    gradient_render "$text"
    printf '\n'
}

term_cols() {
    local c
    c="$(tput cols 2>/dev/null || echo 72)"
    if ! [[ "$c" =~ ^[0-9]+$ ]]; then
        c=72
    fi
    if [[ $c -gt 92 ]]; then c=92; fi
    if [[ $c -lt 60 ]]; then c=60; fi
    echo "$c"
}

rule_gradient() {
    local char="${1:-─}"
    local w line
    w="$(term_cols)"
    printf -v line '%*s' "$w" ''
    line=${line// /$char}
    gradient_text "$line"
}

rule_sweep() {
    local char="${1:-━}"
    local w line
    w="$(term_cols)"
    printf -v line '%*s' "$w" ''
    line=${line// /$char}
    reveal_sweep "$line"
}

reveal_lines() {
    local line
    for line in "$@"; do
        gradient_text "$line"
        if [[ "$ANIM_OK" == "1" ]]; then
            sleep 0.04
        fi
    done
}

print_installer_banner() {
    echo ""
    if [[ "$COLOR_OK" != "1" ]]; then
        echo "Mac Environment Installer v3"
        echo "ambiente de desenvolvimento macOS — instalação por categorias"
        echo ""
        return 0
    fi
    if [[ -t 1 ]]; then
        tput civis 2>/dev/null || true
    fi
    reveal_lines \
        "               ░░▒▒▓▓██████████▓▓▒▒░░" \
        "           ░▒▓████████████████████████▓▒░" \
        "         ▒████▓▒░░                ░░▒▓████▒" \
        "        ▓███▒                          ▒███▓" \
        "         ▒████▓▒░░                ░░▒▓████▒" \
        "           ░▒▓████████████████████████▓▒░" \
        "               ░░▒▒▓▓██████████▓▓▒▒░░"
    echo ""
    shimmer_line "               ◆  M A C · E N V  ◆"
    echo -e "${INFO}        ambiente de desenvolvimento macOS ${MUTED}· v3.6.1${NC}"
    echo ""
    if [[ -t 1 ]]; then
        tput cnorm 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# UI (com fallback quando gum não está disponível)
# -----------------------------------------------------------------------------
ui_info() {
    local msg="$*"
    if [[ -n "$GUM" ]]; then
        "$GUM" log --level info -- "$msg"
    else
        echo -e "${MUTED}·${NC} ${msg}"
    fi
}

ui_warn() {
    local msg="$*"
    if [[ -n "$GUM" ]]; then
        "$GUM" log --level warn -- "$msg"
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
        "$GUM" log --level error -- "$msg"
    else
        echo -e "${ERROR}✗${NC} ${msg}"
    fi
}

# item concluído com cronômetro / item pulado
ui_done() {
    local label="$1"
    local secs="${2:-0}"
    local suffix=""
    if [[ "$secs" -gt 1 ]]; then
        suffix=" · ${secs}s"
    fi
    echo -e "${SUCCESS}✓${NC} ${label}${MUTED}${suffix}${NC}"
}

ui_skip() {
    echo -e "${MUTED}◇ ${1} — já instalado${NC}"
}

INSTALL_STAGE_TOTAL=0
INSTALL_STAGE_CURRENT=0
ITEMS_TOTAL=0
ITEMS_DONE=0

ui_section() {
    local title="$1"
    if [[ -n "$GUM" ]]; then
        "$GUM" style --bold --foreground "#f5b000" --padding "1 0" "$title"
    else
        echo ""
        echo -e "${ACCENT}${BOLD}${title}${NC}"
    fi
}

progress_orbit_line() {
    if [[ "$ITEMS_TOTAL" -le 0 || "$COLOR_OK" != "1" ]]; then
        return 0
    fi
    local width=24
    local filled=$((ITEMS_DONE * width / ITEMS_TOTAL))
    local i esc out=""
    for ((i = 0; i < width; i++)); do
        if [[ $i -lt $filled ]]; then
            ramp_rgb_at $((i * 1000 / (width - 1)))
            printf -v esc '\033[38;2;%d;%d;%dm' "$R" "$G" "$B"
            out+="${esc}▰"
        else
            out+=$'\033[38;2;90;100;128m▱'
        fi
    done
    printf '%s\033[0m %s\n' "$out" "${ITEMS_DONE}/${ITEMS_TOTAL} itens"
}

ui_stage() {
    local title="$1"
    INSTALL_STAGE_CURRENT=$((INSTALL_STAGE_CURRENT + 1))
    echo ""
    if [[ "$COLOR_OK" == "1" ]]; then
        local head="━━ [${INSTALL_STAGE_CURRENT}/${INSTALL_STAGE_TOTAL}] ${title} "
        local w fill pad
        w="$(term_cols)"
        fill=$((w - ${#head}))
        if [[ $fill -lt 4 ]]; then
            fill=4
        fi
        printf -v pad '%*s' "$fill" ''
        pad=${pad// /━}
        reveal_sweep "${head}${pad}"
        progress_orbit_line
    else
        echo "== [${INSTALL_STAGE_CURRENT}/${INSTALL_STAGE_TOTAL}] ${title} =="
    fi
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
# Catálogo — categorias, itens e perfis
# Convenção: item "id" -> função install_<id com hífen vira _>
# A ordem dos registros em ITEM_DB é a ordem de execução dentro da categoria.
# -----------------------------------------------------------------------------
CATEGORY_DB=(
    "terminal|Terminal & Shell|Ghostty + shader blackhole, zsh essentials, prompt, fontes, eza/fzf/zoxide/bat"
    "dev|Dev Essentials|git, gh, jq, wget, Docker, Node/pnpm/bun, pyenv, Claude Code"
    "cloud|Cloud & Infra|awscli, supabase"
    "android|Mobile Android|OpenJDK 21, platform-tools, Android Studio"
    "ios|Mobile iOS|CocoaPods (builds Flutter/iOS)"
    "apps|Apps|VS Code, Cursor"
)

# id|categoria|rótulo|padrão(1/0)|pacotes(f:formula c:cask)|descrição
# Itens com padrão 0 só entram por escolha explícita.
ITEM_DB=(
    "ghostty|terminal|Ghostty|1|c:ghostty|terminal moderno acelerado por GPU (Metal)"
    "iterm2|terminal|iTerm2|0|c:iterm2|terminal clássico do macOS"
    "font-jetbrains|terminal|JetBrainsMono Nerd Font|1|c:font-jetbrains-mono-nerd-font|fonte mono com ícones para prompt e eza"
    "font-meslo|terminal|MesloLGS Nerd Font|0|c:font-meslo-lg-nerd-font|fonte recomendada do Powerlevel10k"
    "blackhole|terminal|Ghostty Blackhole (shader)|1||buraco negro GLSL no fundo do Ghostty (s0xDk/ghostty-blackhole)"
    "zsh-essentials|terminal|Essenciais do zsh|1|f:zsh-autosuggestions f:zsh-syntax-highlighting|completions, histórico e plugins (sugestões + highlight)"
    "starship|terminal|Prompt Starship|1|f:starship|prompt rápido com config declarativa (TOML)"
    "p10k|terminal|Prompt Powerlevel10k|0|f:powerlevel10k|prompt zsh clássico (em modo manutenção)"
    "eza|terminal|eza (ls com ícones)|1|f:eza|ls moderno: ícones, árvore, git status"
    "fzf|terminal|fzf (busca fuzzy)|1|f:fzf|Ctrl-R no histórico e Ctrl-T em arquivos"
    "zoxide|terminal|zoxide (cd inteligente)|1|f:zoxide|cd que aprende: 'z projeto' pula direto"
    "bat|terminal|bat (cat com highlight)|1|f:bat|cat com syntax highlight e numeração"
    "git|dev|git (Homebrew)|1|f:git|git atualizado (o da Apple fica para trás)"
    "gh|dev|GitHub CLI|1|f:gh|PRs, issues e auth do GitHub no terminal"
    "jq|dev|jq|1|f:jq|filtra e transforma JSON no shell"
    "wget|dev|wget|1|f:wget|downloads recursivos e em lote"
    "docker|dev|Docker Desktop|1|c!:docker-desktop|containers + Docker Compose"
    "node|dev|Node.js + pnpm + bun|1|f:node f:pnpm f:bun|runtime JS + gerenciadores de pacote rápidos"
    "pyenv|dev|pyenv + pyenv-virtualenv|1|f:pyenv f:pyenv-virtualenv|múltiplas versões de Python + virtualenvs"
    "claude-code|dev|Claude Code|1||CLI de IA da Anthropic (instalador nativo em ~/.local/bin)"
    "awscli|cloud|AWS CLI|1|f:awscli|gerencia serviços AWS pelo terminal"
    "supabase|cloud|Supabase CLI|1|f:supabase|Supabase local + migrations + deploy"
    "openjdk21|android|OpenJDK 21 (LTS)|1|f:openjdk@21|JDK que o tooling Android/Gradle suporta (25/26 quebram builds)"
    "platform-tools|android|Android platform-tools (adb)|1|c:android-platform-tools|adb/fastboot para devices Android"
    "android-studio|android|Android Studio|0|c!:android-studio|IDE Android completa (pesada)"
    "cocoapods|ios|CocoaPods|1|f:cocoapods|dependências iOS — necessário para Flutter iOS"
    "vscode|apps|Visual Studio Code|1|c!:visual-studio-code|editor da Microsoft"
    "cursor|apps|Cursor|1|c!:cursor|editor com IA integrada"
)

SELECTED_CATEGORIES=""
SELECTED_ITEMS=""
PROMPT_ACTIVE=""        # starship | p10k | vazio
STARSHIP_PRESET="tokyo-night"   # tokyo-night | catppuccin-powerline
TERMINAL_CHOICE=""      # ghostty | iterm2 | ambos | vazio
PROFILE_LABEL=""

category_selected() {
    case " $SELECTED_CATEGORIES " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

item_selected() {
    case " $SELECTED_ITEMS " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

select_item() {
    if ! item_selected "$1"; then
        SELECTED_ITEMS="$SELECTED_ITEMS $1"
    fi
    return 0
}

deselect_item() {
    local out="" it
    for it in $SELECTED_ITEMS; do
        if [[ "$it" != "$1" ]]; then
            out="$out $it"
        fi
    done
    SELECTED_ITEMS="$out"
    return 0
}

category_label() {
    local rec id label desc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        if [[ "$id" == "$1" ]]; then
            echo "$label"
            return 0
        fi
    done
    echo "$1"
}

category_id_by_label() {
    local rec id label desc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        if [[ "$label" == "$1" ]]; then
            echo "$id"
            return 0
        fi
    done
    return 1
}

item_label() {
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        if [[ "$id" == "$1" ]]; then
            echo "$label"
            return 0
        fi
    done
    echo "$1"
}

item_pkgs() {
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        if [[ "$id" == "$1" ]]; then
            echo "$pkgs"
            return 0
        fi
    done
    return 1
}

item_desc() {
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        if [[ "$id" == "$1" ]]; then
            echo "$desc"
            return 0
        fi
    done
    return 1
}

preset_categories() {
    case "$1" in
        completo) echo "terminal dev cloud android ios apps" ;;
        terminal) echo "terminal" ;;
        dev)      echo "terminal dev apps" ;;
        mobile)   echo "terminal dev android ios" ;;
        *)        return 1 ;;
    esac
}

apply_categories() {
    SELECTED_CATEGORIES="$*"
    SELECTED_ITEMS=""
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        category_selected "$cat" || continue
        if [[ "$def" == "1" ]]; then
            select_item "$id"
        fi
    done
    if category_selected terminal; then
        PROMPT_ACTIVE="starship"
        TERMINAL_CHOICE="ghostty"
    else
        PROMPT_ACTIVE=""
        TERMINAL_CHOICE=""
    fi
    return 0
}

count_words() {
    # shellcheck disable=SC2086
    set -- $1
    echo $#
}

# -----------------------------------------------------------------------------
# Argumentos
# -----------------------------------------------------------------------------
VERBOSE=0
ASSUME_YES=0
ALL=0
DRY_RUN=0
PROFILE=""
CATEGORIES_ARG=""
UPGRADE_FLAG=0

print_usage() {
    cat <<'USAGE'
Mac Environment Installer v3

Uso:
  bash mac_env_install.sh [opções]
  curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- [opções]

Sem opções (em terminal interativo): abre o seletor de perfis e categorias.

Opções:
  --profile <p>       Perfil sem interação: completo | terminal | dev | mobile
  --categories a,b,c  Categorias sem interação: terminal,dev,cloud,android,ios,apps
  --all               Tudo (equivale a --profile completo)
  --upgrade           Atualiza itens já instalados que tenham versão nova no brew
  --yes, -y           Não perguntar nada; usa o perfil padrão (terminal)
  --dry-run           Mostra o que seria instalado e sai, sem tocar no sistema
  --list              Lista categorias e itens disponíveis e sai
  --verbose, -v       Mostra a saída completa de cada passo
  --help, -h          Esta ajuda

Variáveis de ambiente: MACENV_USE_GUM (auto|1|0), MACENV_GUM_VERSION, NO_COLOR
USAGE
}

print_catalog() {
    local rec id cat label def clabel cdesc
    echo "Categorias e itens (◆ = padrão do perfil, ◇ = opcional):"
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id clabel cdesc <<< "$rec"
        echo ""
        echo "  ${id} — ${clabel}"
        local irec ipkgs idesc
        for irec in "${ITEM_DB[@]}"; do
            IFS='|' read -r iid cat label def ipkgs idesc <<< "$irec"
            if [[ "$cat" == "$id" ]]; then
                if [[ "$def" == "1" ]]; then
                    echo "     ◆ ${label} — ${idesc}"
                else
                    echo "     ◇ ${label} — ${idesc}"
                fi
            fi
        done
    done
    echo ""
    echo "Perfis: completo · terminal · dev (terminal+dev+apps) · mobile (terminal+dev+android+ios)"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)   VERBOSE=1 ;;
            --yes|-y)       ASSUME_YES=1 ;;
            --all)          ALL=1 ;;
            --upgrade)      UPGRADE_FLAG=1 ;;
            --dry-run)      DRY_RUN=1 ;;
            --profile)      PROFILE="${2:-}"; shift ;;
            --profile=*)    PROFILE="${1#*=}" ;;
            --categories)   CATEGORIES_ARG="${2:-}"; shift ;;
            --categories=*) CATEGORIES_ARG="${1#*=}" ;;
            --list)         print_catalog; exit 0 ;;
            --help|-h)      print_usage; exit 0 ;;
            *)              echo "argumento desconhecido: $1 (use --help)" >&2 ;;
        esac
        shift
    done
    return 0
}

# -----------------------------------------------------------------------------
# Seleção — headless (flags) ou interativa (gum + /dev/tty)
# -----------------------------------------------------------------------------
can_prompt() {
    [[ -n "$GUM" ]] || return 1
    if [[ "$ASSUME_YES" == "1" || "$ALL" == "1" ]]; then
        return 1
    fi
    if [[ -n "$PROFILE" || -n "$CATEGORIES_ARG" ]]; then
        return 1
    fi
    [[ -r /dev/tty && -w /dev/tty ]] || return 1
    return 0
}

gum_choose_tty() {
    "$GUM" choose "$@" </dev/tty
}

gum_confirm_tty() {
    "$GUM" confirm "$@" </dev/tty
}

selection_cancelled() {
    ui_warn "Seleção cancelada."
    exit 130
}

select_profile() {
    local sel
    sel="$(gum_choose_tty --header "Escolha um perfil de instalação" \
        "Completo — tudo: terminal, dev, cloud, android, ios, apps" \
        "Terminal bonito — Ghostty, Starship, fontes, eza/fzf/zoxide/bat" \
        "Dev — Terminal bonito + git, Docker, Node, pyenv + apps" \
        "Mobile — Dev básico + Android + iOS (Flutter)" \
        "Personalizado — escolher categorias")" || selection_cancelled
    case "$sel" in
        Completo*)  PROFILE_LABEL="Completo";  apply_categories terminal dev cloud android ios apps ;;
        Terminal*)  PROFILE_LABEL="Terminal bonito"; apply_categories terminal ;;
        Dev*)       PROFILE_LABEL="Dev";       apply_categories terminal dev apps ;;
        Mobile*)    PROFILE_LABEL="Mobile";    apply_categories terminal dev android ios ;;
        Personalizado*)
            PROFILE_LABEL="Personalizado"
            refine_categories
            ;;
        *) selection_cancelled ;;
    esac
    return 0
}

refine_categories() {
    local rec id label desc opts=()
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        opts+=("$label")
    done
    local sel
    sel="$(gum_choose_tty --no-limit --header "Selecione as categorias (espaço marca, enter confirma)" \
        --selected "Terminal & Shell,Dev Essentials" "${opts[@]}")" || selection_cancelled
    if [[ -z "$sel" ]]; then
        selection_cancelled
    fi
    local cats="" line cid
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if cid="$(category_id_by_label "$line")"; then
            cats="$cats $cid"
        fi
    done <<< "$sel"
    # shellcheck disable=SC2086
    apply_categories $cats
    return 0
}

select_terminal_choice() {
    category_selected terminal || return 0
    local sel
    sel="$(gum_choose_tty --header "Qual terminal instalar?" \
        "Ghostty — GPU/Metal, recomendado" \
        "iTerm2 — clássico" \
        "Ambos")" || selection_cancelled
    case "$sel" in
        Ghostty*) TERMINAL_CHOICE="ghostty"; select_item ghostty; deselect_item iterm2 ;;
        iTerm2*)  TERMINAL_CHOICE="iterm2";  select_item iterm2;  deselect_item ghostty ;;
        Ambos*)   TERMINAL_CHOICE="ambos";   select_item ghostty; select_item iterm2 ;;
    esac
    return 0
}

select_prompt_choice() {
    category_selected terminal || return 0
    local header="Qual prompt ativar no zsh?"
    if [[ -f "$HOME/.p10k.zsh" ]]; then
        header="Qual prompt ativar? (~/.p10k.zsh detectado — sua config será mantida)"
    fi
    local sel
    sel="$(gum_choose_tty --header "$header" \
        "Starship — moderno, config declarativa (recomendado)" \
        "Powerlevel10k — mantém seu setup atual")" || selection_cancelled
    case "$sel" in
        Starship*)
            PROMPT_ACTIVE="starship"
            select_item starship
            deselect_item p10k
            local preset
            preset="$(gum_choose_tty --header "Estilo do prompt Starship" \
                "Tokyo Night — cápsulas arredondadas, azul/cinza (recomendado)" \
                "Catppuccin Powerline — segmentos pastel")" || selection_cancelled
            case "$preset" in
                Tokyo*)      STARSHIP_PRESET="tokyo-night" ;;
                Catppuccin*) STARSHIP_PRESET="catppuccin-powerline" ;;
            esac
            ;;
        Powerlevel10k*)
            PROMPT_ACTIVE="p10k"
            select_item p10k
            deselect_item starship
            select_item font-meslo   # fonte recomendada oficialmente pelo p10k
            ;;
    esac
    return 0
}

interactive_selection() {
    select_profile
    select_terminal_choice
    select_prompt_choice
    return 0
}

resolve_selection() {
    if [[ "$ALL" == "1" ]]; then
        PROFILE_LABEL="Completo"
        apply_categories terminal dev cloud android ios apps
        return 0
    fi
    if [[ -n "$PROFILE" ]]; then
        local cats
        if ! cats="$(preset_categories "$PROFILE")"; then
            ui_error "Perfil desconhecido: ${PROFILE} (use completo|terminal|dev|mobile)"
            exit 1
        fi
        PROFILE_LABEL="$PROFILE"
        # shellcheck disable=SC2086
        apply_categories $cats
        return 0
    fi
    if [[ -n "$CATEGORIES_ARG" ]]; then
        local cats c
        cats="$(echo "$CATEGORIES_ARG" | tr ',' ' ')"
        for c in $cats; do
            if [[ -z "$(category_label "$c")" ]] || ! preset_valid_category "$c"; then
                ui_error "Categoria desconhecida: ${c} (use --list para ver as válidas)"
                exit 1
            fi
        done
        PROFILE_LABEL="Personalizado (flags)"
        # shellcheck disable=SC2086
        apply_categories $cats
        return 0
    fi
    if can_prompt; then
        interactive_selection
        return 0
    fi
    PROFILE_LABEL="Terminal bonito (padrão)"
    ui_warn "Sem seletor interativo (gum/TTY indisponível ou --yes): usando perfil 'terminal'."
    ui_warn "Para outros perfis: --profile completo|dev|mobile ou --categories terminal,dev,..."
    apply_categories terminal
    return 0
}

preset_valid_category() {
    local rec id label desc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        if [[ "$id" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

compute_stages() {
    INSTALL_STAGE_TOTAL=1   # Base
    ITEMS_TOTAL=0
    local rec id label desc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        if category_selected "$id"; then
            INSTALL_STAGE_TOTAL=$((INSTALL_STAGE_TOTAL + 1))
        fi
    done
    if category_selected terminal; then
        INSTALL_STAGE_TOTAL=$((INSTALL_STAGE_TOTAL + 1))   # Configurações
    fi
    ITEMS_TOTAL="$(count_words "$SELECTED_ITEMS")"
    return 0
}

# -----------------------------------------------------------------------------
# Manifesto — resumo pré-instalação em árvore
# -----------------------------------------------------------------------------
print_plan_summary() {
    local body="" rec id clabel cdesc
    body="Perfil: ${PROFILE_LABEL} · ${INSTALL_STAGE_TOTAL} estágios · ${ITEMS_TOTAL} itens"$'\n'
    local cats=() c
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id clabel cdesc <<< "$rec"
        if category_selected "$id"; then
            cats+=("$id")
        fi
    done
    local n=${#cats[@]} i=0 branch items irec iid icat ilabel idef ipkgs idesc
    for c in "${cats[@]}"; do
        i=$((i + 1))
        if [[ $i -eq $n ]]; then
            branch="╰─"
        else
            branch="├─"
        fi
        items=""
        for irec in "${ITEM_DB[@]}"; do
            IFS='|' read -r iid icat ilabel idef ipkgs idesc <<< "$irec"
            if [[ "$icat" == "$c" ]] && item_selected "$iid"; then
                if [[ -n "$items" ]]; then
                    items="${items} · ${ilabel}"
                else
                    items="$ilabel"
                fi
            fi
        done
        body="${body}${branch} $(category_label "$c")"$'\n'
        if [[ $i -eq $n ]]; then
            body="${body}   ${items}"$'\n'
        else
            body="${body}│  ${items}"$'\n'
        fi
    done
    if [[ "$PROMPT_ACTIVE" == "starship" ]]; then
        body="${body}"$'\n'"Prompt ativo: Starship (~/.config/starship.toml)"
    elif [[ "$PROMPT_ACTIVE" == "p10k" ]]; then
        body="${body}"$'\n'"Prompt ativo: Powerlevel10k (~/.p10k.zsh preservado)"
    fi
    echo ""
    if [[ -n "$GUM" ]]; then
        "$GUM" style --border rounded --border-foreground "#f5b000" --padding "0 2" --width "$(($(term_cols) - 4))" "$body"
    else
        echo -e "${ACCENT}${BOLD}Plano de instalação${NC}"
        echo "$body"
    fi
    return 0
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
    run_quiet_step "Instalando Homebrew" env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    ensure_brew_in_path
    ui_success "Homebrew instalado"
}

# -----------------------------------------------------------------------------
# Funções de instalação por item
# Convenção de retorno: 0 = instalado agora · 100 = já instalado · 1 = falhou
# Comandos críticos SEMPRE com "|| return 1" (errexit desliga dentro de "fn || rc").
# -----------------------------------------------------------------------------
install_ghostty() {
    ensure_brew_in_path
    if [[ -d "/Applications/Ghostty.app" ]] || brew list --cask ghostty &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Ghostty" brew install --cask ghostty || return 1
    return 0
}

install_iterm2() {
    ensure_brew_in_path
    if [[ -d "/Applications/iTerm.app" ]] || brew list --cask iterm2 &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando iTerm2" brew install --cask iterm2 || return 1
    return 0
}

# Shader blackhole para o fundo do Ghostty (upstream: s0xDk/ghostty-blackhole)
BLACKHOLE_DIR="$HOME/Development/ghostty-blackhole"
BLACKHOLE_REPO="https://github.com/s0xDk/ghostty-blackhole.git"

install_blackhole() {
    if ! item_selected ghostty && [[ ! -d "/Applications/Ghostty.app" ]]; then
        ui_warn "Blackhole requer Ghostty — shader pulado."
        return 100
    fi
    if ! command -v git &>/dev/null; then
        return 1
    fi
    if [[ -d "$BLACKHOLE_DIR/.git" ]]; then
        run_quiet_step "Atualizando ghostty-blackhole" git -C "$BLACKHOLE_DIR" pull --ff-only || true
        return 100
    fi
    mkdir -p "$(dirname "$BLACKHOLE_DIR")"
    run_quiet_step "Clonando ghostty-blackhole" git clone --depth 1 "$BLACKHOLE_REPO" "$BLACKHOLE_DIR" || return 1
    return 0
}

install_claude_code() {
    if command -v claude &>/dev/null || [[ -x "$HOME/.local/bin/claude" ]]; then
        return 100
    fi
    run_quiet_step "Instalando Claude Code" bash -c "curl -fsSL https://claude.ai/install.sh | bash" || return 1
    return 0
}

install_font_jetbrains() {
    ensure_brew_in_path
    if brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando JetBrainsMono Nerd Font" brew install --cask font-jetbrains-mono-nerd-font || return 1
    return 0
}

# MesloLGS: sempre garante a v3.x e remove a v2.3.3 legada (U+F8FF incompatível)
install_font_meslo() {
    ensure_brew_in_path
    local old_ttf="$HOME/Library/Fonts/MesloLGS NF Regular.ttf"
    if [[ -f "$old_ttf" ]]; then
        ui_info "Removendo MesloLGS NF antiga (v2.3.3 — U+F8FF = pi-box)..."
        rm -f "$HOME/Library/Fonts/MesloLGS NF"*.ttf 2>/dev/null || true
    fi
    if brew list --cask font-meslo-lg-nerd-font &>/dev/null; then
        run_quiet_step "Atualizando MesloLGS Nerd Font" brew upgrade --cask font-meslo-lg-nerd-font || true
        return 100
    fi
    run_quiet_step "Instalando MesloLGS Nerd Font" brew install --cask font-meslo-lg-nerd-font || return 1
    return 0
}

# zsh essentials: completions/histórico são nativos do zsh (só config no .zshrc);
# aqui instalamos apenas os dois plugins via brew.
install_zsh_essentials() {
    ensure_brew_in_path
    local to_install=()
    brew list zsh-autosuggestions &>/dev/null || to_install+=(zsh-autosuggestions)
    brew list zsh-syntax-highlighting &>/dev/null || to_install+=(zsh-syntax-highlighting)
    if [[ ${#to_install[@]} -eq 0 ]]; then
        return 100
    fi
    run_quiet_step "Instalando plugins zsh" brew install "${to_install[@]}" || return 1
    return 0
}

install_starship() {
    ensure_brew_in_path
    if command -v starship &>/dev/null || brew list starship &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Starship" brew install starship || return 1
    return 0
}

install_p10k() {
    ensure_brew_in_path
    if brew list powerlevel10k &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Powerlevel10k" brew install powerlevel10k || return 1
    return 0
}

install_eza() {
    ensure_brew_in_path
    if command -v eza &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando eza" brew install eza || return 1
    return 0
}

install_fzf() {
    ensure_brew_in_path
    if command -v fzf &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando fzf" brew install fzf || return 1
    return 0
}

install_zoxide() {
    ensure_brew_in_path
    if command -v zoxide &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando zoxide" brew install zoxide || return 1
    return 0
}

install_bat() {
    ensure_brew_in_path
    if command -v bat &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando bat" brew install bat || return 1
    return 0
}

install_git() {
    ensure_brew_in_path
    if brew list git &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando git (Homebrew)" brew install git || return 1
    return 0
}

install_gh() {
    ensure_brew_in_path
    if command -v gh &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando GitHub CLI" brew install gh || return 1
    return 0
}

install_jq() {
    ensure_brew_in_path
    if command -v jq &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando jq" brew install jq || return 1
    return 0
}

install_wget() {
    ensure_brew_in_path
    if command -v wget &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando wget" brew install wget || return 1
    return 0
}

install_docker() {
    ensure_brew_in_path
    if [[ -d "/Applications/Docker.app" ]] || brew list --cask docker-desktop &>/dev/null || brew list --cask docker &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Docker Desktop" brew install --cask docker-desktop || return 1
    return 0
}

install_node() {
    ensure_brew_in_path
    local did=0
    if ! command -v node &>/dev/null; then
        run_quiet_step "Instalando Node.js" brew install node || return 1
        did=1
    fi
    if ! command -v pnpm &>/dev/null; then
        run_quiet_step "Instalando pnpm" brew install pnpm || return 1
        did=1
    fi
    if ! command -v bun &>/dev/null; then
        run_quiet_step "Instalando bun" brew install oven-sh/bun/bun || return 1
        did=1
    fi
    if [[ $did -eq 0 ]]; then
        return 100
    fi
    return 0
}

install_pyenv() {
    ensure_brew_in_path
    local did=0
    if ! command -v pyenv &>/dev/null; then
        run_quiet_step "Instalando pyenv" brew install pyenv || return 1
        did=1
    fi
    if ! brew list pyenv-virtualenv &>/dev/null; then
        run_quiet_step "Instalando pyenv-virtualenv" brew install pyenv-virtualenv || return 1
        did=1
    fi
    if [[ $did -eq 0 ]]; then
        return 100
    fi
    return 0
}

install_awscli() {
    ensure_brew_in_path
    if command -v aws &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando AWS CLI" brew install awscli || return 1
    return 0
}

install_supabase() {
    ensure_brew_in_path
    if command -v supabase &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Supabase CLI" brew install supabase/tap/supabase || return 1
    return 0
}

install_openjdk21() {
    ensure_brew_in_path
    if brew list openjdk@21 &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando OpenJDK 21" brew install openjdk@21 || return 1
    return 0
}

install_platform_tools() {
    ensure_brew_in_path
    if command -v adb &>/dev/null || brew list --cask android-platform-tools &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Android platform-tools" brew install --cask android-platform-tools || return 1
    return 0
}

install_android_studio() {
    ensure_brew_in_path
    if [[ -d "/Applications/Android Studio.app" ]] || brew list --cask android-studio &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Android Studio" brew install --cask android-studio || return 1
    return 0
}

install_cocoapods() {
    ensure_brew_in_path
    if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
        ui_warn "Xcode completo não detectado — builds Flutter iOS exigem o Xcode da App Store."
    fi
    if command -v pod &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando CocoaPods" brew install cocoapods || return 1
    return 0
}

install_vscode() {
    ensure_brew_in_path
    if [[ -d "/Applications/Visual Studio Code.app" ]] || brew list --cask visual-studio-code &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Visual Studio Code" brew install --cask visual-studio-code || return 1
    return 0
}

install_cursor() {
    ensure_brew_in_path
    if [[ -d "/Applications/Cursor.app" ]] || brew list --cask cursor &>/dev/null; then
        return 100
    fi
    run_quiet_step "Instalando Cursor" brew install --cask cursor || return 1
    return 0
}

# -----------------------------------------------------------------------------
# Atualizações — um scan do brew outdated; oferta antes de instalar
# (sem --greedy: casks que se auto-atualizam, como Docker/VS Code, ficam de fora)
# -----------------------------------------------------------------------------
OUTDATED_RAW=""
DO_UPGRADE=0
PENDING_UPDATES=""

scan_outdated() {
    OUTDATED_RAW=""
    [[ "$ITEMS_TOTAL" -gt 0 ]] || return 0
    ensure_brew_in_path
    local tmpf
    tmpf="$(mktempfile)"
    run_with_spinner "Verificando atualizações disponíveis" bash -c \
        "brew outdated --verbose >$(printf '%q' "$tmpf") 2>/dev/null; brew outdated --cask --verbose >>$(printf '%q' "$tmpf") 2>/dev/null; true" || true
    OUTDATED_RAW="$(cat "$tmpf" 2>/dev/null || true)"
    return 0
}

# pkg_outdated_line <nome> — ecoa a linha "nome (atual) < nova" se desatualizado
pkg_outdated_line() {
    local name="$1" line first
    [[ -n "$OUTDATED_RAW" ]] || return 1
    while IFS= read -r line; do
        first="${line%% *}"
        if [[ "$first" == "$name" || "${first##*/}" == "$name" ]]; then
            echo "$line"
            return 0
        fi
    done <<< "$OUTDATED_RAW"
    return 1
}

# item_outdated_summary <id> — linhas outdated dos pacotes do item (falha se nenhum)
# Entradas "c!:" (casks que se auto-atualizam: Docker, VS Code, Cursor...) são
# ignoradas: o receipt do brew fica defasado do app real e geraria falso positivo.
item_outdated_summary() {
    local id="$1" pkgs entry name out=""
    pkgs="$(item_pkgs "$id")" || return 1
    for entry in $pkgs; do
        [[ "${entry%%:*}" == "c!" ]] && continue
        name="${entry#*:}"
        name="${name##*/}"
        local line
        if line="$(pkg_outdated_line "$name")"; then
            if [[ -n "$out" ]]; then
                out="${out} · ${line}"
            else
                out="$line"
            fi
        fi
    done
    [[ -n "$out" ]] || return 1
    echo "$out"
    return 0
}

# upgrade_item_pkgs <id> — brew upgrade nos pacotes desatualizados do item
upgrade_item_pkgs() {
    local id="$1" pkgs entry kind name
    pkgs="$(item_pkgs "$id")" || return 1
    for entry in $pkgs; do
        kind="${entry%%:*}"
        [[ "$kind" == "c!" ]] && continue
        name="${entry#*:}"
        pkg_outdated_line "${name##*/}" >/dev/null || continue
        if [[ "$kind" == "c" ]]; then
            run_quiet_step "Atualizando ${name}" brew upgrade --cask "$name" || return 1
        else
            run_quiet_step "Atualizando ${name}" brew upgrade "$name" || return 1
        fi
    done
    return 0
}

offer_upgrades() {
    DO_UPGRADE=0
    PENDING_UPDATES=""
    [[ -n "$OUTDATED_RAW" ]] || return 0
    local id summary body=""
    for id in $SELECTED_ITEMS; do
        if summary="$(item_outdated_summary "$id")"; then
            body="${body}↑ $(item_label "$id") — ${summary}"$'\n'
            PENDING_UPDATES="$PENDING_UPDATES $id"
        fi
    done
    [[ -n "$body" ]] || return 0
    echo ""
    if [[ -n "$GUM" ]]; then
        "$GUM" style --border rounded --border-foreground "#f5b000" --padding "0 2" --width "$(($(term_cols) - 4))" \
            "Atualizações disponíveis:"$'\n'"$body"
    else
        echo -e "${ACCENT}Atualizações disponíveis:${NC}"
        echo "$body"
    fi
    if [[ "$UPGRADE_FLAG" == "1" ]]; then
        DO_UPGRADE=1
        ui_info "Itens acima serão atualizados (--upgrade)."
        return 0
    fi
    if can_prompt; then
        if gum_confirm_tty "Atualizar os itens acima durante a instalação?" --affirmative "Atualizar" --negative "Manter versões"; then
            DO_UPGRADE=1
        fi
        return 0
    fi
    ui_warn "Rodando sem interação: versões mantidas. Use --upgrade para atualizar."
    return 0
}

ui_up() {
    local label="$1"
    local secs="${2:-0}"
    local suffix=" · atualizado"
    if [[ "$secs" -gt 1 ]]; then
        suffix="${suffix} em ${secs}s"
    fi
    echo -e "${ACCENT}↑${NC} ${label}${MUTED}${suffix}${NC}"
}

# -----------------------------------------------------------------------------
# Execução por categoria com placar
# -----------------------------------------------------------------------------
RESULT_OK=""
RESULT_SKIP=""
RESULT_FAIL=""
RESULT_UP=""

run_item() {
    local id="$1"
    local label="$2"
    local fn="install_${id//-/_}"
    local start=$SECONDS
    local rc=0
    "$fn" || rc=$?
    local elapsed=$((SECONDS - start))
    ITEMS_DONE=$((ITEMS_DONE + 1))
    case "$rc" in
        0)
            RESULT_OK="$RESULT_OK $id"
            ui_done "$label" "$elapsed"
            ;;
        100)
            local summary=""
            if summary="$(item_outdated_summary "$id" 2>/dev/null)"; then
                if [[ "$DO_UPGRADE" == "1" ]]; then
                    local up_start=$SECONDS
                    if upgrade_item_pkgs "$id"; then
                        RESULT_UP="$RESULT_UP $id"
                        ui_up "$label" $((SECONDS - up_start))
                    else
                        RESULT_FAIL="$RESULT_FAIL $id"
                        ui_error "Falhou ao atualizar: ${label} (continuando)"
                    fi
                else
                    RESULT_SKIP="$RESULT_SKIP $id"
                    echo -e "${MUTED}◇ ${label} — instalado ${NC}${ACCENT}(atualização disponível)${NC}"
                fi
            else
                RESULT_SKIP="$RESULT_SKIP $id"
                ui_skip "$label"
            fi
            ;;
        *)
            RESULT_FAIL="$RESULT_FAIL $id"
            ui_error "Falhou: ${label} (continuando)"
            ;;
    esac
    return 0
}

run_category() {
    local cat="$1" rec id c label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id c label def pkgs desc <<< "$rec"
        [[ "$c" == "$cat" ]] || continue
        item_selected "$id" || continue
        run_item "$id" "$label"
    done
    return 0
}

result_ok() {
    case " $RESULT_OK " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# -----------------------------------------------------------------------------
# Configurações geradas (.zshrc, starship.toml, ghostty config)
# -----------------------------------------------------------------------------
backup_and_install_file() {
    local src="$1"
    local dest="$2"
    if [[ -f "$dest" ]]; then
        local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$dest" "$backup"
        ui_info "Backup: $backup"
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    return 0
}

zshrc_block_header() {
    cat <<'EOF'
# =============================================================================
# ZSH Configuration — gerado por mac_env_install.sh (v3)
# =============================================================================
EOF
}

zshrc_block_p10k_instant() {
    cat <<'EOF'

# Powerlevel10k Instant Prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
EOF
}

zshrc_block_zsh_core() {
    cat <<'EOF'

# Completions + histórico (nativos do zsh — sem frameworks)
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
bindkey -e
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY INC_APPEND_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt AUTO_CD INTERACTIVE_COMMENTS
EOF
}

zshrc_block_path() {
    cat <<'EOF'

# Homebrew (Apple Silicon: /opt/homebrew | Intel: /usr/local)
export PATH="/opt/homebrew/bin:$PATH"
[[ -x /usr/local/bin/brew ]] && export PATH="/usr/local/bin:$PATH"
EOF
}

zshrc_block_pyenv() {
    cat <<'EOF'

# pyenv + pyenv-virtualenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
  if command -v pyenv-virtualenv-init 1>/dev/null 2>&1; then
    eval "$(pyenv virtualenv-init -)"
  fi
fi
EOF
}

zshrc_block_java() {
    cat <<'EOF'

# OpenJDK 21 (keg-only no Homebrew)
if [[ -d /opt/homebrew/opt/openjdk@21 ]]; then
  export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
elif [[ -d /usr/local/opt/openjdk@21 ]]; then
  export JAVA_HOME="/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  export PATH="/usr/local/opt/openjdk@21/bin:$PATH"
fi
EOF
}

zshrc_block_android_sdk() {
    cat <<'EOF'

# Android SDK
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
EOF
}

zshrc_block_local_bin() {
    cat <<'EOF'

# Binários de usuário (~/.local/bin — Claude Code, uv, pipx)
export PATH="$HOME/.local/bin:$PATH"
EOF
}

zshrc_block_flutter() {
    cat <<'EOF'

# Flutter SDK (se presente em um dos caminhos comuns)
for _fl in "$HOME/Development/FlutterProjects/flutter" "$HOME/development/flutter" "$HOME/flutter"; do
  if [[ -d "$_fl/bin" ]]; then
    export PATH="$PATH:$_fl/bin"
    break
  fi
done
unset _fl
EOF
}

zshrc_block_bun() {
    cat <<'EOF'

# bun (quando instalado via curl em ~/.bun; via Homebrew já entra no PATH)
if [[ -d "$HOME/.bun" ]]; then
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
fi
EOF
}

zshrc_block_api_keys() {
    cat <<'EOF'

# API Keys & Tokens (preencha com seus valores no novo Mac)
# export MAPBOX_DOWNLOADS_TOKEN="seu_token_aqui"
# export OPENAI_API_KEY="sua_chave_aqui"
EOF
}

zshrc_block_autosuggestions() {
    cat <<'EOF'

# zsh-autosuggestions (Homebrew)
if [[ -f "$(brew --prefix 2>/dev/null)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
EOF
}

zshrc_block_fzf() {
    cat <<'EOF'

# fzf — Ctrl-R (histórico), Ctrl-T (arquivos)
if command -v fzf &>/dev/null; then
  source <(fzf --zsh)
fi
EOF
}

zshrc_block_zoxide() {
    cat <<'EOF'

# zoxide — use "z <parte-do-caminho>" no lugar de cd
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi
EOF
}

zshrc_block_eza() {
    cat <<'EOF'

# eza (ls com ícones) — para o ls original: \ls ou command ls
if command -v eza &>/dev/null; then
  alias ls='eza --icons'
  alias ll='eza -l --icons'
  alias la='eza -la --icons'
  alias lt='eza --tree --icons'
fi
EOF
}

zshrc_block_bat() {
    cat <<'EOF'

# bat (cat com syntax highlight) — descomente para substituir o cat:
# alias cat='bat --paging=never --style=plain'
EOF
}

zshrc_block_syntax_highlighting() {
    cat <<'EOF'

# zsh-syntax-highlighting — deve ser o ÚLTIMO plugin carregado
if [[ -f "$(brew --prefix 2>/dev/null)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
EOF
}

zshrc_block_p10k_source() {
    cat <<'EOF'

# Powerlevel10k — execute 'p10k configure' para personalizar
if [[ -f /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme
elif [[ -f /usr/local/share/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/local/share/powerlevel10k/powerlevel10k.zsh-theme
fi
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
}

zshrc_block_starship() {
    cat <<'EOF'

# Starship — config em ~/.config/starship.toml (deve ser a última linha)
if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
fi
EOF
}

zshrc_block_footer() {
    cat <<'EOF'

# =============================================================================
# Fim da Configuração
# =============================================================================
EOF
}

write_zshrc() {
    local tmp
    tmp="$(mktempfile)"
    zshrc_block_header >> "$tmp"
    if [[ "$PROMPT_ACTIVE" == "p10k" ]]; then
        zshrc_block_p10k_instant >> "$tmp"
    fi
    if item_selected zsh-essentials; then
        zshrc_block_zsh_core >> "$tmp"
    fi
    zshrc_block_path >> "$tmp"
    if item_selected pyenv; then
        zshrc_block_pyenv >> "$tmp"
    fi
    if item_selected openjdk21; then
        zshrc_block_java >> "$tmp"
    fi
    if item_selected platform-tools; then
        zshrc_block_android_sdk >> "$tmp"
    fi
    zshrc_block_local_bin >> "$tmp"   # ~/.local/bin (Claude Code, uv, pipx)
    zshrc_block_flutter >> "$tmp"     # auto-guardado: só ativa se o SDK existir
    zshrc_block_bun >> "$tmp"         # auto-guardado: só ativa se ~/.bun existir
    zshrc_block_api_keys >> "$tmp"
    if item_selected zsh-essentials; then
        zshrc_block_autosuggestions >> "$tmp"
    fi
    if item_selected fzf; then
        zshrc_block_fzf >> "$tmp"
    fi
    if item_selected zoxide; then
        zshrc_block_zoxide >> "$tmp"
    fi
    if item_selected eza; then
        zshrc_block_eza >> "$tmp"
    fi
    if item_selected bat; then
        zshrc_block_bat >> "$tmp"
    fi
    if item_selected zsh-essentials; then
        zshrc_block_syntax_highlighting >> "$tmp"
    fi
    case "$PROMPT_ACTIVE" in
        p10k)     zshrc_block_p10k_source >> "$tmp" ;;
        starship) zshrc_block_starship >> "$tmp" ;;
    esac
    zshrc_block_footer >> "$tmp"
    backup_and_install_file "$tmp" "$HOME/.zshrc"
    ui_success ".zshrc escrito em $HOME/.zshrc"
    ui_warn "API keys (MAPBOX, OPENAI) estão comentadas. Edite ~/.zshrc se precisar."
    return 0
}

write_starship_config() {
    ensure_brew_in_path
    local tmp
    tmp="$(mktempfile)"
    # Preset oficial do Starship (tokyo-night padrão); fallback embutido offline
    if command -v starship &>/dev/null && starship preset "$STARSHIP_PRESET" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        backup_and_install_file "$tmp" "$HOME/.config/starship.toml"
        ui_success "starship.toml escrito (preset ${STARSHIP_PRESET})"
        return 0
    fi
    cat > "$tmp" <<'EOF'
# starship.toml — gerado por mac_env_install.sh (v3) · Event Horizon powerline (fallback)
# Requer Nerd Font no terminal (setas  e símbolos)
"$schema" = 'https://starship.rs/config-schema.json'
add_newline = true
palette = "event_horizon"

format = """
[░▒▓](amber)\
$directory\
[](fg:amber bg:surface)\
$git_branch\
$git_status\
[](fg:surface)\
$nodejs\
$python\
$java\
$cmd_duration
$character"""

[character]
success_symbol = "[❯](bold amber)"
error_symbol = "[❯](bold red)"

[directory]
style = "fg:crust bg:amber bold"
format = "[ $path ]($style)"
truncation_length = 4
truncate_to_repo = true

[git_branch]
symbol = ""
style = "bg:surface"
format = '[[ $symbol $branch ](fg:hot bg:surface)]($style)'

[git_status]
style = "bg:surface"
format = '[[($all_status$ahead_behind )](fg:hot bg:surface)]($style)'

[nodejs]
symbol = ""
format = '[ $symbol ($version)](fg:info)'

[python]
symbol = ""
format = '[ $symbol ($version)(\($virtualenv\))](fg:info)'

[java]
symbol = ""
format = '[ $symbol ($version)](fg:info)'

[cmd_duration]
min_time = 2000
style = "fg:muted"
format = "[  $duration]($style)"

[aws]
disabled = true

[gcloud]
disabled = true

[azure]
disabled = true

[docker_context]
disabled = true

[palettes.event_horizon]
ember = "#c47800"
amber = "#f5b000"
hot = "#ffd75e"
info = "#8892b0"
muted = "#5a6480"
cyan = "#00e5cc"
red = "#e63946"
crust = "#120b02"
surface = "#2b1f0a"
EOF
    backup_and_install_file "$tmp" "$HOME/.config/starship.toml"
    ui_success "starship.toml escrito (fallback Event Horizon — sem rede para o preset)"
    return 0
}

write_ghostty_config() {
    local dest="$HOME/.config/ghostty/config"
    local shader="$BLACKHOLE_DIR/blackhole.glsl"
    local want_shader=0
    if item_selected blackhole && [[ -f "$shader" ]]; then
        want_shader=1
    fi

    if [[ -f "$dest" ]]; then
        # Config existente: nunca sobrescrever; só anexar o shader se faltar
        if [[ "$want_shader" == "1" ]] && ! grep -q 'custom-shader' "$dest"; then
            cp "$dest" "${dest}.backup.$(date +%Y%m%d%H%M%S)"
            cat >> "$dest" <<EOF

# Blackhole shader (s0xDk/ghostty-blackhole) — adicionado por mac_env_install.sh
custom-shader = ${shader}
custom-shader-animation = true
EOF
            ui_success "Shader blackhole anexado ao ~/.config/ghostty/config (backup criado)"
        else
            echo -e "${MUTED}◇ ~/.config/ghostty/config existente — preservado${NC}"
        fi
        return 0
    fi

    local font="JetBrainsMono Nerd Font"
    if ! item_selected font-jetbrains && item_selected font-meslo; then
        font="MesloLGS Nerd Font"
    fi
    local tmp
    tmp="$(mktempfile)"
    cat > "$tmp" <<EOF
# ghostty config — gerado por mac_env_install.sh (v3)
font-family = ${font}
font-size = 14
cursor-color = #f5b000
window-padding-x = 8
window-padding-y = 8
background = #0e0e16
foreground = #e6e6f0
EOF
    if [[ "$want_shader" == "1" ]]; then
        cat >> "$tmp" <<EOF

# Blackhole shader (s0xDk/ghostty-blackhole)
custom-shader = ${shader}
custom-shader-animation = true
EOF
    fi
    backup_and_install_file "$tmp" "$dest"
    if [[ "$want_shader" == "1" ]]; then
        ui_success "Ghostty configurado (fonte: ${font}, cursor âmbar, shader blackhole)"
    else
        ui_success "Ghostty configurado (fonte: ${font}, cursor âmbar)"
    fi
    return 0
}

# Define terminal.integrated.fontFamily no settings.json do VS Code e do Cursor.
# Preserva valor existente; não toca em settings.json não-parseável (JSONC etc).
configure_editor_terminal_font() {
    if ! command -v python3 &>/dev/null; then
        ui_warn "python3 indisponível — defina terminal.integrated.fontFamily nos editores manualmente"
        return 0
    fi
    local font="JetBrainsMono Nerd Font Mono"
    if ! item_selected font-jetbrains && item_selected font-meslo; then
        font="MesloLGS Nerd Font Mono"
    fi
    local py
    py="$(mktempfile)"
    cat > "$py" <<'PYEOF'
import json, sys
src, font, out = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(src) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception:
    sys.exit(2)
if data.get("terminal.integrated.fontFamily"):
    sys.exit(3)
data["terminal.integrated.fontFamily"] = font
with open(out, "w") as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
    f.write("\n")
PYEOF
    local rec label appname supdir sfile tmpout rc
    for rec in "VS Code|Visual Studio Code|Code" "Cursor|Cursor|Cursor"; do
        IFS='|' read -r label appname supdir <<< "$rec"
        [[ -d "/Applications/${appname}.app" ]] || continue
        sfile="$HOME/Library/Application Support/${supdir}/User/settings.json"
        tmpout="$(mktempfile)"
        rc=0
        python3 "$py" "$sfile" "$font" "$tmpout" || rc=$?
        case "$rc" in
            0)
                backup_and_install_file "$tmpout" "$sfile"
                ui_success "${label}: fonte do terminal definida (${font})"
                ;;
            3)
                echo -e "${MUTED}◇ ${label}: fonte do terminal já definida — preservada${NC}"
                ;;
            *)
                ui_warn "${label}: settings.json não parseável — adicione terminal.integrated.fontFamily manualmente"
                ;;
        esac
    done
    return 0
}

setup_p10k() {
    if [[ -f "$HOME/.p10k.zsh" ]]; then
        ui_success "~/.p10k.zsh já existe — configuração mantida"
        return 0
    fi
    ui_info "Na primeira abertura do zsh, rode: p10k configure"
    return 0
}

# -----------------------------------------------------------------------------
# Relatório final
# -----------------------------------------------------------------------------
format_duration() {
    local s="$1"
    if [[ $s -ge 60 ]]; then
        echo "$((s / 60))m$((s % 60))s"
    else
        echo "${s}s"
    fi
}

print_final_report() {
    local total_secs="$1"
    echo ""
    if [[ "$COLOR_OK" == "1" ]]; then
        rule_sweep "━"
    fi

    local n_ok n_skip n_fail n_up
    n_ok="$(count_words "$RESULT_OK")"
    n_skip="$(count_words "$RESULT_SKIP")"
    n_fail="$(count_words "$RESULT_FAIL")"
    n_up="$(count_words "$RESULT_UP")"

    shimmer_line "  ◆  instalação concluída em $(format_duration "$total_secs")  ◆"
    echo -e "  ${SUCCESS}✓ ${n_ok} instalados${NC}  ${ACCENT}$( [[ "$n_up" -gt 0 ]] && echo "↑ ${n_up} atualizados" )${NC}  ${MUTED}◇ ${n_skip} já presentes${NC}  ${ERROR}$( [[ "$n_fail" -gt 0 ]] && echo "✗ ${n_fail} falharam" )${NC}"
    echo ""

    if [[ "$n_fail" -gt 0 ]]; then
        local body="" id
        for id in $RESULT_FAIL; do
            body="${body}✗ $(item_label "$id")"$'\n'
        done
        body="${body}"$'\n'"Re-execute com --verbose para ver os logs."
        if [[ -n "$GUM" ]]; then
            "$GUM" style --border rounded --border-foreground "#e63946" --padding "0 2" --width "$(($(term_cols) - 4))" "$body"
        else
            echo -e "${ERROR}Falhas:${NC}"
            echo "$body"
        fi
    fi

    local steps=""
    add_step() {
        steps="${steps}  • $1"$'\n'
    }
    if category_selected terminal; then
        add_step "Recarregue o shell:  exec zsh"
    fi
    if result_ok ghostty || { item_selected ghostty && [[ ! -f "$HOME/.config/ghostty/config" ]]; }; then
        add_step "Abra o Ghostty — fonte e cursor âmbar já configurados"
    fi
    if item_selected iterm2; then
        add_step "iTerm2: Settings → Profiles → Text → Font → fonte Nerd Font instalada"
    fi
    if [[ "$PROMPT_ACTIVE" == "starship" ]]; then
        add_step "Prompt Starship ativo — ajuste em ~/.config/starship.toml"
    fi
    if [[ "$PROMPT_ACTIVE" == "p10k" ]]; then
        add_step "Powerlevel10k: rode 'p10k configure' se quiser reconfigurar"
    fi
    if result_ok docker; then
        add_step "Abra o Docker.app uma vez para concluir a instalação"
    fi
    if result_ok supabase; then
        add_step "Supabase: rode 'supabase login'"
    fi
    if result_ok claude-code; then
        add_step "Claude Code: rode 'claude' para autenticar na primeira vez"
    fi
    if result_ok blackhole; then
        add_step "Shader blackhole ativo — reabra o Ghostty (ou Cmd+Shift+,) para ver"
    fi
    if result_ok android-studio; then
        add_step "Abra o Android Studio uma vez para instalar o SDK"
    fi
    if ! category_selected terminal && [[ -n "$RESULT_OK" ]]; then
        add_step "Seu ~/.zshrc não foi alterado — adicione os inits (pyenv, JAVA_HOME) se precisar"
    fi
    if [[ -n "$PENDING_UPDATES" && "$DO_UPGRADE" != "1" ]]; then
        add_step "Atualizações não aplicadas: re-execute com --upgrade (ou brew upgrade)"
    fi

    if [[ -n "$steps" ]]; then
        local card="Próximos passos:"$'\n'"$steps"
        if [[ -n "$GUM" ]]; then
            "$GUM" style --border rounded --border-foreground "#5a6480" --padding "0 1" --width "$(($(term_cols) - 4))" "$card"
        else
            echo -e "${INFO}${card}${NC}"
        fi
    fi

    if [[ "$n_fail" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local main_start=$SECONDS

    bootstrap_gum_temp || true
    apply_gum_theme
    print_installer_banner
    print_gum_status
    detect_macos_or_die

    resolve_selection
    compute_stages
    print_plan_summary

    if [[ "$DRY_RUN" == "1" ]]; then
        ui_info "--dry-run: nada foi instalado."
        exit 0
    fi

    if can_prompt; then
        if ! gum_confirm_tty "Instalar agora?" --affirmative "Instalar" --negative "Cancelar"; then
            ui_info "Instalação cancelada."
            exit 0
        fi
    fi

    install_xcode_clt

    ui_stage "Base"
    install_homebrew
    scan_outdated
    offer_upgrades

    local rec id label desc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        if category_selected "$id"; then
            ui_stage "$label"
            run_category "$id"
        fi
    done

    if category_selected terminal; then
        ui_stage "Configurações"
        write_zshrc
        if [[ "$PROMPT_ACTIVE" == "starship" ]]; then
            write_starship_config
        fi
        if [[ "$PROMPT_ACTIVE" == "p10k" ]]; then
            setup_p10k
        fi
        if item_selected ghostty; then
            write_ghostty_config
        fi
        configure_editor_terminal_font
    fi

    print_final_report $((SECONDS - main_start))
}

parse_args "$@"
main
