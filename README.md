# RuneScape MCP

**English** | [Português](README.pt-BR.md)

Introspection bridge between the RuneScape (RS3) client and an AI agent over
[MCP](https://modelcontextprotocol.io). The project has two halves:

| Folder | What it is |
| --- | --- |
| [`plugin/`](plugin/) | Lua plugin for the RuneScape beta client. Collects snapshots, manages event watchers and polls the bridge over HTTP. |
| [`bridge/`](bridge/) | Node.js server. Exposes MCP tools over stdio and receives the state sent by the plugin at `http://127.0.0.1:8765`. |

```
┌────────────┐  HTTP polling  ┌────────────┐  MCP stdio  ┌────────┐
│ RuneScape  │ ◄────────────► │   bridge   │ ◄─────────► │  LLM   │
│  (plugin)  │   /state /cmd   │  (Node.js) │             │ client │
└────────────┘                └────────────┘             └────────┘
```

The plugin never opens a listening socket (the game API does not allow it): it
only makes requests to the local bridge. The bridge is never exposed outside
`127.0.0.1`.

## Installation

### 1. Plugin

1. Copy the `plugin/` folder to the beta client's
   `dev_plugins/runescape-mcp/`.
2. Install the **PrettyUI** dependency (mod.io `6398181`).
3. In the client console: `prf`, `plist`, `pon runescape-mcp`,
   `ppr runescape-mcp`.
4. In the plugin settings, grant `httpAccess` (and `chatAccess` if you want to
   read chat).

Details in [`plugin/README.md`](plugin/README.md).

### 2. Bridge

```sh
cd bridge
npm start        # or: node server.js
```

Requires Node.js. The port can be changed with `MCP_BRIDGE_PORT`.

### 3. MCP client

Add the server to your client configuration (OpenCode example):

```json
{
  "mcp": {
    "runescape-mcp": {
      "type": "local",
      "command": ["node", "/path/to/runescape-mcp/bridge/server.js"],
      "disabled": false
    }
  }
}
```

In the plugin, open the **Bridge** tab → **Enable bridge**. State is then sent
every few ticks.

## MCP tools

`get_state`, `get_snapshot`, `eval_code`, `add_watcher`, `remove_watcher`,
`list_watchers`, `query_var`, `get_logs`.

## Security

- `eval_code` runs arbitrary Lua inside the client. Stick to read-only code if
  you want to keep the promise of not modifying the game.
- The bridge listens on loopback only, but any local process can talk to it —
  do not expose the port.
- Watcher code runs in the global environment through `load`.

## License

MIT — see [LICENSE](LICENSE).
