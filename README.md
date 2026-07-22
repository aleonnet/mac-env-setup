# mac-env-setup

Instalador de ambiente de desenvolvimento para macOS em um único script Bash — idempotente, seguro para re-executar e pronto para rodar direto via `curl`.

## O que ele instala e configura

- **Xcode Command Line Tools** (abre o instalador da Apple se necessário)
- **Homebrew** (Apple Silicon ou Intel, detecta o prefixo automaticamente)
- **iTerm2** (cask)
- **Oh My Zsh** (instalação não interativa, preserva shell atual)
- **Powerlevel10k** + plugins **zsh-autosuggestions** e **zsh-syntax-highlighting**
- **pyenv**
- **eza** com alias `ls`/`ll`/`la`/`lt` (ls com ícones)
- **MesloLGS Nerd Font v3.x** (remove a v2.3.3 legada, que tem glifos incompatíveis)
- Gera um `~/.zshrc` limpo e organizado (backup do anterior antes)

## Instalação

### Remota (recomendada)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash
```

Com saída detalhada:

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/mac-env-setup/main/mac_env_install.sh | bash -s -- --verbose
```

### Local

```bash
bash mac_env_install.sh [--verbose]
```

## Variáveis de ambiente

| Variável | Padrão | Efeito |
|---|---|---|
| `MACENV_USE_GUM` | `auto` | Controla a UI com [gum](https://github.com/charmbracelet/gum) (`1`/`0`/`auto`). O gum é baixado em diretório temporário com verificação SHA256 e nunca é instalado permanentemente. |
| `MACENV_GUM_VERSION` | `0.17.0` | Versão do gum baixada para a UI. |
| `NO_COLOR` | — | Desativa cores e a UI do gum. |

## Comportamentos importantes

- **Idempotente**: cada componente é verificado antes de instalar ("já instalado" → pula). Pode re-executar quantas vezes quiser.
- **Xcode CLT**: se não estiver instalado, o script abre o instalador gráfico da Apple e **encerra**. Termine a instalação e execute o script novamente.
- **`~/.zshrc`**: o arquivo existente é copiado para `~/.zshrc.backup.<timestamp>` e depois **sobrescrito** por um template novo (não faz append).
- **Fonte**: a MesloLGS Nerd Font é sempre atualizada para a v3.x; arquivos `MesloLGS NF *.ttf` da v2.3.3 são removidos.
- Saída silenciosa por padrão: cada etapa loga em arquivo temporário e só exibe as últimas 80 linhas em caso de falha. Use `--verbose` para ver tudo.

## Requisitos

- macOS (Apple Silicon ou Intel)
- `curl` ou `wget`

## Pós-instalação

Abra o iTerm2, selecione a fonte **MesloLGS Nerd Font** no perfil (Preferences → Profiles → Text) e rode `p10k configure` se quiser reconfigurar o prompt.
