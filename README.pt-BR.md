# RuneScape MCP

[English](README.md) | **Português**

Ponte de introspecção entre o cliente RuneScape (RS3) e um agente de IA via
[MCP](https://modelcontextprotocol.io). O projeto tem duas metades:

| Pasta | O que é |
| --- | --- |
| [`plugin/`](plugin/) | Plugin Lua para o cliente beta do RuneScape. Coleta snapshots, gerencia watchers de eventos e faz polling HTTP no bridge. |
| [`bridge/`](bridge/) | Servidor Node.js. Expõe ferramentas MCP via stdio e recebe o estado enviado pelo plugin em `http://127.0.0.1:8765`. |

```
┌────────────┐  HTTP polling  ┌────────────┐  MCP stdio  ┌────────┐
│  RuneScape │ ◄────────────► │   bridge   │ ◄─────────► │  LLM   │
│  (plugin)  │   /state /cmd   │ (Node.js)  │             │ client │
└────────────┘                └────────────┘             └────────┘
```

O plugin não abre porta de escuta (a API do jogo não permite): ele só faz
requisições para o bridge local. O bridge nunca é exposto fora de
`127.0.0.1`.

## Instalação

### 1. Plugin

1. Copie a pasta `plugin/` para `dev_plugins/runescape-mcp/` do cliente beta.
2. Instale a dependência **PrettyUI** (mod.io `6398181`).
3. No console do cliente: `prf`, `plist`, `pon runescape-mcp`,
   `ppr runescape-mcp`.
4. Nas configurações do plugin, conceda `httpAccess` (e `chatAccess` se quiser
   ler o chat).

Detalhes em [`plugin/README.pt-BR.md`](plugin/README.pt-BR.md).

### 2. Bridge

```sh
cd bridge
npm start        # ou: node server.js
```

Requer Node.js. A porta pode ser trocada com `MCP_BRIDGE_PORT`.

### 3. Cliente MCP

Adicione o servidor à configuração do seu cliente (exemplo: OpenCode):

```json
{
  "mcp": {
    "runescape-mcp": {
      "type": "local",
      "command": ["node", "/caminho/para/runescape-mcp/bridge/server.js"],
      "disabled": false
    }
  }
}
```

No plugin, aba **Bridge** → **Ativar bridge**. O estado passa a ser enviado a
cada poucos ticks.

## Ferramentas MCP

`get_state`, `get_snapshot`, `eval_code`, `add_watcher`, `remove_watcher`,
`list_watchers`, `query_var`, `get_logs`.

## Segurança

- `eval_code` executa Lua arbitrário no cliente. Use apenas código de leitura
  se quiser preservar a proposta de não modificar o jogo.
- O bridge escuta apenas em loopback, mas qualquer processo local pode falar
  com ele — não exponha a porta.
- Código de watchers roda no ambiente global via `load`.

## Licença

MIT — veja [LICENSE](LICENSE).
