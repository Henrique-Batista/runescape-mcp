# RuneScape MCP Bridge

Plugin de desenvolvimento para RuneScape (RS3) que funciona como ponte de
introspecção para uma IA (ou para o próprio desenvolvedor). Ele coleta
informações do cliente, permite inscrever código em eventos do jogo e pode se
conectar a um servidor MCP externo via HTTP (polling).

O servidor MCP que conversa com este plugin está em [`../bridge`](../bridge).

## Dependências

- PrettyUI (mod.io 6398181) — obrigatória.
- Permissões opcionais: `httpAccess`, `chatAccess`.

## Instalação (beta)

1. Copie a pasta `plugin/` deste repo para `dev_plugins/runescape-mcp/`.
2. Baixe o PrettyUI para `dev_plugins/prettyui` (ou instale via Mod.io no cliente).
3. Execute `prf` e `plist` no console do cliente.
4. `pon runescape-mcp` e `ppr runescape-mcp`. Vá nas configurações e habilite as permissões do plugin.
5. Abra o painel Plugins e selecione o ícone.

## Uso

- Aba **Introspecção**: snapshots de player, inventário, NPCs, jogadores e
  variáveis informadas (um nome por linha).
- Aba **Watchers**: registre um nome, evento e código Lua. O código recebe a
  tabela `event` do evento assinado. Resultados e erros são registrados.
- Aba **Bridge**: ative o polling para `http://127.0.0.1:8765` (configurável
  via manifest). Envia snapshots/estado e executa comandos recebidos
  (`eval`, `addWatcher`, `removeWatcher`, `listWatchers`, `snapshot`,
  `queryVar`).
- Aba **Logs**: últimas mensagens.

## Eventos suportados para watchers

Logic, ServerLogic, Draw, VarTransmit, SkillTransmit, RunEnergyTransmit,
RunWeightTransmit, InventoryUpdated/Added/Removed, NPCEntityAdded/Removed,
PlayerEntityAdded/Removed, ObjStackEntity*, GameStateChanged, LocAdded/Removed,
ChatMessage, MiniMenuReady/EntrySelected, WorldUpdated, RegionUpdated.

## Persistência

Watchers são persistidos em `PersistentDB` e recarregados ao ativar o plugin.

## Limitações

- O plugin não cria servidor HTTP no cliente (API não permite). A conexão com a
  IA ocorre por polling HTTP para um bridge externo.
- Código de watchers é executado com `load` no ambiente global; pode afetar o
  cliente. Use apenas código de leitura para respeitar a proposta de não
  modificar o jogo.
- Snapshots são best-effort e podem variar conforme disponibilidade da API.
