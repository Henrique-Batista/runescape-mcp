# Bridge (Node.js)

Ponte entre o plugin RuneScape "RuneScape MCP Bridge" e um cliente MCP (stdio).

## Pré-requisitos

- Node.js instalado (`node --version`).
- Plugin `runescape-mcp` ativo no cliente beta, na aba **Bridge** →
  **Ativar bridge**.
- Permissão `httpAccess` concedida ao plugin (`ppr runescape-mcp` no console).

## Rodar

```sh
cd bridge
npm start          # ou: node server.js
```

O servidor HTTP escuta em `http://127.0.0.1:8765` e o MCP usa stdin/stdout do
mesmo processo. Para outra porta:

```sh
MCP_BRIDGE_PORT=9000 node server.js
```

## Configurar no cliente MCP

Exemplo com OpenCode (`~/.config/opencode/opencode.json` ou `opencode.json` do
projeto):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "runescape-mcp": {
      "type": "local",
      "command": ["node", "/caminho/para/runescape-mcp/bridge/server.js"],
      "disabled": false
    }
  }
}
```

O cliente inicia o processo automaticamente.

## Verificar

```sh
opencode mcp list
```

As ferramentas aparecem como `runescape-mcp_get_state`,
`runescape-mcp_eval_code`, etc.

## Fluxo

1. No RuneScape, ative a bridge no plugin.
2. O plugin envia estado a cada poucos ticks para `http://127.0.0.1:8765`
   (`POST /state`) e faz polling de comandos (`GET /commands`).
3. O cliente MCP consulta estado, executa código e gerencia watchers.

## Endpoints HTTP

| Método | Rota | Uso |
| --- | --- | --- |
| `POST` | `/state` | Plugin envia o último estado. |
| `GET` | `/state` | Último estado recebido. |
| `GET` | `/commands` | Plugin busca comandos pendentes. |
| `POST` | `/result` | Plugin devolve o resultado de um comando. |
| `POST` | `/logs` | Plugin anexa logs em `bridge.log` (ignorado pelo git). |
| `GET` | `/health` | Diagnóstico rápido. |

## Ferramentas expostas

`get_state`, `get_snapshot`, `eval_code`, `add_watcher`, `remove_watcher`,
`list_watchers`, `query_var`, `get_logs`.

## Segurança

- Escuta apenas em `127.0.0.1`; não exponha a porta.
- `eval_code` executa Lua arbitrário no cliente — trate como execução remota de
  código.
