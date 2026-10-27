# RuneScape MCP Bridge (plugin)

**English** | [Português](README.pt-BR.md)

Development plugin for RuneScape (RS3) that acts as an introspection bridge for
an AI (or for the developer). It collects client information, lets you
subscribe Lua code to game events, and can connect to an external MCP server
over HTTP (polling).

The MCP server that talks to this plugin lives in [`../bridge`](../bridge).

## Dependencies

- PrettyUI (mod.io 6398181) — required.
- Optional permissions: `httpAccess`, `chatAccess`.

## Installation (beta)

1. Copy the `plugin/` folder from this repo to `dev_plugins/runescape-mcp/`.
2. Download PrettyUI to `dev_plugins/prettyui` (or install it via Mod.io in the
   client).
3. Run `prf` and `plist` in the client console.
4. Run `pon runescape-mcp` and `ppr runescape-mcp`. Open the settings and grant
   the plugin permissions.
5. Open the Plugins panel and select the icon.

## Usage

- **Introspection** tab: snapshots of player, inventory, NPCs, players and
  named variables (one name per line).
- **Watchers** tab: register a name, event and Lua code. The code receives the
  `event` table of the subscribed event. Results and errors are logged.
- **Bridge** tab: enable polling to `http://127.0.0.1:8765` (configurable in the
  manifest). Sends snapshots/state and runs received commands (`eval`,
  `addWatcher`, `removeWatcher`, `listWatchers`, `snapshot`, `queryVar`).
- **Logs** tab: latest messages.

## Events supported by watchers

Logic, ServerLogic, Draw, VarTransmit, SkillTransmit, RunEnergyTransmit,
RunWeightTransmit, InventoryUpdated/Added/Removed, NPCEntityAdded/Removed,
PlayerEntityAdded/Removed, ObjStackEntity*, GameStateChanged, LocAdded/Removed,
ChatMessage, MiniMenuReady/EntrySelected, WorldUpdated, RegionUpdated.

## Persistence

Watchers are persisted in `PersistentDB` and reloaded when the plugin starts.

## Limitations

- The plugin does not create an HTTP server inside the client (the API does not
  allow it). The connection to the AI uses HTTP polling against an external
  bridge.
- Watcher code runs through `load` in the global environment; it can affect the
  client. Use read-only code to honour the promise of not modifying the game.
- Snapshots are best-effort and may vary with API availability.
