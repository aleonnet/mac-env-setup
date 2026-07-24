# ROADMAP — mac-env-setup

> Autocontido de propósito: junto com `CLAUDE.md` (convenções técnicas), este arquivo permite retomar o projeto em uma sessão nova sem contexto anterior.

## Estado atual (v3.7.2 — 2026-07-23)

Instalador de ambiente macOS em **um único script Bash 3.2** (`mac_env_install.sh`, ~2.000 linhas), executado remotamente:

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash
```

O que já existe e funciona (validado em produção na máquina do Alessandro):

- **Seletor interativo** (gum via `/dev/tty`, pipe-safe): perfis Completo/Terminal/Dev/Mobile/Personalizado; escolhas de terminal (Ghostty padrão/iTerm2), prompt (Starship padrão/p10k) e preset do Starship (tokyo-night padrão/catppuccin-powerline). Flags headless: `--profile`, `--categories`, `--all`, `--yes`, `--upgrade`, `--dry-run`, `--list`, `--verbose`.
- **6 categorias, ~26 itens** idempotentes (contrato 0/100/1): terminal (Ghostty + shader blackhole, zsh essentials sem OMZ, fontes Nerd, eza/fzf/zoxide/bat), dev (git, gh, jq, wget, Docker, Node+pnpm+bun, pyenv+virtualenv, **Claude Code nativo**), cloud (awscli, supabase), android (OpenJDK 21 LTS deliberado — tooling não suporta 25/26), ios (CocoaPods p/ Flutter), apps (VS Code, Cursor).
- **Engine de upgrades**: um scan de `brew outdated` pós-Base, card de oferta com versões, `↑ atualizado` no placar; casks auto-atualizáveis (marcador `c!:`) excluídos — receipt do brew fica defasado do app real.
- **Configs geradas** (backup timestampado sempre): `.zshrc` modular por seleção (preserva `~/.local/bin`, Flutter SDK, bun via curl; setas ↑/↓ com busca por prefixo), `starship.toml` via preset oficial, config do Ghostty (cursor `#f5a000` — o `#f5b000` exato é canal do token mode do shader; `background-blur`; shader anexado com backup em config existente sem shader), `terminal.integrated.fontFamily` no settings.json de VS Code/Cursor (preserva valor existente, ignora JSONC).
- **UI "Event Horizon"** no limite do bash single-file: rampa blackbody `#7a3b00→#f5b000→#fff3c4`, banner com anel do blackhole girando na abertura, calha vertical conectada estilo clack (perguntas viram respostas `◆`), spinner braille por item transformado in-place no resultado, barra orbit viva redesenhada a cada item, degradação completa (non-TTY/NO_COLOR/--verbose).

Como testar (nunca instalar de verdade durante o desenvolvimento):

```bash
bash -n mac_env_install.sh && shellcheck mac_env_install.sh
/bin/bash mac_env_install.sh --dry-run --profile completo      # bash 3.2!
cat mac_env_install.sh | /bin/bash -s -- --dry-run --profile dev
# caminhos de TTY (spinner/barra/animações): rodar sob pty
python3 -c "import pty; pty.spawn(['/bin/bash','mac_env_install.sh','--dry-run','--profile','terminal'])"
# geração de configs: fake HOME (source do script menos as 2 últimas linhas)
```

## Evoluções sugeridas

### P1 — próximo passo natural

1. ~~**Preservar linhas desconhecidas do `.zshrc`**~~ — **feito na v3.8.0** (`zshrc_migrate_tail`: tudo após o rodapé do arquivo anterior migra para a seção "Suas adições", com dedupe e round-trip estável).
2. ~~**`--doctor`**~~ — **feito na v3.9.0** (diagnóstico read-only: sistema, brew, catálogo por categoria, configs; exit 1 com problemas).
3. ~~**`--upgrade-only`**~~ — **feito na v3.9.0** (só o engine de upgrades; headless aplica, interativo confirma).
4. ~~**CI no GitHub Actions**~~ — **feito na v3.9.0** (`.github/workflows/ci.yml`: bash 3.2, shellcheck warning-clean bloqueante, dry-runs, pty, configs em HOME falso; badge no README).

**P1 concluído por completo.** Próxima fronteira: P2.

### P2 — qualidade de vida

5. ~~**Seleção por item no Personalizado**~~ — **feito na v3.10.0** (multi-select com descrições, defaults pré-marcados; terminal/prompt derivados da seleção).
6. ~~**Perfil persistente**~~ — **feito na v3.10.0** (`~/.config/macenv/state`, "Repetir última instalação" no seletor, `--profile last` headless, filtro de itens obsoletos).
7. ~~**Log da execução**~~ — **feito na v3.10.0** (`~/.config/macenv/last-run.log` com tempos por item).
8. ~~**Config automática do iTerm2**~~ — **feito na v3.10.0** (export/PlistBuddy/import com app fechado; Dynamic Profile "MacEnv" como fallback).

**P2 concluído por completo.** Próxima fronteira: P3.

### P3 — apostas maiores

9. **Companion TUI em Bubble Tea + huh v2** — **aprovado, próximo passo (v4.0.0)**: binário Go universal baixado com checksum como o gum, só para a fase de seleção (busca fuzzy, painel de descrição, tema Event Horizon em Lipgloss, blackhole animado); pipeline de release no GitHub Actions; bash continua o motor e o fluxo gum atual vira fallback.
10. ~~**`--self-update`**~~ — **feito na v3.11.0** (SHA-256 + validação de sintaxe + backup `.bak`; constante `MACENV_VERSION`).
11. ~~**Xcode completo via `mas`**~~ — **feito na v3.11.0** (item opcional na categoria ios; falha graciosa sem login).
12. ~~**Rollback**~~ — **feito na v3.11.0** (`--restore-zshrc` e `--remove a,b,c` com plano explícito e confirmação).

## Decisões que não devem regredir (ver CLAUDE.md para o como)

- Arquivo único + Bash 3.2 do sistema + pipe-safety — é o que garante o `curl | bash` universal; qualquer dependência nova segue o padrão gum (download temp + checksum + fallback).
- Nunca `--greedy` no brew outdated; casks `c!:` fora de ofertas de upgrade.
- `~/.p10k.zsh` e config existente do Ghostty são invioláveis (no máximo append com backup).
- OpenJDK fixo em 21 LTS enquanto o tooling Android não suportar mais novo.
- UI degrada sempre: gum → ANSI → NO_COLOR → non-TTY linear.
