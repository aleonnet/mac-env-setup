# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [3.7.2] - 2026-07-23

### Fixed
- Config gerada do Ghostty: cursor muda de `#f5b000` para `#f5a000` — o âmbar exato da assinatura é o canal de sinal do token mode do shader blackhole e não pode ser usado como cor estática do cursor. Também troca `background-blur-radius` pelo nome atual da opção, `background-blur`.

## [3.7.1] - 2026-07-23

### Changed
- A rotação do blackhole abre o instalador (logo após a revelação do anel no banner) e sai do finale, que mantém só o fechamento da calha + resumo.

## [3.7.0] - 2026-07-23

### Changed — UI levada ao limite do bash single-file
- **Calha vertical conectada** (estilo clack) do início ao fim: mensagens, itens, estágios (`├──`) e fechamento (`╰──`) compartilham a mesma espinha `│`; no fluxo de seleção cada pergunta (`◇`) permanece visível e vira resposta (`◆ Perfil: Dev`).
- **Spinner de item que se transforma no resultado**: cada item roda sob um spinner braille âmbar na própria linha, que é substituída in-place por `✓/◇/↑/✗` com cronômetro; saída interna (avisos, tail de log em falha) aparece indentada sob o item.
- **Barra orbit viva**: pinada como última linha e redesenhada após cada item (não mais só por estágio).
- **Finale "event horizon"**: o anel do banner gira ao final — a luz da rampa blackbody percorre o disco de acreção em ~10 frames antes do resumo.
- Mensagens `ui_*` não passam mais pelo `gum log`; gum fica só para seleção/confirm/cards. Tudo degrada como antes (non-TTY/`NO_COLOR`/`--verbose` mantêm o fluxo linear).

## [3.6.3] - 2026-07-23

### Changed
- Config nova do Ghostty inclui fundo translúcido com blur estilo iTerm2 (`background-opacity = 0.85`, `background-blur-radius = 20`).

## [3.6.2] - 2026-07-23

### Fixed
- **Busca no histórico por prefixo com ↑/↓ restaurada**: o Oh My Zsh amarrava as setas aos widgets nativos `up/down-line-or-beginning-search` e isso se perdeu na troca pelos zsh essentials (3.3.0). O bloco core do `.zshrc` agora faz os `bindkey` (modos normal e application).

## [3.6.1] - 2026-07-23

### Fixed
- **Falso positivo de atualização em apps que se auto-atualizam** (Docker Desktop, VS Code, Cursor, Android Studio): o receipt do brew fica congelado na versão do install original enquanto o app se atualiza sozinho (ex.: receipt 4.29.0 vs app real 4.81.0), gerando ofertas de upgrade erradas e no-ops silenciosos. Novo marcador `c!:` no catálogo exclui esses casks do engine de upgrades — eles cuidam das próprias atualizações.

## [3.6.0] - 2026-07-23

### Added
- **Claude Code** (categoria dev): instalador nativo da Anthropic (`claude.ai/install.sh` → `~/.local/bin/claude`, PATH já coberto pelo `.zshrc` gerado). Atualizações ficam com o auto-update do próprio Claude Code.
- **Ghostty Blackhole** (categoria terminal): clona [s0xDk/ghostty-blackhole](https://github.com/s0xDk/ghostty-blackhole) em `~/Development/ghostty-blackhole` (`git pull` quando já existe) e ativa o `custom-shader` na config do Ghostty — escrito em configs novas, **anexado com backup** em configs existentes sem shader, intocado quando já há um. Pulado com aviso se Ghostty não estiver na seleção/máquina.

## [3.5.1] - 2026-07-22

### Fixed
- `.zshrc` gerado preserva mais dois PATHs que a sobrescrita perdia: **`~/.local/bin`** (Claude Code, uv, pipx — sempre) e **Flutter SDK** (bloco auto-guardado que procura o SDK em caminhos comuns, incluindo `~/Development/FlutterProjects/flutter`). Antes, regenerar o `.zshrc` quebrava `claude` e `flutter` no PATH.

## [3.5.0] - 2026-07-22

### Added
- **Fonte do terminal no VS Code e Cursor**: o estágio Configurações agora define `terminal.integrated.fontFamily` (Nerd Font instalada) no `settings.json` dos editores presentes — cria se faltar, preserva valor existente, backup antes de escrever e não toca em JSON não-parseável.
- **CocoaPods de volta** (categoria `ios` restaurada): builds Flutter iOS dependem dele — a remoção na 3.2.0 partiu de premissa errada (não vem com o Xcode). Perfis `completo` e `mobile` voltam a incluir ios.

## [3.4.0] - 2026-07-22

### Added
- Seletor de **estilo do prompt Starship**: Tokyo Night (novo padrão) ou Catppuccin Powerline, via `starship preset`.

## [3.3.2] - 2026-07-22

### Changed
- Prompt Starship agora usa o **preset oficial `catppuccin-powerline`** (o mesmo do guia Ghostty/Starship/Catppuccin), gerado via `starship preset` na instalação. O config Event Horizon embutido vira fallback para instalação sem rede.

## [3.3.1] - 2026-07-22

### Fixed
- `starship.toml` agora entrega o **powerline Event Horizon** prometido: diretório em segmento âmbar com setas de transição, git em segmento escuro, lead-in `░▒▓` (assinatura do instalador) e `❯` em linha própria. Módulos AWS/GCloud/Azure desligados (o "on ☁️ (us-east-1)" não aparece mais). O config anterior caía no layout padrão do Starship.

## [3.3.0] - 2026-07-22

### Changed
- **Oh My Zsh substituído por "zsh essentials"**: completions e histórico agora vêm de configuração nativa do zsh no `.zshrc` gerado (`compinit`, `setopt` de histórico, menu de completion); os plugins zsh-autosuggestions e zsh-syntax-highlighting continuam via Homebrew. O instalador não baixa mais o framework Oh My Zsh — shell mais leve e sem dependência de repositório externo. Powerlevel10k continua funcionando standalone quando escolhido.

## [3.2.0] - 2026-07-22

### Removed
- **ngrok**, **Redis**, **kubectl** e **CocoaPods** saíram do catálogo (eram de necessidades pontuais). kubectl já vem embutido no Docker Desktop; para iOS, o caminho moderno é Swift Package Manager no Xcode (App Store). A categoria **ios** foi removida (ficou vazia); perfil `mobile` agora é terminal+dev+android e `cloud` ficou com AWS CLI + Supabase CLI.

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
