# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

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
