const http = require("http");
const readline = require("readline");

const PORT = process.env.MCP_BRIDGE_PORT ? Number(process.env.MCP_BRIDGE_PORT) : 8765;
const HOST = "127.0.0.1";
const CMD_TIMEOUT = 15000;

let lastState = null;
let pendingCommands = [];
let commandResults = new Map();

function genId() {
  return "cmd_" + Date.now() + "_" + Math.random().toString(36).slice(2, 8);
}

function queueCommand(cmd) {
  return new Promise((resolve, reject) => {
    const id = genId();
    const full = Object.assign({ id }, cmd);
    commandResults.set(id, { resolve, reject });
    pendingCommands.push(full);
    setTimeout(() => {
      if (commandResults.has(id)) {
        commandResults.delete(id);
        reject(new Error("timeout waiting for plugin"));
      }
    }, CMD_TIMEOUT);
  });
}

const server = http.createServer((req, res) => {
  // CORS not needed (localhost)
  if (req.method === "GET" && req.url === "/commands") {
    const cmds = pendingCommands.splice(0, pendingCommands.length);
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(cmds));
    return;
  }
  if (req.method === "POST" && req.url === "/logs") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try {
        const fs = require("fs");
        const path = require("path");
        fs.appendFileSync(path.join(__dirname, "bridge.log"), new Date().toISOString() + " " + body + "\n");
      } catch (e) {}
      res.statusCode = 204;
      res.end();
    });
    return;
  }
  if (req.method === "POST" && req.url === "/state") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try { lastState = JSON.parse(body); } catch (e) { lastState = { raw: body }; }
      res.statusCode = 204;
      res.end();
    });
    return;
  }
  if (req.method === "POST" && req.url === "/result") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      let obj = {};
      try { obj = JSON.parse(body); } catch (e) { obj = { raw: body }; }
      const entry = commandResults.get(obj.id);
      if (entry) {
        commandResults.delete(obj.id);
        if (obj.ok) entry.resolve(obj.result);
        else entry.reject(new Error(obj.error || "plugin error"));
      }
      res.statusCode = 204;
      res.end();
    });
    return;
  }
  if (req.method === "GET" && req.url === "/state") {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(lastState || {}));
    return;
  }
  if (req.method === "GET" && req.url === "/health") {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ ok: true, hasState: !!lastState }));
    return;
  }
  res.statusCode = 404;
  res.end();
});

server.on("error", (err) => {
  console.error("Bridge HTTP error:", err && err.message ? err.message : err);
  process.exit(1);
});
server.listen(PORT, HOST, () => {
  // MCP stdio
});

// MCP stdio JSON-RPC
const rl = readline.createInterface({ input: process.stdin });
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

const tools = [
  {
    name: "get_state",
    description: "Retorna o último estado enviado pelo plugin (snapshot + watchers + logs).",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "get_snapshot",
    description: "Pede um snapshot completo ao plugin (player, inventário, NPCs, jogadores, vars).",
    inputSchema: {
      type: "object",
      properties: { varNames: { type: "array", items: { type: "string" } } },
      additionalProperties: false,
    },
  },
  {
    name: "eval_code",
    description: "Executa código Lua no cliente RuneScape e retorna o resultado.",
    inputSchema: {
      type: "object",
      properties: { code: { type: "string" } },
      required: ["code"],
      additionalProperties: false,
    },
  },
  {
    name: "add_watcher",
    description: "Inscreve código para executar quando um evento ocorrer.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string" },
        event: { type: "string" },
        code: { type: "string" },
        filter: { type: "string" },
      },
      required: ["name", "event", "code"],
      additionalProperties: false,
    },
  },
  {
    name: "remove_watcher",
    description: "Remove um watcher pelo id.",
    inputSchema: {
      type: "object",
      properties: { watcherId: { type: "number" } },
      required: ["watcherId"],
      additionalProperties: false,
    },
  },
  {
    name: "list_watchers",
    description: "Lista watchers ativos.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "query_var",
    description: "Lê uma variável VarPlayer ou VarClient pelo nome.",
    inputSchema: {
      type: "object",
      properties: { name: { type: "string" }, table: { type: "string", enum: ["VarPlayer", "VarClient"] } },
      required: ["name"],
      additionalProperties: false,
    },
  },
  {
    name: "get_logs",
    description: "Retorna logs recentes do plugin.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },

];

async function handleTool(name, args) {
  args = args || {};
  if (name === "get_state") {
    return lastState || { message: "sem estado ainda (plugin não enviou)" };
  }
  if (name === "get_logs") {
    const res = await queueCommand({ action: "getLogs" });
    return { logs: res || [] };
  }

  if (name === "get_snapshot") {
    const res = await queueCommand({ action: "snapshot", varNames: args.varNames || [] });
    return { snapshot: res };
  }
  if (name === "eval_code") {
    const res = await queueCommand({ action: "eval", code: args.code });
    return { result: res };
  }
  if (name === "add_watcher") {
    const res = await queueCommand({ action: "addWatcher", name: args.name, event: args.event, code: args.code, filter: args.filter || "" });
    return res;
  }
  if (name === "remove_watcher") {
    const res = await queueCommand({ action: "removeWatcher", watcherId: args.watcherId });
    return { ok: res };
  }
  if (name === "list_watchers") {
    const res = await queueCommand({ action: "listWatchers" });
    return { watchers: res };
  }
  if (name === "query_var") {
    const res = await queueCommand({ action: "queryVar", name: args.name, table: args.table || "VarPlayer" });
    return { name: args.name, value: res };
  }
  throw new Error("unknown tool: " + name);
}

rl.on("line", async (line) => {
  let req;
  try { req = JSON.parse(line); } catch (e) { return; }
  if (!req || typeof req !== "object") return;
  const { id, method, params } = req;
  if (method === "initialize") {
    send({ jsonrpc: "2.0", id, result: {
      protocolVersion: "2024-11-05",
      capabilities: { tools: {} },
      serverInfo: { name: "runescape-mcp-bridge", version: "0.1.0" },
    }});
    return;
  }
  if (method === "notifications/initialized") {
    return;
  }
  if (method === "tools/list") {
    send({ jsonrpc: "2.0", id, result: { tools } });
    return;
  }
  if (method === "tools/call") {
    const toolName = params && params.name;
    const args = params && params.arguments;
    try {
      const result = await handleTool(toolName, args);
      send({ jsonrpc: "2.0", id, result: {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      }});
    } catch (e) {
      send({ jsonrpc: "2.0", id, result: {
        content: [{ type: "text", text: "ERROR: " + (e && e.message ? e.message : e) }],
        isError: true,
      }});
    }
    return;
  }
  if (id !== undefined) {
    send({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } });
  }
});