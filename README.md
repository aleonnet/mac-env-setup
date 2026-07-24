# mac-env-setup

![CI](https://github.com/aleonnet/mac-env-setup/actions/workflows/ci.yml/badge.svg)

Instalador de ambiente de desenvolvimento para macOS em um único script Bash — **por categorias, com seletor interativo**, idempotente e pronto para rodar direto via `curl`. UI "Event Horizon": gradiente âmbar sobre preto, progresso em tempo real.

## Instalação

### Remota (recomendada)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash
```

Em terminal interativo, abre o **seletor de perfis** (gum) — com "Repetir última instalação" quando houver seleção salva e ajuste **item a item** no modo Personalizado. Com `--tui` (ou `MACENV_USE_TUI=1`), usa o seletor alternativo em tela cheia (`macenv-tui`, Bubble Tea — busca com `/`, perfis nas teclas 1-4, painel de descrição; baixado em runtime com SHA-256, nunca instalado). Sem TTY (CI etc.), usa o perfil `terminal`. Cada execução salva a seleção em `~/.config/macenv/state` e o relatório com tempos em `~/.config/macenv/last-run.log`.

### Headless / sem interação

```bash
# perfil pronto
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- --profile dev

# categorias específicas
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- --categories terminal,cloud

# só ver o que seria instalado
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- --dry-run --profile completo
```

## Perfis

| Perfil | Categorias |
|---|---|
| `completo` | tudo |
| `terminal` | Terminal & Shell |
| `dev` | Terminal & Shell + Dev Essentials + Apps |
| `mobile` | Terminal & Shell + Dev Essentials + Android + iOS |

## Categorias e itens

- **terminal** — Ghostty *(padrão)* ou iTerm2, shader **Blackhole** no fundo do Ghostty ([s0xDk/ghostty-blackhole](https://github.com/s0xDk/ghostty-blackhole)), zsh essentials (completions + histórico nativos, zsh-autosuggestions, zsh-syntax-highlighting — sem frameworks), prompt **Starship** *(padrão)* ou Powerlevel10k, JetBrainsMono Nerd Font *(padrão)* e/ou MesloLGS Nerd Font, eza, fzf, zoxide, bat
- **dev** — git (Homebrew), GitHub CLI, jq, wget, Docker Desktop, Node.js + pnpm + bun, pyenv + pyenv-virtualenv, **Claude Code** (instalador nativo da Anthropic)
- **cloud** — AWS CLI, Supabase CLI
- **android** — OpenJDK 21 LTS (deliberado: é o JDK que Android Studio/Gradle suportam — 25/26 quebram builds Flutter), android-platform-tools (adb); Android Studio opcional
- **ios** — CocoaPods (necessário para builds Flutter iOS); Xcode completo opcional via `mas` (~12 GB, exige login na App Store)
- **apps** — Visual Studio Code, Cursor

kubectl vem embutido no Docker Desktop e por isso não está no catálogo.

Veja tudo com `bash mac_env_install.sh --list`.

## Opções

| Flag | Efeito |
|---|---|
| `--profile <p>` | `completo` \| `terminal` \| `dev` \| `mobile` \| `last` (repete a última instalação salva), sem interação |
| `--categories a,b,c` | categorias diretas, sem interação |
| `--all` | tudo (= `--profile completo`) |
| `--upgrade` | atualiza itens já instalados com versão nova no brew (sem a flag, o instalador pergunta quando interativo e mantém versões quando headless) |
| `--upgrade-only` | só atualiza o que está instalado e sai — não instala nada novo (headless aplica direto; interativo confirma) |
| `--doctor` | diagnóstico do ambiente: sistema, Homebrew, presença dos itens por categoria, configurações — nada é instalado ou alterado (exit 1 se houver problemas) |
| `--self-update` | atualiza o script local para a versão do `main` (SHA-256 + validação de sintaxe, backup `.bak`) |
| `--restore-zshrc` | restaura o backup mais recente do `~/.zshrc` (headless exige `--yes`) |
| `--remove a,b,c` | remove itens do catálogo com plano explícito e confirmação (avisa quando apaga apps inteiros) |
| `--tui` | seletor alternativo em tela cheia (busca, hotkeys de perfil, painel de descrição) |
| `--yes`, `-y` | não pergunta nada; perfil padrão `terminal` |
| `--dry-run` | mostra o plano e sai sem tocar no sistema |
| `--list` | lista categorias/itens e sai |
| `--verbose`, `-v` | mostra a saída completa de cada passo |

Variáveis de ambiente: `MACENV_USE_GUM` (`auto`/`1`/`0`), `MACENV_GUM_VERSION` (padrão `0.17.0`), `MACENV_USE_TUI` (`1` ativa o seletor Bubble Tea; padrão desativado), `NO_COLOR`.

## Configurações geradas (só quando a categoria `terminal` é selecionada)

- **`~/.zshrc`** — montado por blocos conforme a seleção (pyenv, JAVA_HOME, fzf, zoxide, eza, bat, plugins, prompt). Backup do anterior em `~/.zshrc.backup.<timestamp>` antes de sobrescrever — e tudo que outras ferramentas tiverem anexado ao final do arquivo anterior é **migrado automaticamente** para a seção "Suas adições" do novo (com dedupe).
- **`~/.config/starship.toml`** — preset oficial do Starship: `tokyo-night` (padrão) ou `catppuccin-powerline`, escolhido no seletor (fallback Event Horizon embutido quando sem rede); backup antes de sobrescrever. Escolher Powerlevel10k mantém seu `~/.p10k.zsh` intacto e instala a MesloLGS (fonte recomendada do p10k).
- **`~/.config/ghostty/config`** — fonte Nerd Font, cursor âmbar e shader blackhole (quando selecionado); config nova é criada completa, config existente é preservada — no máximo o bloco `custom-shader` é **anexado** (com backup) se ainda não houver um.
- **VS Code / Cursor** — `terminal.integrated.fontFamily` recebe a Nerd Font no `settings.json` de cada editor instalado (valor existente é preservado; backup antes de escrever).
- **iTerm2** — fonte Nerd aplicada ao perfil padrão (iTerm2 fechado) ou via Dynamic Profile "MacEnv" (iTerm2 aberto); fonte Nerd já configurada é preservada.

## Comportamentos importantes

- **Idempotente**: cada item é verificado antes de instalar; re-execuções reportam "já instalado". Falha de um item não aborta os demais (resumo final com falhas e exit 1).
- **Atualizações**: itens já instalados com versão nova no Homebrew são detectados e ofertados num card antes da instalação (interativo pergunta; `--upgrade` aplica direto).
- **Xcode CLT**: se ausente, abre o instalador gráfico e **encerra** — re-execute o script depois.
- **Fonte MesloLGS**: quando selecionada, sempre atualizada para v3.x; arquivos v2.3.3 legados são removidos.
- Saída silenciosa por padrão (últimas 80 linhas do log em caso de falha); `--verbose` mostra tudo.
- UI com [gum](https://github.com/charmbracelet/gum) baixado em temp com verificação SHA256 (nunca instalado permanentemente), com fallback ANSI e modo headless.

## Requisitos

- macOS (Apple Silicon ou Intel)
- `curl` ou `wget`

## Pós-instalação

O relatório final lista os passos específicos da sua seleção (abrir Docker.app na primeira vez, `supabase login`, etc.). Recarregue o shell com `exec zsh`.
