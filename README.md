# mac-env-setup

Instalador de ambiente de desenvolvimento para macOS em um único script Bash — **por categorias, com seletor interativo**, idempotente e pronto para rodar direto via `curl`. UI "Event Horizon": gradiente âmbar sobre preto, progresso em tempo real.

## Instalação

### Remota (recomendada)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash
```

Em terminal interativo, abre o **seletor de perfis**. Sem TTY (CI etc.), usa o perfil `terminal`.

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

- **terminal** — Ghostty *(padrão)* ou iTerm2, zsh essentials (completions + histórico nativos, zsh-autosuggestions, zsh-syntax-highlighting — sem frameworks), prompt **Starship** *(padrão)* ou Powerlevel10k, JetBrainsMono Nerd Font *(padrão)* e/ou MesloLGS Nerd Font, eza, fzf, zoxide, bat
- **dev** — git (Homebrew), GitHub CLI, jq, wget, Docker Desktop, Node.js + pnpm + bun, pyenv + pyenv-virtualenv
- **cloud** — AWS CLI, Supabase CLI
- **android** — OpenJDK 21, android-platform-tools (adb); Android Studio opcional
- **ios** — CocoaPods (necessário para builds Flutter iOS; o Xcode completo vem só da App Store)
- **apps** — Visual Studio Code, Cursor

kubectl vem embutido no Docker Desktop e por isso não está no catálogo.

Veja tudo com `bash mac_env_install.sh --list`.

## Opções

| Flag | Efeito |
|---|---|
| `--profile <p>` | `completo` \| `terminal` \| `dev` \| `mobile`, sem interação |
| `--categories a,b,c` | categorias diretas, sem interação |
| `--all` | tudo (= `--profile completo`) |
| `--upgrade` | atualiza itens já instalados com versão nova no brew (sem a flag, o instalador pergunta quando interativo e mantém versões quando headless) |
| `--yes`, `-y` | não pergunta nada; perfil padrão `terminal` |
| `--dry-run` | mostra o plano e sai sem tocar no sistema |
| `--list` | lista categorias/itens e sai |
| `--verbose`, `-v` | mostra a saída completa de cada passo |

Variáveis de ambiente: `MACENV_USE_GUM` (`auto`/`1`/`0`), `MACENV_GUM_VERSION` (padrão `0.17.0`), `NO_COLOR`.

## Configurações geradas (só quando a categoria `terminal` é selecionada)

- **`~/.zshrc`** — montado por blocos conforme a seleção (pyenv, JAVA_HOME, fzf, zoxide, eza, bat, plugins, prompt). Backup do anterior em `~/.zshrc.backup.<timestamp>` antes de **sobrescrever**.
- **`~/.config/starship.toml`** — preset oficial do Starship: `tokyo-night` (padrão) ou `catppuccin-powerline`, escolhido no seletor (fallback Event Horizon embutido quando sem rede); backup antes de sobrescrever. Escolher Powerlevel10k mantém seu `~/.p10k.zsh` intacto e instala a MesloLGS (fonte recomendada do p10k).
- **`~/.config/ghostty/config`** — fonte Nerd Font, cursor âmbar; **só é criado se não existir** (config existente é preservada).
- **VS Code / Cursor** — `terminal.integrated.fontFamily` recebe a Nerd Font no `settings.json` de cada editor instalado (valor existente é preservado; backup antes de escrever).

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
