#!/usr/bin/env bash
# =============================================================================
# embed.sh — copia os templates/ para dentro do mac_env_install.sh.
#
# O instalador é autocontido (curl | bash), mas a fonte de verdade dos
# payloads ESTÁTICOS vive em templates/, onde tem lint e diff próprios:
#   templates/starship_fallback.toml  → heredoc MACENV_STARSHIP_FALLBACK
#   templates/editor_font_patch.py    → heredoc PYEOF
# Os delimitadores do próprio heredoc são os marcadores — nada de comentário
# extra vazando para o arquivo gerado. Payload dinâmico (blocos do .zshrc,
# interpolados em runtime) fica no script, onde a lógica que o escolhe mora.
#
#   ./tools/embed.sh           embute
#   ./tools/embed.sh --check   só confere (exit 3 se divergir)
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
ALVO="$RAIZ/mac_env_install.sh"

BLOCOS="MACENV_STARSHIP_FALLBACK|templates/starship_fallback.toml PYEOF|templates/editor_font_patch.py"

[ -f "$ALVO" ] || { echo "[ERRO] instalador ausente: $ALVO" >&2; exit 4; }

tmp_a="$(mktemp)"; tmp_b="$(mktemp)"
trap 'rm -f "$tmp_a" "$tmp_b"' EXIT

falhou=0
for bloco in $BLOCOS; do
    delim="${bloco%%|*}"; rel="${bloco#*|}"
    origem="$RAIZ/$rel"
    [ -f "$origem" ] || { echo "[ERRO] origem ausente: $origem" >&2; exit 4; }
    grep -q "<<'$delim'" "$ALVO" || { echo "[ERRO] sem heredoc <<'$delim' no instalador" >&2; exit 3; }
    grep -qx "$delim" "$ALVO"    || { echo "[ERRO] sem fechamento $delim no instalador" >&2; exit 3; }

    awk -v d="$delim" '
        index($0, "<<\x27" d "\x27") { dentro=1; next }
        dentro && $0==d { dentro=0; next }
        dentro' "$ALVO" > "$tmp_a"

    if [ "${1:-}" = "--check" ]; then
        if diff -q "$tmp_a" "$origem" >/dev/null 2>&1; then
            echo "[OK] $delim idêntico a $rel"
        else
            echo "[ERRO] $delim DIVERGE de $rel — rode ./tools/embed.sh" >&2
            diff "$origem" "$tmp_a" | head -8 >&2
            falhou=1
        fi
        continue
    fi

    awk -v d="$delim" -v src="$origem" '
        index($0, "<<\x27" d "\x27") {
            print
            while ((getline l < src) > 0) print l
            close(src); pulando=1; next
        }
        pulando && $0==d { pulando=0; print; next }
        !pulando { print }
    ' "$ALVO" > "$tmp_b"
    /bin/bash -n "$tmp_b" || { echo "[ERRO] resultado não passa em bash -n — nada escrito" >&2; exit 3; }
    cat "$tmp_b" > "$ALVO"
    echo "[OK] $delim embutido ($(wc -l < "$origem" | tr -d ' ') linhas de $rel)"
done
[ "$falhou" = "0" ] || exit 3
