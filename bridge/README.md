# Bridge (Node.js)

**English** | [Português](README.pt-BR.md)

Bridge between the RuneScape plugin "RuneScape MCP Bridge" and an MCP client
(stdio).

## Requirements

- Node.js installed (`node --version`).
- `runescape-mcp` plugin running in the beta client, with **Bridge** tab →
  **Enable bridge**.
- `httpAccess` permission granted to the plugin (`ppr runescape-mcp` in the
  console).

## Run

```sh
cd bridge
npm start          # or: node server.js
```

The HTTP server listens on `http://127.0.0.1:8765` and MCP uses stdin/stdout of
the same process. For another port:

```sh
MCP_BRIDGE_PORT=9000 node server.js
```

## Configure the MCP client

OpenCode example (`~/.config/opencode/opencode.json` or the project's
`opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "runescape-mcp": {
      "type": "local",
      "command": ["node", "/path/to/runescape-mcp/bridge/server.js"],
      "disabled": false
    }
  }
}
```

The client starts the process automatically.

## Verify

```sh
opencode mcp list
```

Tools show up as `runescape-mcp_get_state`, `runescape-mcp_eval_code`, and so
on.

## Flow

1. In RuneScape, enable the bridge in the plugin.
2. The plugin sends state every few ticks to `http://127.0.0.1:8765`
   (`POST /state`) and polls for commands (`GET /commands`).
3. The MCP client queries state, runs code and manages watchers.

## HTTP endpoints

| Method | Route | Purpose |
| --- | --- | --- |
| `POST` | `/state` | Plugin sends the latest state. |
| `GET` | `/state` | Last received state. |
| `GET` | `/commands` | Plugin fetches pending commands. |
| `POST` | `/result` | Plugin returns the result of a command. |
| `POST` | `/logs` | Plugin appends logs to `bridge.log` (git-ignored). |
| `GET` | `/health` | Quick health check. |

## Exposed tools

`get_state`, `get_snapshot`, `eval_code`, `add_watcher`, `remove_watcher`,
`list_watchers`, `query_var`, `get_logs`.

## Security

- Listens on `127.0.0.1` only; do not expose the port.
- `eval_code` runs arbitrary Lua in the client — treat it as remote code
  execution.
