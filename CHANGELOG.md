# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [3.1.0] - 2026-07-22

### Added
- **Oferta de atualizações**: um scan único de `brew outdated` após o estágio Base; itens já instalados com versão nova aparecem num card "Atualizações disponíveis" (com versões atual → nova) e o instalador pergunta se deve atualizar. Headless: flag `--upgrade` aplica, sem ela as versões são mantidas e o relatório final lembra. Novo estado `↑ atualizado` no placar. Casks que se auto-atualizam (Docker, VS Code) não usam `--greedy`.
- **Descrições por item**: cada item do catálogo agora explica para que serve (`--list` e registro `ITEM_DB`).
- **Mais animação**: shimmer no wordmark do banner e no título final (a luz percorre o texto), revelação esquerda→direita (ignição) nos headers de estágio e nas réguas.

### Fixed
- Mensagem duplicada "— já instalado" ao preservar `~/.config/ghostty/config` existente.

## [3.0.1] - 2026-07-22

### Fixed
- `.zshrc` gerado agora preserva o **bun instalado via curl** (`~/.bun`): bloco auto-guardado com `BUN_INSTALL`, PATH e completions. Antes, regenerar o `.zshrc` derrubava o bun do PATH nessas instalações.

## [3.0.0] - 2026-07-22

Instalador por categorias com seletor interativo e direção de arte "Event Horizon".

### Added
- **Seletor interativo** (gum via `/dev/tty`, pipe-safe): perfis Completo / Terminal bonito / Dev / Mobile / Personalizado, escolha de terminal (Ghostty/iTerm2) e de prompt (Starship/Powerlevel10k).
- **6 categorias**: terminal, dev (git, gh, jq, wget, Docker Desktop, Node+pnpm+bun, pyenv+virtualenv), cloud (awscli, kubectl, supabase, ngrok, redis), android (OpenJDK 21, platform-tools, Android Studio), ios (CocoaPods), apps (VS Code, Cursor).
- Flags headless: `--profile`, `--categories`, `--all`, `--yes`, `--dry-run`, `--list`, `--help`.
- **Direção de arte Event Horizon**: gradiente truecolor na rampa blackbody (`#7a3b00→#f5b000→#fff3c4`), banner do disco de acreção com revelação animada, réguas-gradiente por estágio, barra de progresso "orbit", manifesto pré-instalação em árvore, relatório final com cronômetro e próximos passos condicionais.
- Novos itens de terminal: **Ghostty** (padrão), **Starship** (prompt padrão, `~/.config/starship.toml` com paleta Event Horizon), JetBrainsMono Nerd Font (padrão), fzf, zoxide, bat, geração de `~/.config/ghostty/config` (preserva config existente).
- `.zshrc` modular: blocos gerados conforme a seleção (pyenv+virtualenv, JAVA_HOME/OpenJDK 21, Android SDK, fzf, zoxide, eza, bat, prompt).

### Changed
- iTerm2, Powerlevel10k e MesloLGS viram **opcionais** no seletor (Ghostty/Starship/JetBrainsMono são os novos padrões). Escolher p10k mantém `~/.p10k.zsh` e traz a MesloLGS junto.
- Estágios de progresso dinâmicos conforme a seleção; falha de um item não aborta os demais (resumo final + exit 1).
- Paleta do instalador migrou do coral `#ff4d4d` para o âmbar `#f5b000` (assinatura ghostty-blackhole).

## [2.0.0] - 2026-07-22

Primeira publicação no GitHub (`aleonnet/mac-env-setup`), com suporte a execução remota via `curl | bash`.

### Added
- Instalação do **eza** com aliases `ls`/`ll`/`la`/`lt` (ls com ícones) no `.zshrc` gerado.
- UI opcional com **gum** (spinner, etapas), baixado em temp com verificação SHA256.
- MesloLGS Nerd Font **v3.x**, com remoção automática da v2.3.3 legada.

### Changed
- Script renomeado de `mac_env_install_v2.sh` para `mac_env_install.sh`.

## [1.0.0]

Versão original: zsh + iTerm2 + Oh My Zsh + Powerlevel10k + plugins + pyenv, sem eza e sem UI com gum.
