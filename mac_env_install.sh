#!/bin/bash
# shellcheck disable=SC2034,SC2088
# SC2034: o padrão IFS='|' read descompacta todos os campos dos registros
#         mesmo quando nem todos são usados; SC2088: "~" aparece só em
#         strings de exibição, nunca como caminho.
# =============================================================================
# Mac Environment Installer v3 — instalador por categorias com seletor
# Uso local:  bash mac_env_install.sh [opções]
# Uso remoto: curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- [opções]
# Opções:     --profile completo|terminal|dev|mobile · --categories a,b,c
#             --all · --yes · --dry-run · --list · --verbose · --help
# Requer:     macOS (Apple Silicon ou Intel)
# =============================================================================
set -euo pipefail

MACENV_VERSION="4.0.1"
MACENV_RAW_URL="https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh"
MACENV_TUI_VERSION="0.1.1"   # release tui-vX.Y.Z pinado (binário + checksums)

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
    # shellcheck disable=SC2206  # split intencional das paradas da rampa
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

BANNER_ART=(
    "               ░░▒▒▓▓██████████▓▓▒▒░░"
    "           ░▒▓████████████████████████▓▒░"
    "         ▒████▓▒░░                ░░▒▓████▒"
    "        ▓███▒                          ▒███▓"
    "         ▒████▓▒░░                ░░▒▓████▒"
    "           ░▒▓████████████████████████▓▒░"
    "               ░░▒▒▓▓██████████▓▓▒▒░░"
)

# O buraco negro gira: a luz da rampa percorre o anel já desenhado na tela
# (pressupõe a arte pintada imediatamente acima do cursor)
blackhole_spin() {
    local frames="${1:-10}"
    if [[ "$ANIM_OK" != "1" || ! -t 1 ]]; then
        return 0
    fi
    tput civis 2>/dev/null || true
    local f row r
    for ((f = 1; f <= frames; f++)); do
        sleep 0.06
        tput cuu ${#BANNER_ART[@]} 2>/dev/null || break
        r=0
        for row in "${BANNER_ART[@]}"; do
            printf '\r'
            tput el 2>/dev/null || true
            gradient_text "$row" $(((f * 260 + r * 140) % 2000))
            r=$((r + 1))
        done
    done
    tput cnorm 2>/dev/null || true
    return 0
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
    reveal_lines "${BANNER_ART[@]}"
    blackhole_spin 10
    echo ""
    shimmer_line "               ◆  M A C · E N V  ◆"
    echo -e "${INFO}        ambiente de desenvolvimento macOS ${MUTED}· v${MACENV_VERSION}${NC}"
    echo ""
    if [[ -t 1 ]]; then
        tput cnorm 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# UI — calha vertical conectada (│ ◇ ◆) estilo clack; ANSI puro com gutter.
# gum fica só para choose/confirm/style (cards); mensagens nunca passam por ele.
# -----------------------------------------------------------------------------
GUT="${MUTED}│${NC} "

ui_info() {
    bar_clear
    echo -e "${GUT}${MUTED}·${NC} $*"
}

ui_warn() {
    bar_clear
    echo -e "${GUT}${WARN}!${NC} $*"
}

ui_success() {
    bar_clear
    echo -e "${GUT}${SUCCESS}✓${NC} $*"
}

ui_error() {
    bar_clear
    echo -e "${GUT}${ERROR}✗${NC} $*"
}

# item concluído com cronômetro / item pulado
ui_done() {
    bar_clear
    local label="$1"
    local secs="${2:-0}"
    local suffix=""
    if [[ "$secs" -gt 1 ]]; then
        suffix=" · ${secs}s"
    fi
    echo -e "${GUT}${SUCCESS}✓${NC} ${label}${MUTED}${suffix}${NC}"
}

ui_skip() {
    bar_clear
    echo -e "${GUT}${MUTED}◇ ${1} — já instalado${NC}"
}

# Fluxo de seleção estilo clack: pergunta fica visível e vira resposta
flow_node() {
    echo -e "${GUT}"
    echo -e "${GUT}${ACCENT}◇${NC} ${BOLD}$1${NC}"
}

flow_done() {
    echo -e "${GUT}${SUCCESS}◆${NC} $1"
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

# Barra orbit "viva": fica pinada como última linha e é redesenhada a cada item.
BAR_VISIBLE=0

bar_live_capable() {
    [[ "$COLOR_OK" == "1" && -t 1 && "$ITEMS_TOTAL" -gt 0 && "${VERBOSE:-0}" != "1" ]]
}

progress_orbit_render() {
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
    printf '\033[38;2;90;100;128m│\033[0m %s\033[0m \033[38;2;90;100;128m%s/%s itens\033[0m' \
        "$out" "$ITEMS_DONE" "$ITEMS_TOTAL"
}

bar_show() {
    bar_live_capable || return 0
    progress_orbit_render
    BAR_VISIBLE=1
    return 0
}

bar_clear() {
    if [[ "$BAR_VISIBLE" == "1" ]]; then
        printf '\r'
        tput el 2>/dev/null || true
        BAR_VISIBLE=0
    fi
    return 0
}

ui_stage() {
    local title="$1"
    INSTALL_STAGE_CURRENT=$((INSTALL_STAGE_CURRENT + 1))
    bar_clear
    if [[ "$COLOR_OK" == "1" ]]; then
        echo -e "${GUT}"
        local head="├── [${INSTALL_STAGE_CURRENT}/${INSTALL_STAGE_TOTAL}] ${title} "
        local w fill pad
        w="$(term_cols)"
        fill=$((w - ${#head}))
        if [[ $fill -lt 4 ]]; then
            fill=4
        fi
        printf -v pad '%*s' "$fill" ''
        pad=${pad// /─}
        reveal_sweep "${head}${pad}"
        bar_show
    else
        echo ""
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

    # MACENV_INNER=1: rodando sob o spinner de item do run_item — sem gum spin aninhado
    if [[ -n "$GUM" && -z "${MACENV_INNER:-}" ]] && gum_is_tty && ! is_shell_function "${1:-}"; then
        "$GUM" spin --spinner dot --title "$title" -- "$@"
        return $?
    fi

    "$@"
}

# spin_while <pid> <label> — anima braille âmbar na linha até o pid terminar;
# a linha é apagada ao final (o chamador imprime o resultado no lugar).
SPIN_FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
spin_while() {
    local pid="$1"
    local label="$2"
    local i=0 ch rc=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        ch="${SPIN_FRAMES:$((i % 10)):1}"
        printf '\r\033[38;2;90;100;128m│\033[0m \033[38;2;245;176;0m%s\033[0m %s' "$ch" "$label"
        i=$((i + 1))
        sleep 0.08
    done
    wait "$pid" 2>/dev/null || rc=$?
    printf '\r'
    tput el 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    return $rc
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
    "ios|Mobile iOS|Xcode (opcional), CocoaPods (builds Flutter/iOS)"
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
    "xcode|ios|Xcode (App Store, ~12 GB)|0||IDE da Apple via mas — exige login na App Store"
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
SELECTION_MODE="preset" # preset | custom | repeat
ITEM_TIMES=""           # "id:segundos" por item processado

# Estado persistente (última seleção + relatório da última execução)
MACENV_STATE_DIR="$HOME/.config/macenv"

save_selection_state() {
    mkdir -p "$MACENV_STATE_DIR" 2>/dev/null || return 0
    {
        echo "# última seleção — mac_env_install.sh ($(date '+%Y-%m-%d %H:%M'))"
        echo "PROFILE_LABEL=${PROFILE_LABEL}"
        echo "SELECTED_CATEGORIES=${SELECTED_CATEGORIES}"
        echo "SELECTED_ITEMS=${SELECTED_ITEMS}"
        echo "PROMPT_ACTIVE=${PROMPT_ACTIVE}"
        echo "TERMINAL_CHOICE=${TERMINAL_CHOICE}"
        echo "STARSHIP_PRESET=${STARSHIP_PRESET}"
    } > "$MACENV_STATE_DIR/state" 2>/dev/null || true
    return 0
}

item_exists() {
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        if [[ "$id" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

# Carrega a última seleção, filtrando ids/categorias que saíram do catálogo
load_selection_state() {
    local f="$MACENV_STATE_DIR/state" line
    [[ -f "$f" ]] || return 1
    while IFS= read -r line; do
        case "$line" in
            PROFILE_LABEL=*)       PROFILE_LABEL="${line#*=}" ;;
            SELECTED_CATEGORIES=*) SELECTED_CATEGORIES="${line#*=}" ;;
            SELECTED_ITEMS=*)      SELECTED_ITEMS="${line#*=}" ;;
            PROMPT_ACTIVE=*)       PROMPT_ACTIVE="${line#*=}" ;;
            TERMINAL_CHOICE=*)     TERMINAL_CHOICE="${line#*=}" ;;
            STARSHIP_PRESET=*)     STARSHIP_PRESET="${line#*=}" ;;
        esac
    done < "$f"
    local filtered="" it
    for it in $SELECTED_ITEMS; do
        if item_exists "$it"; then
            filtered="$filtered $it"
        fi
    done
    SELECTED_ITEMS="$filtered"
    filtered=""
    for it in $SELECTED_CATEGORIES; do
        if preset_valid_category "$it"; then
            filtered="$filtered $it"
        fi
    done
    SELECTED_CATEGORIES="$filtered"
    [[ -n "${SELECTED_ITEMS// /}" && -n "${SELECTED_CATEGORIES// /}" ]] || return 1
    return 0
}

state_summary() {
    local label
    label="$(grep -m1 '^PROFILE_LABEL=' "$MACENV_STATE_DIR/state" 2>/dev/null | cut -d= -f2- || true)"
    local items
    items="$(grep -m1 '^SELECTED_ITEMS=' "$MACENV_STATE_DIR/state" 2>/dev/null | cut -d= -f2- || true)"
    echo "${label:-?} · $(count_words "$items") itens"
}

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

item_id_by_label() {
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        if [[ "$label" == "$1" ]]; then
            echo "$id"
            return 0
        fi
    done
    return 1
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
DOCTOR=0
UPGRADE_ONLY=0
SELF_UPDATE=0
RESTORE_ZSHRC=0
REMOVE_ARG=""

print_usage() {
    cat <<'USAGE'
Mac Environment Installer v3

Uso:
  bash mac_env_install.sh [opções]
  curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- [opções]

Sem opções (em terminal interativo): abre o seletor de perfis e categorias.

Opções:
  --profile <p>       Perfil sem interação: completo | terminal | dev | mobile | last
                      (last = repete a última instalação salva)
  --categories a,b,c  Categorias sem interação: terminal,dev,cloud,android,ios,apps
  --all               Tudo (equivale a --profile completo)
  --upgrade           Atualiza itens já instalados que tenham versão nova no brew
  --upgrade-only      Só atualiza o que está instalado e sai (sem instalar nada novo)
  --doctor            Diagnóstico do ambiente (nada é instalado ou alterado)
  --tui               Usa o seletor alternativo em tela cheia (busca, hotkeys)
  --self-update       Atualiza este script para a versão do branch main
  --restore-zshrc     Restaura o backup mais recente do ~/.zshrc e sai
  --remove a,b,c      Remove itens do catálogo (com confirmação; headless exige --yes)
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
            --upgrade-only) UPGRADE_ONLY=1 ;;
            --doctor)       DOCTOR=1 ;;
            --tui)          MACENV_USE_TUI=1 ;;
            --self-update)  SELF_UPDATE=1 ;;
            --restore-zshrc) RESTORE_ZSHRC=1 ;;
            --remove)       REMOVE_ARG="${2:-}"; shift ;;
            --remove=*)     REMOVE_ARG="${1#*=}" ;;
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
# -----------------------------------------------------------------------------
# Seletor TUI (macenv-tui, Bubble Tea) — baixado como o gum: temp + SHA-256,
# nunca instalado. Qualquer falha cai no fluxo gum (fallback permanente).
# -----------------------------------------------------------------------------
TUI_BIN=""
TUI_REASON=""

# O TUI é OPT-IN (--tui ou MACENV_USE_TUI=1): o fluxo gum é o padrão preferido.
bootstrap_tui_temp() {
    TUI_BIN=""
    TUI_REASON=""
    case "${MACENV_USE_TUI:-0}" in
        1|true|True|TRUE|on|ON|yes|YES) ;;
        *)
            TUI_REASON="opt-in: use --tui ou MACENV_USE_TUI=1"
            return 1
            ;;
    esac
    if ! command -v tar &>/dev/null; then
        TUI_REASON="tar ausente"
        return 1
    fi
    local base="https://github.com/aleonnet/mac-env-setup/releases/download/tui-v${MACENV_TUI_VERSION}"
    local asset="macenv-tui_${MACENV_TUI_VERSION}_Darwin_universal.tar.gz"
    local dir
    dir="$(mktemp -d)"
    TMPFILES+=("$dir")
    if ! download_file "$base/$asset" "$dir/$asset"; then
        TUI_REASON="download falhou"
        return 1
    fi
    if ! download_file "$base/checksums.txt" "$dir/checksums.txt"; then
        TUI_REASON="checksums indisponíveis"
        return 1
    fi
    if ! (cd "$dir" && verify_sha256sum_file "checksums.txt"); then
        TUI_REASON="checksum não confere"
        return 1
    fi
    if ! tar -xzf "$dir/$asset" -C "$dir" 2>/dev/null; then
        TUI_REASON="extração falhou"
        return 1
    fi
    chmod +x "$dir/macenv-tui" 2>/dev/null || true
    if [[ ! -x "$dir/macenv-tui" ]]; then
        TUI_REASON="binário inválido"
        return 1
    fi
    TUI_BIN="$dir/macenv-tui"
    return 0
}

# Itens de um perfil, sem tocar na seleção corrente (subshell)
profile_items() {
    (
        # shellcheck disable=SC2046
        apply_categories $(preset_categories "$1") >/dev/null 2>&1
        echo "$SELECTED_ITEMS"
    )
}

# Escreve o catálogo no protocolo do macenv-tui e roda o seletor.
# Retorno: 0 = seleção feita; 1 = indisponível (fallback gum); sai 130 se cancelado.
tui_selection() {
    if ! bootstrap_tui_temp; then
        # silencioso quando é só o opt-in; barulhento quando o usuário pediu e falhou
        if [[ "${MACENV_USE_TUI:-0}" != "0" ]]; then
            ui_warn "Seletor TUI indisponível (${TUI_REASON}) — usando o fluxo padrão."
        fi
        return 1
    fi
    # seleção inicial: última instalação salva, senão defaults do perfil dev
    apply_categories terminal dev apps
    if [[ -f "$MACENV_STATE_DIR/state" ]]; then
        local saved filtered="" it
        saved="$(grep -m1 '^SELECTED_ITEMS=' "$MACENV_STATE_DIR/state" | cut -d= -f2- || true)"
        for it in $saved; do
            if item_exists "$it"; then
                filtered="$filtered $it"
            fi
        done
        if [[ -n "${filtered// /}" ]]; then
            SELECTED_ITEMS="$filtered"
        fi
    fi
    local catfile rec id cat label def pkgs desc sel
    catfile="$(mktempfile)"
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        echo "C|${id}|${label}" >> "$catfile"
    done
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        sel=0
        if item_selected "$id"; then
            sel=1
        fi
        echo "I|${id}|${cat}|${label}|${sel}|${desc}" >> "$catfile"
    done
    local pname
    for pname in Completo Terminal Dev Mobile; do
        local plower
        plower="$(echo "$pname" | tr '[:upper:]' '[:lower:]')"
        echo "P|${pname}|$(profile_items "$plower")" >> "$catfile"
    done

    local out rc=0
    out="$("$TUI_BIN" "$catfile")" || rc=$?
    if [[ $rc -eq 130 ]]; then
        selection_cancelled
    fi
    if [[ $rc -ne 0 ]]; then
        ui_warn "Seletor TUI falhou (rc=${rc}) — usando o fluxo padrão."
        return 1
    fi
    local line ids
    if ! line="$(printf '%s\n' "$out" | grep -m1 '^ITEMS ')"; then
        return 1
    fi
    ids="${line#ITEMS }"
    if [[ -z "${ids// /}" ]]; then
        selection_cancelled
    fi
    SELECTED_ITEMS=""
    local it
    for it in $ids; do
        if item_exists "$it"; then
            select_item "$it"
        fi
    done
    SELECTED_CATEGORIES=""
    local irec iid icat ilabel idef ipkgs idesc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r id label desc <<< "$rec"
        for irec in "${ITEM_DB[@]}"; do
            IFS='|' read -r iid icat ilabel idef ipkgs idesc <<< "$irec"
            if [[ "$icat" == "$id" ]] && item_selected "$iid"; then
                SELECTED_CATEGORIES="$SELECTED_CATEGORIES $id"
                break
            fi
        done
    done
    PROFILE_LABEL="Personalizado (TUI)"
    SELECTION_MODE="custom"
    flow_done "Seleção via TUI: $(count_words "$SELECTED_ITEMS") itens"
    derive_choices_from_items
    return 0
}

can_prompt() {
    [[ -n "$GUM" ]] || return 1
    if [[ "$ASSUME_YES" == "1" || "$ALL" == "1" ]]; then
        return 1
    fi
    if [[ -n "$PROFILE" || -n "$CATEGORIES_ARG" ]]; then
        return 1
    fi
    [[ -r /dev/tty && -w /dev/tty ]] || return 1
    ( : </dev/tty ) 2>/dev/null || return 1   # -r/-w não bastam: sessões detached falham no open
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
    flow_node "Perfil de instalação"
    local opts=()
    if [[ -f "$MACENV_STATE_DIR/state" ]]; then
        opts+=("Repetir última instalação — $(state_summary)")
    fi
    opts+=(
        "Completo — tudo: terminal, dev, cloud, android, ios, apps"
        "Terminal bonito — Ghostty, Starship, fontes, eza/fzf/zoxide/bat"
        "Dev — Terminal bonito + git, Docker, Node, pyenv + apps"
        "Mobile — Dev básico + Android + iOS (Flutter)"
        "Personalizado — escolher categorias e itens"
    )
    local sel
    sel="$(gum_choose_tty --header "Escolha um perfil de instalação" "${opts[@]}")" || selection_cancelled
    case "$sel" in
        Repetir*)
            if ! load_selection_state; then
                ui_error "Estado anterior inválido (~/.config/macenv/state) — escolha um perfil."
                exit 1
            fi
            SELECTION_MODE="repeat"
            PROFILE_LABEL="${PROFILE_LABEL} (repetida)"
            ;;
        Completo*)  PROFILE_LABEL="Completo";  apply_categories terminal dev cloud android ios apps ;;
        Terminal*)  PROFILE_LABEL="Terminal bonito"; apply_categories terminal ;;
        Dev*)       PROFILE_LABEL="Dev";       apply_categories terminal dev apps ;;
        Mobile*)    PROFILE_LABEL="Mobile";    apply_categories terminal dev android ios ;;
        Personalizado*)
            PROFILE_LABEL="Personalizado"
            SELECTION_MODE="custom"
            refine_categories
            ;;
        *) selection_cancelled ;;
    esac
    flow_done "Perfil: ${PROFILE_LABEL}"
    return 0
}

# Personalizado: ajuste fino por item dentro das categorias escolhidas
select_items_within() {
    local rec id cat label def pkgs desc opt opts=() presel=""
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        category_selected "$cat" || continue
        opt="${label} — ${desc//,/ ·}"
        opts+=("$opt")
        if item_selected "$id"; then
            if [[ -n "$presel" ]]; then
                presel="${presel},${opt}"
            else
                presel="$opt"
            fi
        fi
    done
    if [[ ${#opts[@]} -eq 0 ]]; then
        return 0
    fi
    flow_node "Itens (espaço marca, enter confirma)"
    local sel line lbl iid
    sel="$(gum_choose_tty --no-limit --height 18 --header "Ajuste os itens da instalação" \
        --selected "$presel" "${opts[@]}")" || selection_cancelled
    if [[ -z "$sel" ]]; then
        selection_cancelled
    fi
    SELECTED_ITEMS=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        lbl="${line%% — *}"
        if iid="$(item_id_by_label "$lbl")"; then
            select_item "$iid"
        fi
    done <<< "$sel"
    flow_done "Itens: $(count_words "$SELECTED_ITEMS") selecionados"
    return 0
}

# Deriva TERMINAL_CHOICE/PROMPT_ACTIVE da seleção por item (modo Personalizado)
derive_choices_from_items() {
    TERMINAL_CHOICE=""
    if item_selected ghostty && item_selected iterm2; then
        TERMINAL_CHOICE="ambos"
    elif item_selected ghostty; then
        TERMINAL_CHOICE="ghostty"
    elif item_selected iterm2; then
        TERMINAL_CHOICE="iterm2"
    fi
    PROMPT_ACTIVE=""
    if item_selected starship && item_selected p10k; then
        if [[ -n "$GUM" ]]; then
            flow_node "Prompt do shell"
            local sel
            sel="$(gum_choose_tty --header "Os dois prompts serão instalados — qual ativar no zsh?" \
                "Starship" "Powerlevel10k")" || selection_cancelled
            case "$sel" in
                Starship*) PROMPT_ACTIVE="starship" ;;
                *)         PROMPT_ACTIVE="p10k" ;;
            esac
            flow_done "Prompt ativo: ${sel}"
        else
            PROMPT_ACTIVE="starship"
            ui_warn "Dois prompts selecionados sem seletor — ativando Starship."
        fi
    elif item_selected starship; then
        PROMPT_ACTIVE="starship"
    elif item_selected p10k; then
        PROMPT_ACTIVE="p10k"
    fi
    if [[ "$PROMPT_ACTIVE" == "p10k" ]] && ! item_selected font-meslo && ! item_selected font-jetbrains; then
        select_item font-meslo
    fi
    if [[ "$PROMPT_ACTIVE" == "starship" ]]; then
        select_starship_preset
    fi
    return 0
}

select_starship_preset() {
    [[ -n "$GUM" ]] || return 0   # sem seletor: mantém o preset padrão
    local preset
    preset="$(gum_choose_tty --header "Estilo do prompt Starship" \
        "Tokyo Night — cápsulas arredondadas, azul/cinza (recomendado)" \
        "Catppuccin Powerline — segmentos pastel")" || selection_cancelled
    case "$preset" in
        Tokyo*)      STARSHIP_PRESET="tokyo-night" ;;
        Catppuccin*) STARSHIP_PRESET="catppuccin-powerline" ;;
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
    flow_node "Terminal"
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
    flow_done "Terminal: ${TERMINAL_CHOICE}"
    return 0
}

select_prompt_choice() {
    category_selected terminal || return 0
    flow_node "Prompt do shell"
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
            select_starship_preset
            ;;
        Powerlevel10k*)
            PROMPT_ACTIVE="p10k"
            select_item p10k
            deselect_item starship
            select_item font-meslo   # fonte recomendada oficialmente pelo p10k
            ;;
    esac
    if [[ "$PROMPT_ACTIVE" == "starship" ]]; then
        flow_done "Prompt: Starship · preset ${STARSHIP_PRESET}"
    else
        flow_done "Prompt: Powerlevel10k"
    fi
    return 0
}

interactive_selection() {
    select_profile
    case "$SELECTION_MODE" in
        repeat)
            ;;   # tudo carregado do estado salvo
        custom)
            select_items_within
            derive_choices_from_items
            ;;
        *)
            select_terminal_choice
            select_prompt_choice
            ;;
    esac
    return 0
}

resolve_selection() {
    if [[ "$ALL" == "1" ]]; then
        PROFILE_LABEL="Completo"
        apply_categories terminal dev cloud android ios apps
        return 0
    fi
    if [[ -n "$PROFILE" ]]; then
        if [[ "$PROFILE" == "last" ]]; then
            if ! load_selection_state; then
                ui_error "Nenhuma instalação anterior salva (~/.config/macenv/state)."
                exit 1
            fi
            SELECTION_MODE="repeat"
            PROFILE_LABEL="${PROFILE_LABEL} (repetida)"
            return 0
        fi
        local cats
        if ! cats="$(preset_categories "$PROFILE")"; then
            ui_error "Perfil desconhecido: ${PROFILE} (use completo|terminal|dev|mobile|last)"
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
        if tui_selection; then
            return 0
        fi
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

# Xcode completo via mas (Mac App Store CLI). App id 497799835.
# Atualizações ficam com a própria App Store (campo pacotes vazio de propósito).
install_xcode() {
    if [[ -d "/Applications/Xcode.app" ]]; then
        return 100
    fi
    ensure_brew_in_path
    if ! command -v mas &>/dev/null; then
        run_quiet_step "Instalando mas (Mac App Store CLI)" brew install mas || return 1
    fi
    ui_info "Baixando Xcode da App Store (~12 GB — pode demorar bastante)..."
    if ! run_quiet_step "Instalando Xcode via mas" mas install 497799835; then
        ui_warn "Falhou — abra o app App Store, entre com seu Apple ID e re-execute."
        return 1
    fi
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
    bar_clear
    local label="$1"
    local secs="${2:-0}"
    local suffix=" · atualizado"
    if [[ "$secs" -gt 1 ]]; then
        suffix="${suffix} em ${secs}s"
    fi
    echo -e "${GUT}${ACCENT}↑${NC} ${label}${MUTED}${suffix}${NC}"
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
    local fn_out=""
    if bar_live_capable; then
        # spinner de item que se transforma no resultado (a fn roda em subshell;
        # set +e preserva o contrato de retorno 0/100/1 sem errexit interno)
        bar_clear
        fn_out="$(mktempfile)"
        ( set +e; export MACENV_INNER=1; "$fn" ) >"$fn_out" 2>&1 &
        spin_while $! "$label" || rc=$?
    else
        "$fn" || rc=$?
    fi
    local elapsed=$((SECONDS - start))
    ITEMS_DONE=$((ITEMS_DONE + 1))
    ITEM_TIMES="$ITEM_TIMES ${id}:${elapsed}"
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
                    echo -e "${GUT}${MUTED}◇ ${label} — instalado ${NC}${ACCENT}(atualização disponível)${NC}"
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
    # saída interna da fn (avisos, tail de log em falha) — indentada sob o item
    if [[ -n "$fn_out" && -s "$fn_out" ]]; then
        sed $'s/^/\033[38;2;90;100;128m│\033[0m   /' "$fn_out"
    fi
    bar_show
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
        local backup
        backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
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

# Setas ↑/↓ buscam no histórico pelo prefixo já digitado
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search
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

# Migra para o novo .zshrc tudo que estiver APÓS o rodapé do arquivo anterior —
# é onde instaladores externos anexam (Claude Code, bun, etc). O marcador
# "Fim da Configuração" é estrutural: NUNCA renomear sem migração.
# Dedupe (classe export/alias/source/eval) contra o novo arquivo e entre si;
# linhas de outras classes (if/fi etc.) passam verbatim para não quebrar blocos.
zshrc_migrate_tail() {
    local old="$1"
    local new="$2"
    [[ -f "$old" ]] || return 0
    grep -qF '# Fim da Configuração' "$old" || return 0
    local collected
    collected="$(awk '
        f {
            if ($0 ~ /^# =====/) next
            if ($0 ~ /^# ─────/) next
            if ($0 ~ /^# Suas adições/) next
            print
        }
        /# Fim da Configuração/ { f = 1 }
    ' "$old")"
    if [[ -z "${collected//[[:space:]]/}" ]]; then
        return 0
    fi
    local line out="" seen=$'\n'
    while IFS= read -r line; do
        if [[ -z "${line//[[:space:]]/}" ]]; then
            continue
        fi
        case "$line" in
            export\ *|alias\ *|source\ *|eval\ *)
                if grep -qxF "$line" "$new"; then
                    continue
                fi
                case "$seen" in
                    *$'\n'"$line"$'\n'*) continue ;;
                esac
                seen="${seen}${line}"$'\n'
                ;;
        esac
        out="${out}${line}"$'\n'
    done <<< "$collected"
    if [[ -z "${out//[[:space:]]/}" ]]; then
        return 0
    fi
    {
        echo ""
        echo "# ─────────────────────────────────────────────────────────────────────────────"
        echo "# Suas adições — preservadas automaticamente do .zshrc anterior"
        echo "# ─────────────────────────────────────────────────────────────────────────────"
        printf '%s' "$out"
    } >> "$new"
    local n
    n="$(printf '%s' "$out" | grep -c . || true)"
    ui_info "Preservadas ${n} linha(s) suas do .zshrc anterior (seção 'Suas adições')"
    return 0
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
    zshrc_migrate_tail "$HOME/.zshrc" "$tmp"
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

# Não use #f5b000: ele é interpretado pelo shader (canal do token mode)
cursor-color = #f5a000

window-padding-x = 8
window-padding-y = 8

background = #0e0e16
foreground = #e6e6f0

# Fundo translúcido com blur (estilo iTerm2)
background-opacity = 0.85
background-blur = 20
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

# Fonte Nerd no perfil padrão do iTerm2 — via defaults export/import (respeita o
# cfprefsd). iTerm2 aberto ou sem plist: cai para Dynamic Profile (hot-load).
configure_iterm2_font() {
    item_selected iterm2 || return 0
    local psfont="JetBrainsMonoNFM-Regular 14"
    if ! item_selected font-jetbrains && item_selected font-meslo; then
        psfont="MesloLGSNerdFontMono-Regular 14"
    fi
    local tmp current
    tmp="$(mktempfile)"
    if ! pgrep -xq iTerm2 && defaults export com.googlecode.iterm2 "$tmp" 2>/dev/null; then
        if current="$(/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Normal Font"' "$tmp" 2>/dev/null)"; then
            case "$current" in
                *NFM*|*NerdFont*|*"Nerd Font"*)
                    echo -e "${GUT}${MUTED}◇ iTerm2: fonte Nerd já configurada — preservada${NC}"
                    return 0
                    ;;
            esac
            if /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Normal Font\" ${psfont}" "$tmp" 2>/dev/null \
                && defaults import com.googlecode.iterm2 "$tmp" 2>/dev/null; then
                ui_success "iTerm2: fonte do perfil padrão definida (${psfont%% *})"
                return 0
            fi
        fi
    fi
    local dyn="$HOME/Library/Application Support/iTerm2/DynamicProfiles/macenv.json"
    if [[ -f "$dyn" ]]; then
        echo -e "${GUT}${MUTED}◇ iTerm2: perfil dinâmico MacEnv já existe — preservado${NC}"
        return 0
    fi
    mkdir -p "$(dirname "$dyn")"
    cat > "$dyn" <<EOF
{ "Profiles": [ { "Name": "MacEnv", "Guid": "macenv-nerd-font", "Normal Font": "${psfont}" } ] }
EOF
    ui_success "iTerm2: perfil dinâmico 'MacEnv' criado com fonte Nerd (Profiles → MacEnv)"
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
item_time() {
    local e
    for e in $ITEM_TIMES; do
        if [[ "${e%%:*}" == "$1" ]]; then
            echo "${e#*:}"
            return 0
        fi
    done
    echo 0
}

# Espelha o resultado em ~/.config/macenv/last-run.log (texto puro, com tempos)
write_run_log() {
    local total="$1"
    mkdir -p "$MACENV_STATE_DIR" 2>/dev/null || return 0
    local f="$MACENV_STATE_DIR/last-run.log" id
    {
        echo "mac_env_install.sh — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "perfil: ${PROFILE_LABEL} · duração: $(format_duration "$total")"
        echo ""
        for id in $RESULT_OK; do
            echo "instalado    $(item_label "$id") ($(item_time "$id")s)"
        done
        for id in $RESULT_UP; do
            echo "atualizado   $(item_label "$id") ($(item_time "$id")s)"
        done
        for id in $RESULT_SKIP; do
            echo "já presente  $(item_label "$id")"
        done
        for id in $RESULT_FAIL; do
            echo "FALHOU       $(item_label "$id")"
        done
        if [[ -n "$PENDING_UPDATES" && "$DO_UPGRADE" != "1" ]]; then
            echo ""
            echo "atualizações pendentes — rode com --upgrade-only"
        fi
    } > "$f" 2>/dev/null || return 0
    ui_info "Relatório salvo em ~/.config/macenv/last-run.log"
    return 0
}

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
    bar_clear
    if [[ "$COLOR_OK" == "1" ]]; then
        echo -e "${GUT}"
        local w line
        w="$(term_cols)"
        printf -v line '%*s' "$((w - 3))" ''
        reveal_sweep "╰──${line// /─}"
        echo ""
    else
        echo ""
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
    if result_ok xcode; then
        add_step "Abra o Xcode uma vez para aceitar a licença e instalar componentes"
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

    write_run_log "$total_secs"

    if [[ "$n_fail" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# --self-update: substitui este arquivo pela versão do branch main
# -----------------------------------------------------------------------------
run_self_update() {
    local self="${BASH_SOURCE[0]:-}"
    if [[ -z "$self" || ! -f "$self" ]]; then
        ui_info "Execução via pipe (curl | bash) já usa sempre a versão remota — nada a atualizar."
        return 0
    fi
    local tmp
    tmp="$(mktempfile)"
    if ! download_file "$MACENV_RAW_URL" "$tmp"; then
        ui_error "Falha ao baixar a versão remota."
        return 1
    fi
    if ! bash -n "$tmp" 2>/dev/null; then
        ui_error "Download remoto inválido — atualização abortada."
        return 1
    fi
    local h_local h_remote
    h_local="$(shasum -a 256 "$self" | awk '{print $1}')"
    h_remote="$(shasum -a 256 "$tmp" | awk '{print $1}')"
    if [[ "$h_local" == "$h_remote" ]]; then
        ui_success "Já está na versão mais recente (v${MACENV_VERSION})."
        return 0
    fi
    local remote_ver
    remote_ver="$(grep -m1 '^MACENV_VERSION=' "$tmp" | cut -d'"' -f2 || true)"
    if can_prompt; then
        if ! gum_confirm_tty "Atualizar v${MACENV_VERSION} → v${remote_ver:-?}?" --affirmative "Atualizar" --negative "Cancelar"; then
            ui_info "Atualização cancelada."
            return 0
        fi
    fi
    cp "$self" "${self}.bak"
    cat "$tmp" > "$self"
    chmod +x "$self" 2>/dev/null || true
    ui_success "Atualizado para v${remote_ver:-nova} (backup em ${self}.bak)"
    return 0
}

# -----------------------------------------------------------------------------
# --restore-zshrc: volta o backup mais recente do ~/.zshrc
# -----------------------------------------------------------------------------
run_restore_zshrc() {
    local latest
    latest="$(/bin/ls -t "$HOME"/.zshrc.backup.* 2>/dev/null | head -1 || true)"
    if [[ -z "$latest" ]]; then
        ui_error "Nenhum backup ~/.zshrc.backup.* encontrado."
        return 1
    fi
    local n_diff="?"
    if [[ -f "$HOME/.zshrc" ]]; then
        n_diff="$(diff "$latest" "$HOME/.zshrc" 2>/dev/null | grep -c '^[<>]' || true)"
    fi
    ui_info "Backup mais recente: ${latest##*/} (${n_diff} linha(s) diferentes do atual)"
    if can_prompt; then
        if ! gum_confirm_tty "Restaurar este backup como ~/.zshrc?" --affirmative "Restaurar" --negative "Cancelar"; then
            ui_info "Restauração cancelada."
            return 0
        fi
    elif [[ "$ASSUME_YES" != "1" ]]; then
        ui_warn "Sem interação: confirme com --yes para restaurar."
        return 1
    fi
    if [[ -f "$HOME/.zshrc" ]]; then
        cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
    fi
    cp "$latest" "$HOME/.zshrc"
    if zsh -n "$HOME/.zshrc" 2>/dev/null; then
        ui_success "~/.zshrc restaurado de ${latest##*/} (o anterior virou backup)"
    else
        ui_warn "~/.zshrc restaurado, mas o zsh apontou erro de sintaxe — verifique o arquivo."
    fi
    return 0
}

# -----------------------------------------------------------------------------
# --remove a,b,c: desinstalação por item do catálogo, com confirmação
# -----------------------------------------------------------------------------
run_remove() {
    local ids id
    ids="$(echo "$REMOVE_ARG" | tr ',' ' ')"
    [[ -n "${ids// /}" ]] || { ui_error "Use: --remove item1,item2 (veja --list)"; return 1; }
    for id in $ids; do
        if ! item_exists "$id"; then
            ui_error "Item desconhecido: ${id} (use --list para ver os ids)"
            return 1
        fi
    done

    # monta o plano de remoção
    local plan="" actions="" pkgs entry kind name label
    for id in $ids; do
        label="$(item_label "$id")"
        case "$id" in
            claude-code)
                if [[ -x "$HOME/.local/bin/claude" ]]; then
                    plan="${plan}• ${label}: remover ~/.local/bin/claude (config ~/.claude preservada)"$'\n'
                    actions="${actions}rm-claude "
                else
                    plan="${plan}• ${label}: não instalado — nada a fazer"$'\n'
                fi
                continue
                ;;
            blackhole)
                if [[ -d "$BLACKHOLE_DIR" ]]; then
                    plan="${plan}• ${label}: remover ${BLACKHOLE_DIR} e desativar o shader na config do Ghostty"$'\n'
                    actions="${actions}rm-blackhole "
                else
                    plan="${plan}• ${label}: não instalado — nada a fazer"$'\n'
                fi
                continue
                ;;
        esac
        pkgs="$(item_pkgs "$id")" || true
        for entry in $pkgs; do
            kind="${entry%%:*}"
            name="${entry#*:}"
            name="${name##*/}"
            if [[ "$kind" == "f" ]]; then
                if brew list "$name" &>/dev/null; then
                    plan="${plan}• ${label}: brew uninstall ${name}"$'\n'
                    actions="${actions}f:${name} "
                else
                    plan="${plan}• ${label}: ${name} não instalado via brew — nada a fazer"$'\n'
                fi
            else
                if brew list --cask "$name" &>/dev/null; then
                    plan="${plan}• ${label}: brew uninstall --cask ${name} (APAGA o app de /Applications)"$'\n'
                    actions="${actions}c:${name} "
                else
                    plan="${plan}• ${label}: cask ${name} não veio do brew — se o app existir, remova manualmente de /Applications"$'\n'
                fi
            fi
        done
    done

    echo ""
    if [[ -n "$GUM" ]]; then
        "$GUM" style --border rounded --border-foreground "#e63946" --padding "0 2" --width "$(($(term_cols) - 4))" \
            "Plano de remoção:"$'\n'"$plan"
    else
        echo -e "${ERROR}Plano de remoção:${NC}"
        echo "$plan"
    fi
    if [[ -z "${actions// /}" ]]; then
        ui_info "Nada a remover."
        return 0
    fi
    if can_prompt; then
        if ! gum_confirm_tty "Executar a remoção acima?" --affirmative "Remover" --negative "Cancelar"; then
            ui_info "Remoção cancelada."
            return 0
        fi
    elif [[ "$ASSUME_YES" != "1" ]]; then
        ui_warn "Sem interação: confirme com --yes para remover."
        return 1
    fi

    local fail=0 act
    for act in $actions; do
        case "$act" in
            rm-claude)
                rm -f "$HOME/.local/bin/claude" && ui_success "claude removido de ~/.local/bin" || fail=1
                ;;
            rm-blackhole)
                rm -rf "$BLACKHOLE_DIR" && ui_success "ghostty-blackhole removido" || fail=1
                local gcfg="$HOME/.config/ghostty/config"
                if [[ -f "$gcfg" ]] && grep -q 'custom-shader' "$gcfg"; then
                    cp "$gcfg" "${gcfg}.backup.$(date +%Y%m%d%H%M%S)"
                    sed -i '' 's/^custom-shader/# custom-shader/' "$gcfg"
                    ui_info "Linhas custom-shader comentadas na config do Ghostty (backup criado)"
                fi
                ;;
            f:*)
                run_quiet_step "Removendo ${act#f:}" brew uninstall "${act#f:}" || fail=1
                ;;
            c:*)
                run_quiet_step "Removendo ${act#c:}" brew uninstall --cask "${act#c:}" || fail=1
                ;;
        esac
    done
    ui_info "Blocos correspondentes no ~/.zshrc são auto-guardados e ficam inertes."
    if [[ $fail -eq 1 ]]; then
        return 1
    fi
    ui_success "Remoção concluída."
    return 0
}

# -----------------------------------------------------------------------------
# --doctor: diagnóstico do ambiente, nada é instalado ou alterado
# -----------------------------------------------------------------------------
DOC_OK=0
DOC_WARN=0
DOC_FAIL=0
DOC_FORMULAE=""
DOC_CASKS=""

doc_ok()   { DOC_OK=$((DOC_OK + 1));     echo -e "${GUT}${SUCCESS}✓${NC} $*"; }
doc_warn() { DOC_WARN=$((DOC_WARN + 1)); echo -e "${GUT}${WARN}!${NC} $*"; }
doc_fail() { DOC_FAIL=$((DOC_FAIL + 1)); echo -e "${GUT}${ERROR}✗${NC} $*"; }
doc_head() { echo -e "${GUT}"; echo -e "${GUT}${ACCENT}◆${NC} ${BOLD}$1${NC}"; }

# Presença de um item usando o snapshot do brew + fallbacks (apps manuais, curl)
doctor_item_present() {
    local id="$1"
    case "$id" in
        claude-code) command -v claude &>/dev/null || [[ -x "$HOME/.local/bin/claude" ]]; return $? ;;
        blackhole)   [[ -d "$BLACKHOLE_DIR" ]]; return $? ;;
        ghostty)     [[ -d "/Applications/Ghostty.app" ]] && return 0 ;;
        iterm2)      [[ -d "/Applications/iTerm.app" ]] && return 0 ;;
        docker)      [[ -d "/Applications/Docker.app" ]] && return 0 ;;
        vscode)      [[ -d "/Applications/Visual Studio Code.app" ]] && return 0 ;;
        cursor)      [[ -d "/Applications/Cursor.app" ]] && return 0 ;;
        android-studio) [[ -d "/Applications/Android Studio.app" ]] && return 0 ;;
    esac
    local pkgs entry kind name
    pkgs="$(item_pkgs "$id")" || return 1
    [[ -n "$pkgs" ]] || return 1
    for entry in $pkgs; do
        kind="${entry%%:*}"
        name="${entry#*:}"
        name="${name##*/}"
        if [[ "$kind" == "f" ]]; then
            case " $DOC_FORMULAE " in
                *" $name "*) : ;;
                *) command -v "$name" &>/dev/null || return 1 ;;
            esac
        else
            case " $DOC_CASKS " in
                *" $name "*) : ;;
                *) return 1 ;;
            esac
        fi
    done
    return 0
}

run_doctor() {
    doc_head "Sistema"
    doc_ok "macOS $(sw_vers -productVersion 2>/dev/null || echo '?') ($(uname -m)) · Homebrew em ${BREW_PREFIX}"
    if xcode-select -p &>/dev/null; then
        doc_ok "Xcode Command Line Tools"
    else
        doc_fail "Xcode Command Line Tools ausente — rode: xcode-select --install"
    fi
    if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
        doc_ok "Xcode completo (builds iOS disponíveis)"
    else
        doc_warn "Xcode completo ausente — builds Flutter iOS exigem o Xcode da App Store"
    fi

    doc_head "Homebrew"
    if ! command -v brew &>/dev/null; then
        doc_fail "Homebrew não encontrado — rode o instalador sem --doctor para instalá-lo"
    else
        doc_ok "brew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
        DOC_FORMULAE="$(brew list --formula 2>/dev/null | tr '\n' ' ')"
        DOC_CASKS="$(brew list --cask 2>/dev/null | tr '\n' ' ')"
        ITEMS_TOTAL=1
        scan_outdated
        local n_out=0 orec oid ocat olabel odef opkgs odesc outdated_labels=""
        for orec in "${ITEM_DB[@]}"; do
            IFS='|' read -r oid ocat olabel odef opkgs odesc <<< "$orec"
            if item_outdated_summary "$oid" >/dev/null 2>&1; then
                n_out=$((n_out + 1))
                if [[ -n "$outdated_labels" ]]; then
                    outdated_labels="${outdated_labels}, ${olabel}"
                else
                    outdated_labels="$olabel"
                fi
            fi
        done
        if [[ "$n_out" -gt 0 ]]; then
            doc_warn "${n_out} item(ns) do catálogo com atualização (${outdated_labels}) — use --upgrade-only"
        else
            doc_ok "Itens do catálogo em dia no brew"
        fi
    fi

    doc_head "Catálogo por categoria"
    local rec cid clabel cdesc irec iid icat ilabel idef ipkgs idesc
    for rec in "${CATEGORY_DB[@]}"; do
        IFS='|' read -r cid clabel cdesc <<< "$rec"
        local total=0 present=0 missing=""
        for irec in "${ITEM_DB[@]}"; do
            IFS='|' read -r iid icat ilabel idef ipkgs idesc <<< "$irec"
            [[ "$icat" == "$cid" ]] || continue
            total=$((total + 1))
            if doctor_item_present "$iid"; then
                present=$((present + 1))
            else
                if [[ -n "$missing" ]]; then
                    missing="${missing}, ${ilabel}"
                else
                    missing="$ilabel"
                fi
            fi
        done
        if [[ $present -eq $total ]]; then
            doc_ok "${clabel} — ${present}/${total}"
        else
            doc_warn "${clabel} — ${present}/${total} (ausentes: ${missing})"
        fi
    done

    doc_head "Configurações"
    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -qF '# Fim da Configuração' "$HOME/.zshrc"; then
            doc_ok "~/.zshrc gerado pelo instalador"
        else
            doc_warn "~/.zshrc existe mas não foi gerado pelo instalador (regenerar migra adições externas)"
        fi
        if grep -qF '.local/bin' "$HOME/.zshrc"; then
            doc_ok "~/.local/bin no PATH (Claude Code, uv, pipx)"
        else
            doc_warn "~/.local/bin fora do .zshrc — binários nativos (claude) podem sumir do PATH"
        fi
    else
        doc_fail "~/.zshrc ausente"
    fi
    if command -v starship &>/dev/null; then
        if [[ -f "$HOME/.config/starship.toml" ]]; then
            doc_ok "starship.toml presente"
        else
            doc_warn "Starship instalado sem ~/.config/starship.toml (layout padrão em uso)"
        fi
    fi
    if [[ -d "/Applications/Ghostty.app" ]]; then
        if [[ -f "$HOME/.config/ghostty/config" ]]; then
            if grep -q 'custom-shader' "$HOME/.config/ghostty/config"; then
                doc_ok "Ghostty configurado (shader blackhole ativo)"
            else
                doc_ok "Ghostty configurado"
            fi
        else
            doc_warn "Ghostty sem ~/.config/ghostty/config (o instalador gera um)"
        fi
    fi
    local erec elabel eapp edir esfile
    for erec in "VS Code|Visual Studio Code|Code" "Cursor|Cursor|Cursor"; do
        IFS='|' read -r elabel eapp edir <<< "$erec"
        [[ -d "/Applications/${eapp}.app" ]] || continue
        esfile="$HOME/Library/Application Support/${edir}/User/settings.json"
        if [[ -f "$esfile" ]] && grep -q 'terminal.integrated.fontFamily' "$esfile"; then
            doc_ok "${elabel}: fonte do terminal configurada"
        else
            doc_warn "${elabel}: terminal.integrated.fontFamily ausente — ícones quebrados no terminal integrado"
        fi
    done

    echo -e "${GUT}"
    local verdict="Diagnóstico: ${DOC_OK} ✓ · ${DOC_WARN} aviso(s) · ${DOC_FAIL} problema(s)"
    if [[ -n "$GUM" ]]; then
        local color="#00e5cc"
        if [[ $DOC_FAIL -gt 0 ]]; then color="#e63946"; elif [[ $DOC_WARN -gt 0 ]]; then color="#f5b000"; fi
        "$GUM" style --border rounded --border-foreground "$color" --padding "0 2" "$verdict"
    else
        echo "$verdict"
    fi
    if [[ $DOC_FAIL -gt 0 ]]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# --upgrade-only: só o engine de atualizações, sem instalar nada novo
# -----------------------------------------------------------------------------
select_all_items() {
    SELECTED_ITEMS=""
    local rec id cat label def pkgs desc
    for rec in "${ITEM_DB[@]}"; do
        IFS='|' read -r id cat label def pkgs desc <<< "$rec"
        select_item "$id"
    done
    ITEMS_TOTAL="$(count_words "$SELECTED_ITEMS")"
    return 0
}

run_upgrade_only() {
    if ! command -v brew &>/dev/null && [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
        ui_error "Homebrew não encontrado — nada a atualizar."
        return 1
    fi
    ensure_brew_in_path
    select_all_items
    if ! can_prompt; then
        UPGRADE_FLAG=1   # pedir --upgrade-only headless já é consentimento
    fi
    scan_outdated
    offer_upgrades
    if [[ -z "$PENDING_UPDATES" ]]; then
        ui_success "Tudo atualizado — nenhum item do catálogo tem versão nova no brew."
        return 0
    fi
    if [[ "$DO_UPGRADE" != "1" ]]; then
        ui_info "Nenhuma atualização aplicada."
        return 0
    fi
    local id label start fail=0
    for id in $PENDING_UPDATES; do
        label="$(item_label "$id")"
        start=$SECONDS
        if upgrade_item_pkgs "$id"; then
            ui_up "$label" $((SECONDS - start))
        else
            ui_error "Falhou ao atualizar: ${label}"
            fail=1
        fi
    done
    if [[ $fail -eq 1 ]]; then
        return 1
    fi
    ui_success "Atualizações concluídas."
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

    if [[ "$SELF_UPDATE" == "1" ]]; then
        run_self_update
        exit $?
    fi
    if [[ "$DOCTOR" == "1" ]]; then
        run_doctor
        exit $?
    fi
    if [[ "$UPGRADE_ONLY" == "1" ]]; then
        run_upgrade_only
        exit $?
    fi
    if [[ "$RESTORE_ZSHRC" == "1" ]]; then
        run_restore_zshrc
        exit $?
    fi
    if [[ -n "$REMOVE_ARG" ]]; then
        ensure_brew_in_path
        run_remove
        exit $?
    fi

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

    save_selection_state
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
        configure_iterm2_font
        configure_editor_terminal_font
    fi

    print_final_report $((SECONDS - main_start))
}

parse_args "$@"
main
