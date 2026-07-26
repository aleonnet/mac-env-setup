# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [4.3.2] - 2026-07-26

### Fixed
- **O perfil "MacEnv" do iTerm2 agora herda o seu perfil Default** (`"Dynamic Profile Parent Name": "Default"`, chave [documentada pelo iTerm2](https://iterm2.com/documentation-dynamic-profiles.html)). Esse perfil é o caminho usado quando a fonte não pode ir no plist — tipicamente **quando o instalador é rodado de dentro do próprio iTerm2**, que é o caso mais comum de todos: o iTerm2 mantém as preferências em memória e as sobrescreve ao sair, então escrever no plist com ele aberto se perderia. Antes o MacEnv declarava só a fonte, e as chaves não declaradas caíam nos padrões do iTerm2 — escolher o perfil trocava as cores do usuário, o que tornava o fallback inútil na prática. Agora ele herda tudo e troca apenas a fonte. Perfis dinâmicos são hot-loaded, então aparece sem reiniciar o app.
- Passo do relatório final reescrito: dizia "iTerm2 estava aberto" mesmo quando o motivo era outro (plist indisponível, perfil 0 não sendo o padrão), e não dizia como tornar permanente. Agora aponta Profiles → MacEnv **ou** fechar o iTerm2 e re-executar para gravar no perfil Default.

## [4.3.1] - 2026-07-26

### Changed
- **Fonte Nerd no iTerm2 agora é aplicada por presença do app**, não por seleção. O `.zshrc` gerado entrega prompt powerline e `eza --icons` a todo terminal que não seja o Terminal da Apple, então um iTerm2 instalado precisava da fonte para não virar tofu — mas `configure_iterm2_font()` só agia se `iterm2` estivesse na seleção, e ele é default `0` no catálogo. VS Code e Cursor já eram tratados por presença; o iTerm2 era a exceção inconsistente. Fonte Nerd já configurada continua sendo preservada, então a mudança só toca perfil quebrado. Continua restrito ao estágio Configurações, ou seja, só quando a categoria `terminal` é selecionada.

### Fixed
- **Nome de fonte inválido no ramo Powerlevel10k**: `configure_iterm2_font()` escrevia `MesloLGSNerdFontMono-Regular`, que é o nome do *arquivo* — o plist do iTerm2 espera o nome **PostScript**, `MesloLGSNFM-Regular`. Quem escolhia Powerlevel10k (que auto-seleciona a Meslo) recebia uma fonte inexistente, o iTerm2 caía no fallback do sistema e os glifos viravam tofu. O ramo do JetBrains (`JetBrainsMonoNFM-Regular`) já estava correto.
- **Perfil errado do iTerm2**: a função escrevia em `New Bookmarks:0`, assumindo que o perfil de índice 0 é o padrão. Agora compara o `Guid` dele com o `Default Bookmark Guid` e, se divergirem, não mexe no plist — cai no perfil dinâmico, que não altera a configuração de ninguém.
- **`Use Non-ASCII Font`**: com esse toggle ligado, os ícones vêm da fonte não-ASCII, então definir só a `Normal Font` deixava o tofu de pé. Quando ligado, a `Non Ascii Font` recebe a mesma fonte Nerd (o toggle é preservado).

### Added
- Passo no relatório final quando o iTerm2 estava **aberto** durante a instalação: nesse caminho a função cria o perfil dinâmico "MacEnv", que não vira o padrão — nada muda visualmente até escolher Profiles → MacEnv.

### CI
- Novo step **"Fonte Nerd no iTerm2"**: asserção estática de que o script não usa nome de arquivo onde vai nome PostScript (comentários filtrados, já que o próprio código cita o nome errado como aviso), e asserções funcionais sobre o perfil dinâmico em `$HOME` falso — gate por presença, JSON válido, fonte correta em cada ramo, e perfil existente preservado. O ramo do plist não é coberto: `defaults export/import` fala com o `cfprefsd` do usuário real e ignora `$HOME`; um stub de `defaults` força o caminho testável. Cobertura conferida por mutation testing: 5 regressões plantadas, 5 detectadas — a primeira rodada revelou que a asserção de idempotência era vazia (reescrever o mesmo conteúdo passa batido por um `diff`), hoje ela planta um marcador.

## [4.3.0] - 2026-07-25

### Added
- **Virtualenv Python visível no prompt**: o `starship.toml` gerado passa a incluir o módulo `python` com o nome do venv em destaque — âmbar `#f5b000` no `tokyo-night`, negrito no `catppuccin-powerline` (âmbar sobre o verde claro do preset dá ~1.4:1 de contraste), e âmbar também no fallback Event Horizon. Com venv ativo a barra mostra ` v3.11.0 (.venv)`; em projeto Python sem venv, só a versão; fora de projeto Python, nada muda.

  O `tokyo-night` **não traz `$python` no `format`** (só `$nodejs $bun $rust $golang $php`) — por isso o prompt ficava idêntico antes e depois do `activate`. Agrava porque o `starship init zsh` exporta `VIRTUAL_ENV_DISABLE_PROMPT=1`, desligando de propósito o prefixo `(.venv)` que o `activate` colocaria no `PS1`: o Starship espera mostrar o venv pelo módulo `python`, que o preset não incluía. O pós-processamento (`starship_patch_venv`) é idempotente e não-destrutivo — valida o TOML resultante com `starship print-config` e mantém o preset original se algo falhar.

### CI
- Novo step **"Segmento de venv no starship.toml (presets + fallback)"**: instala o Starship no runner e valida, para os dois presets, que `$python` entra no `format` logo após a âncora `$nodejs`, que existe uma única tabela `[python]`, que o TOML é válido, que o render **com** `VIRTUAL_ENV` mostra `(.venv)` e **sem** não vaza, e que `starship_patch_venv` é idempotente. Valida também o fallback embutido (TOML, âmbar no venv, nenhum símbolo ou seta de powerline vazios). O step de `.zshrc` ganhou asserções da guarda `[[ -d $PYENV_ROOT/bin ]]` e da ausência de `pyenv-virtualenv`. Cobertura conferida por mutation testing: 8 regressões plantadas, 8 detectadas.
- Asserções de **ausência** passam por uma função `ausente()` em vez de `! grep`: sob `set -e` o bash não sai quando o status é invertido por `!`, então `! grep -q ...` nunca derruba um step — era um teste que não testava nada.

### Fixed
- **`$PYENV_ROOT/bin` inexistente no PATH**: o bloco pyenv do `.zshrc` gerado exportava `$PYENV_ROOT/bin` sem checar se existe — e com pyenv instalado via Homebrew (o caminho deste script) `~/.pyenv` só tem `cache/`, `shims/`, `version` e `versions/`, então todo `.zshrc` gerado plantava um diretório morto no PATH. Agora vai sob guarda `[[ -d ]]`.
- **O fallback Event Horizon embutido nunca teve seus glifos Nerd Font**: as duas setas de powerline do `format` eram `[]` (colchete vazio) e `[git_branch]`, `[nodejs]` e `[java]` tinham `symbol = ""` — ou seja, o config que se chama "powerline" renderizava sem nenhuma transição entre segmentos e sem ícones. Não é regressão: `git log -S` mostra que o bloco entrou assim no commit que o criou (v3.3.1) e atravessou 8 versões intocado. Repostos via escape TOML (`\ue0b0`, `\uf418`, `\ue718`, `\ue256`), o mesmo mecanismo do `[python]`, que mantém o fonte do script em ASCII.

### Removed
- **`pyenv-virtualenv` sai do catálogo** e do `.zshrc` gerado (o item `pyenv` continua, só com a fórmula `pyenv`). Convenção adotada: **pyenv para a versão do Python, `python -m venv .venv` para os pacotes do projeto** — duas ferramentas resolvendo isolamento é ruído, e o `pyenv-virtualenv` ainda mexe no `PS1` por conta própria. Quem já tem a fórmula instalada não é incomodado: o script não desinstala nem sugere desinstalar — apenas deixa de instalar e de inicializar.

## [4.2.0] - 2026-07-24

### Added
- **Terminal da Apple preservado**: o `.zshrc` gerado detecta `TERM_PROGRAM=Apple_Terminal` e mantém visual padrão nele — prompt zsh clássico (sem Starship/p10k, que dependem de Nerd Font) e `eza` sem `--icons`; autosuggestions, highlight, fzf, zoxide e PATHs continuam valendo em todo lugar. Ghostty, iTerm2 e terminais de editores seguem com a experiência completa.

## [4.1.1] - 2026-07-24

### Fixed
- Tema do `gum filter`: o prefixo `◆` de item selecionado ainda usava o rosa padrão da Charm (color 212) — agora âmbar, com prefixos não-selecionados e placeholder em cinza da paleta. Zero `212` restante nos widgets tematizados.

### Docs
- `ROADMAP.md` ganha a seção **"Como ressuscitar o TUI"**: restauração do código pela tag `tui-v0.1.1`, reintegração via `git show 711a2ab` invertido, e re-pin dos binários já publicados — sem recompilar.

## [4.1.0] - 2026-07-24

### Removed
- **Companion TUI removido do repositório** (decisão de produto: o fluxo gum é o preferido e caminho opt-in não exercitado é passivo de manutenção). Nada foi perdido: código, workflow e integração completos estão preservados na tag `tui-v0.1.1` e nos releases `tui-v0.1.x` publicados. O repo volta a ser um projeto de arquivo único em Bash.

### Added
- **Busca no Personalizado**: a seleção por item agora usa `gum filter` — digite para filtrar por nome/descrição, `Tab` marca/desmarca, `Enter` confirma; defaults continuam pré-selecionados e o tema âmbar cobre indicador/matches/prefixos.

## [4.0.1] - 2026-07-24

### Changed
- **Seletor TUI vira opt-in** (`--tui` ou `MACENV_USE_TUI=1`): o fluxo gum (perfis + Personalizado item a item) volta a ser o padrão interativo — preferência de UX validada em uso real; o shader blackhole do Ghostty já compõe sobre o fluxo gum, então o visual "com shader" é nativo do padrão. TUI corrigido (truecolor, tui-v0.1.1) permanece disponível.

## [4.0.0] - 2026-07-24

### Added — Fase 4 do roadmap: companion TUI (Bubble Tea)
- **`macenv-tui`** (novo diretório `tui/`, Go + Bubble Tea + Lipgloss): seletor de itens em tela cheia com tema Event Horizon — anel com shimmer animado, busca (`/`) sobre rótulo+descrição, perfis por hotkey (1-4), toggle por categoria (`a`), painel de descrição ao vivo e abertura pré-carregada com a última instalação salva. `Enter` confirma, `q`/`Esc` cancela (exit 130).
- **Distribuição como o gum**: binário universal (arm64+x86_64) publicado em GitHub Release (`tui-vX.Y.Z`), baixado em runtime para diretório temporário com verificação SHA-256, nunca instalado; versão pinada em `MACENV_TUI_VERSION`. Workflow `release-tui.yml` builda e publica a cada tag; CI ganha job `go vet + build`.
- **Fallback permanente**: qualquer indisponibilidade (offline, checksum, `MACENV_USE_TUI=0`, rc inesperado) cai no fluxo gum da v3.11 sem perda de função; headless (`--profile`, `--categories`, CI) nunca toca o TUI. Após a seleção, o bash segue idêntico (derive de terminal/prompt, preset via gum, manifesto, engine).

## [3.11.0] - 2026-07-24

### Added — P3 fases 1-3 (self-update, rollback, Xcode)
- **`--self-update`**: baixa o `main`, compara SHA-256, valida a sintaxe do download e substitui o próprio arquivo com backup `.bak` (confirma quando interativo). Via `curl | bash` avisa que já se está na versão remota. Nova constante `MACENV_VERSION` unifica a versão (banner e comparações).
- **`--restore-zshrc`**: restaura o backup mais recente do `~/.zshrc` (mostra diferença em linhas, confirma; headless exige `--yes`; o atual vira backup antes).
- **`--remove a,b,c`**: desinstalação por item do catálogo com card de plano explícito (avisa quando um app inteiro será apagado) e confirmação; casos especiais: claude-code (remove só o binário, preserva `~/.claude`), blackhole (remove o clone e comenta o `custom-shader` na config do Ghostty, com backup). Apps fora do brew são apontados para remoção manual.
- **Xcode via `mas`** (categoria ios, opcional/default 0): instala o `mas` se preciso e baixa o Xcode da App Store (exige login; falha graciosa com instrução). Atualizações ficam com a App Store.
- Robustez: `can_prompt` agora testa a **abertura real** do `/dev/tty` (sessões detached passavam no `-r/-w` e quebravam o gum).

## [3.10.0] - 2026-07-24

### Added — fecha o P2 do roadmap
- **Seleção por item no Personalizado**: depois das categorias, um multi-select com todos os itens (rótulo + descrição, defaults pré-marcados) permite desmarcar padrões e incluir opcionais; terminal/prompt são derivados da seleção (ambos os prompts marcados → pergunta qual ativar).
- **Perfil persistente**: a seleção é salva em `~/.config/macenv/state` ao iniciar a instalação; o seletor ganha "Repetir última instalação" e o headless ganha `--profile last`. Itens/categorias que saírem do catálogo são filtrados no load.
- **Log de execução**: relatório em texto puro com tempos por item em `~/.config/macenv/last-run.log`.
- **Fonte automática no iTerm2**: com o iTerm2 fechado, define a fonte Nerd no perfil padrão via `defaults export`/PlistBuddy/`defaults import` (respeitando o cfprefsd, preservando fonte Nerd existente); com o app aberto ou sem plist, cria o Dynamic Profile "MacEnv" (hot-load).

## [3.9.0] - 2026-07-23

### Added — fecha o P1 do roadmap
- **`--doctor`**: diagnóstico read-only com calha — sistema (CLT, Xcode completo), Homebrew (versão + itens do catálogo com atualização pendente), presença dos itens por categoria (snapshot do brew + fallbacks para apps manuais e instalações via curl), e configurações (`.zshrc` gerado/PATH, starship.toml, Ghostty/shader, fonte dos editores). Card final com placar; exit 1 se houver problemas.
- **`--upgrade-only`**: roda apenas o engine de atualizações sobre todo o catálogo e sai — interativo confirma, headless aplica direto (a flag já é o consentimento).
- **CI no GitHub Actions** (runner macOS): `bash -n` com o bash 3.2 do sistema, **shellcheck bloqueante em nível warning** (script zerado de warnings), matriz de dry-runs (perfis × NO_COLOR × pipe × --yes), teste de categoria inválida, dry-run sob PTY (caminhos de animação) e geração de configs em HOME falso com `zsh -n`. Badge no README.

## [3.8.0] - 2026-07-23

### Added
- **Preservação automática de adições ao `.zshrc`** (P1 do roadmap): ao regenerar, tudo que estiver após o rodapé do arquivo anterior — onde instaladores externos anexam (Claude Code, bun, etc.) — migra para a seção "Suas adições" no arquivo novo. Dedupe de `export`/`alias`/`source`/`eval` contra o template e entre si; blocos multi-linha passam verbatim; round-trip estável entre execuções. `.zshrc` sem o marcador (não gerado por nós) mantém o comportamento anterior (só backup). Fecha a classe de regressão que derrubou bun, Claude Code e Flutter do PATH nesta série.

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
