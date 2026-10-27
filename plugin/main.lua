-- RuneScape MCP Bridge
-- Read-only introspection plugin + dynamic event watchers + optional HTTP bridge.
-- Uses PrettyUI for all UI.

local json = require("lib/json")
if json == nil then
    log("Não foi possível carregar lib/json.lua")
    return
end

if prettyui == nil then
    log("PrettyUI não disponível. Instale a dependência (mod.io 6398181) e recarregue.")
    return
end

-- -------------------------------------------------------------------
-- State and logging
-- -------------------------------------------------------------------
local LOG_LIMIT = 300
local logs = {}

local function logMsg(msg)
    local text = tostring(msg)
    table.insert(logs, text)
    if #logs > LOG_LIMIT then
        table.remove(logs, 1)
    end
    log(text)
end

local function safeToString(v)
    if v == nil then return "nil" end
    local ok, s = pcall(tostring, v)
    if not ok then return "<erro>" end
    return s
end

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        return nil, tostring(res)
    end
    return res, nil
end

-- -------------------------------------------------------------------
-- Watchers (dynamic subscriptions requested by AI or UI)
-- -------------------------------------------------------------------
local watchers = {}          -- list of watcher tables
local watcherCounter = 0
local EVENT_MAP = nil        -- built after globals are available

local function buildEventMap()
    EVENT_MAP = {
        Logic = Event.Logic,
        ServerLogic = Event.ServerLogic,
        Draw = Event.Draw,
        VarTransmit = Event.VarTransmit,
        SkillTransmit = Event.SkillTransmit,
        RunEnergyTransmit = Event.RunEnergyTransmit,
        RunWeightTransmit = Event.RunWeightTransmit,
        InventoryUpdated = Event.InventoryUpdated,
        InventoryAdded = Event.InventoryAdded,
        InventoryRemoved = Event.InventoryRemoved,
        NPCEntityAdded = Event.NPCEntityAdded,
        NPCEntityRemoved = Event.NPCEntityRemoved,
        PlayerEntityAdded = Event.PlayerEntityAdded,
        PlayerEntityRemoved = Event.PlayerEntityRemoved,
        ObjStackEntityAdded = Event.ObjStackEntityAdded,
        ObjStackEntityChanged = Event.ObjStackEntityChanged,
        ObjStackEntityRemoved = Event.ObjStackEntityRemoved,
        GameStateChanged = Event.GameStateChanged,
        LocAdded = Event.LocAdded,
        LocRemoved = Event.LocRemoved,
        ChatMessage = Event.ChatMessage,
        MiniMenuReady = Event.MiniMenuReady,
        MiniMenuEntrySelected = Event.MiniMenuEntrySelected,
        WorldUpdated = Event.WorldUpdated,
        RegionUpdated = Event.RegionUpdated,
    }
end

local function makeSandbox()
    local sandbox = {}
    local mt = {
        __index = function(_, key)
            if key == "ExecuteConsoleCommand" then
                return nil
            end
            return _G[key]
        end,
    }
    sandbox._G = sandbox
    setmetatable(sandbox, mt)
    return sandbox
end

local function compileCode(code)
    local sandbox = makeSandbox()
    local fn, err = load(code, "mcp-watcher", "t", sandbox)
    if fn == nil then
        return nil, tostring(err)
    end
    return fn, nil
end

local function subscribeWatcher(w)
    if EVENT_MAP == nil then buildEventMap() end
    local ev = EVENT_MAP[w.eventName]
    if ev == nil then
        w.subscribed = false
        w.lastError = "Evento desconhecido: " .. tostring(w.eventName)
        logMsg(w.lastError)
        return false
    end
    local ref = "mcp.watcher." .. tostring(w.id)
    local function cb(payload)
        local ok, res = pcall(w.fn, payload)
        w.triggerCount = (w.triggerCount or 0) + 1
        if not ok then
            w.lastError = tostring(res)
            logMsg("Watcher '" .. w.name .. "' erro: " .. tostring(res))
        else
            w.lastResult = res
            w.lastError = nil
            if res ~= nil then
                logMsg("Watcher '" .. w.name .. "' => " .. safeToString(res))
            end
        end
    end
    ev.Subscribe(ref, cb)
    w.subscribed = true
    return true
end

local function unsubscribeWatcher(w)
    if EVENT_MAP == nil then buildEventMap() end
    local ev = EVENT_MAP[w.eventName]
    logMsg("unsub: event=" .. tostring(w.eventName) .. " evType=" .. type(ev) .. " id=" .. tostring(w.id))
    if ev ~= nil then
        pcall(function() ev.Unsubscribe("mcp.watcher." .. tostring(w.id)) end)
    end
    w.subscribed = false
end

local saveWatchers
local function addWatcher(name, eventName, code, filter, persist)
    local fn, err = compileCode(code)
    if fn == nil then
        logMsg("Código inválido para watcher '" .. tostring(name) .. "': " .. err)
        return nil, err
    end
    watcherCounter = watcherCounter + 1
    local w = {
        id = watcherCounter,
        name = name or ("watcher_" .. watcherCounter),
        eventName = eventName or "ServerLogic",
        code = code,
        filter = filter or "",
        fn = fn,
        triggerCount = 0,
        lastResult = nil,
        lastError = nil,
        subscribed = false,
    }
    -- wrap fn to inject filter? The code itself can read _G.filter? Instead set a global-ish via closure? Keep simple.
    watchers[#watchers + 1] = w
    subscribeWatcher(w)
    if persist ~= false then
        saveWatchers()
    end
    logMsg("Watcher adicionado: " .. w.name .. " (" .. w.eventName .. ")")
    if watchersCountLabel then watchersCountLabel.content = "Watchers ativos: " .. tostring(#watchers) end
    return w, nil
end

local function removeWatcherById(id, persist)
    for i, w in ipairs(watchers) do
        if w.id == id then
            unsubscribeWatcher(w)
            table.remove(watchers, i)
            if persist ~= false then saveWatchers() end
            logMsg("Watcher removido: " .. w.name)
            if watchersCountLabel then watchersCountLabel.content = "Watchers ativos: " .. tostring(#watchers) end
            return true
        end
    end
    return false
end

saveWatchers = function()
    PersistentDB:SetInt("mcp.watcher.count", #watchers)
    for i, w in ipairs(watchers) do
        PersistentDB:SetString("mcp.watcher." .. i .. ".name", w.name or "")
        PersistentDB:SetString("mcp.watcher." .. i .. ".event", w.eventName or "")
        PersistentDB:SetString("mcp.watcher." .. i .. ".code", w.code or "")
        PersistentDB:SetString("mcp.watcher." .. i .. ".filter", w.filter or "")
    end
    local prev = PersistentDB:GetInt("mcp.watcher.count.prev") or 0
    if prev > #watchers then
        for i = #watchers + 1, prev do
            PersistentDB:SetString("mcp.watcher." .. i .. ".name", "")
            PersistentDB:SetString("mcp.watcher." .. i .. ".event", "")
            PersistentDB:SetString("mcp.watcher." .. i .. ".code", "")
            PersistentDB:SetString("mcp.watcher." .. i .. ".filter", "")
        end
    end
    PersistentDB:SetInt("mcp.watcher.count.prev", #watchers)
end

local function loadWatchers()
    local count = PersistentDB:GetInt("mcp.watcher.count") or 0
    for i = 1, count do
        local name = PersistentDB:GetString("mcp.watcher." .. i .. ".name")
        local eventName = PersistentDB:GetString("mcp.watcher." .. i .. ".event")
        local code = PersistentDB:GetString("mcp.watcher." .. i .. ".code")
        local filter = PersistentDB:GetString("mcp.watcher." .. i .. ".filter")
        if code and code ~= "" then
            addWatcher(name, eventName, code, filter, false)
        end
    end
end

-- -------------------------------------------------------------------
-- Introspection snapshots
-- -------------------------------------------------------------------
local SKILL_NAMES = {
    "ATTACK","DEFENCE","STRENGTH","HITPOINTS","RANGED","PRAYER","MAGIC",
    "COOKING","WOODCUTTING","FLETCHING","FISHING","FIREMAKING","CRAFTING",
    "SMITHING","MINING","HERBLORE","AGILITY","THIEVING","SLAYER","FARMING",
    "RUNECRAFTING","HUNTER","CONSTRUCTION","SUMMONING","DUNGEONEERING",
    "DIVINATION","INVENTION","ARCHAEOLOGY","NECROMANCY",
}

local function getVarValue(varTable, varName)
    if type(varTable) ~= "table" then return nil end
    local v = varTable[varName]
    if v == nil then
        return nil
    end
    if type(v) == "table" and v.value ~= nil then
        return v.value
    end
    return v
end

local function snapshotPlayer()
    local out = {}
    local entity = nil
    pcall(function() entity = Player.GetEntity and Player.GetEntity() end)
    if entity ~= nil then
        out.name = entity.displayName or entity.name
        out.coord = tostring(entity.coordGrid)
    end
    pcall(function() out.runEnergy = Player.GetRunEnergy and Player.GetRunEnergy() end)
    pcall(function() out.weight = Player.GetWeight and Player.GetWeight() end)
    out.skills = {}
    for _, sn in ipairs(SKILL_NAMES) do
        local st = SkillType[sn]
        if st ~= nil then
            local lvl, xp = nil, nil
            pcall(function() lvl = Player.GetLevelGameplay and Player.GetLevelGameplay(st) end)
            pcall(function() xp = Player.GetXPCapped and Player.GetXPCapped(st) end)
            out.skills[sn] = { level = lvl, xp = xp }
        end
    end
    return out
end

local function snapshotInventory()
    local out = {}
    local ok, inv = pcall(function() return Inventory.Find(config.Inv.INV) end)
    if not ok or inv == nil then
        out.error = "inventory unavailable"
        return out
    end
    local ok2, slots = pcall(function() return inv:GetSlots() end)
    if not ok2 or slots == nil then
        out.error = "slots unavailable"
        return out
    end
    out.items = {}
    for i, slot in ipairs(slots) do
        local obj = slot.obj or slot.objType or slot.object
        local qty = slot.count or slot.quantity or slot.stackSize or 0
        if obj ~= nil and qty and qty > 0 then
            local name = obj.name or obj.configName or obj.id
            out.items[#out.items + 1] = { slot = i, name = name, id = obj.id, quantity = qty }
        end
    end
    out.totalSlots = #slots
    return out
end

local function snapshotNPCs()
    local out = { npcs = {} }
    local playerEntity = nil
    pcall(function() playerEntity = Player.GetEntity and Player.GetEntity() end)
    local coord = playerEntity and playerEntity.coordGrid
    local npcs = nil
    if coord ~= nil then
        local ok, res = pcall(function() return NPCList.Filter({ coordGrid = coord, range = 100 }) end)
        if ok and type(res) == "table" then npcs = res end
    end
    if npcs == nil then
        out.error = "npc list unavailable"
        return out
    end
    local count = 0
    for i, npc in ipairs(npcs) do
        if count >= 80 then break end
        count = count + 1
        local name = npc.displayName or (npc.config and npc.config.name) or npc.name
        local cfg = npc.configID or (npc.config and npc.config.id)
        out.npcs[count] = { index = i, name = name, uid = npc.uid, config = cfg, coord = tostring(npc.coordGrid) }
    end
    out.total = #npcs
    return out
end

local function snapshotPlayers()
    local out = { players = {} }
    local playerEntity = nil
    pcall(function() playerEntity = Player.GetEntity and Player.GetEntity() end)
    local coord = playerEntity and playerEntity.coordGrid
    local pls = nil
    if coord ~= nil then
        local ok, res = pcall(function() return PlayerList.Filter({ coordGrid = coord, range = 100 }) end)
        if ok and type(res) == "table" then pls = res end
    end
    if pls == nil then
        out.error = "player list unavailable"
        return out
    end
    local count = 0
    for i, p in ipairs(pls) do
        if count >= 50 then break end
        count = count + 1
        local name = p.displayName or p.name
        out.players[count] = { index = i, name = name, coord = tostring(p.coordGrid) }
    end
    out.total = #pls
    return out
end

local function snapshotVars(varNames)
    local out = {}
    for _, vn in ipairs(varNames or {}) do
        local val = getVarValue(var.VarPlayer, vn)
        local src = "VarPlayer"
        if val == nil then
            val = getVarValue(var.VarClient, vn)
            src = "VarClient"
        end
        out[vn] = { source = src, value = val }
    end
    return out
end

local function fullSnapshot(varNames)
    return {
        player = snapshotPlayer(),
        inventory = snapshotInventory(),
        npcs = snapshotNPCs(),
        players = snapshotPlayers(),
        vars = snapshotVars(varNames or {}),
    }
end

-- fullSnapshot defined above (structured)

-- -------------------------------------------------------------------
-- Bridge (optional HTTP polling)
-- -------------------------------------------------------------------
local bridgeEnabled = false
local pollIntervalTicks = PersistentDB:GetInt("mcp.poll.interval") or 50
if pollIntervalTicks < 1 then pollIntervalTicks = 1 end
local bridgeTickCounter = 0
local postLogsRequested = false
local processCommandsRequested = false
local receivedCommands = {}
local manualPollRequested = false
local bridgeStatus = "desativado"

local function hasHttp()
    return Plugin.HasPermission(PluginPermissions.httpAccess)
end

local function bridgeGet(path, cb)
    if not hasHttp() then
        bridgeStatus = "sem permissão httpAccess"
        if bridgeStatusLabel then bridgeStatusLabel.content = "Status: " .. bridgeStatus end
        return
    end
    local base = Plugin.urls.mcpbridge
    if base == nil then
        bridgeStatus = "URL mcpbridge ausente"
        if bridgeStatusLabel then bridgeStatusLabel.content = "Status: " .. bridgeStatus end
        return
    end
    local req = HTTPRequest.new(base, path)

    req:Get(function(request)
        if cb then cb(request) end
    end)
end

local function bridgePost(path, payloadTable, cb)
    if not hasHttp() then
        bridgeStatus = "sem permissão httpAccess"
        return
    end
    local base = Plugin.urls.mcpbridge
    if base == nil then
        bridgeStatus = "URL mcpbridge ausente"
        return
    end
    local body = json.encode(payloadTable or {})
    local req = HTTPRequest.new(base, path)
    pcall(function() req:AddHeader("Content-Type", "application/json") end)

    req:Post(body, function(request)
        if cb then cb(request) end
    end)
end

local function handleCommand(cmd)
    if type(cmd) ~= "table" then return end
    local action = cmd.action
    local id = cmd.id
    local result = nil
    local err = nil
    if action == "eval" then
        local fn, e = compileCode(cmd.code or "")
        if fn == nil then
            err = e
        else
            local ok, res = pcall(fn)
            if not ok then err = tostring(res) else result = res end
        end
    elseif action == "addWatcher" then
        local w, e = addWatcher(cmd.name, cmd.event, cmd.code, cmd.filter, true)
        if w == nil then err = e else result = { id = w.id, name = w.name } end
    elseif action == "removeWatcher" then
        local ok = removeWatcherById(cmd.watcherId, true)
        if not ok then err = "watcher não encontrado" else result = true end
    elseif action == "listWatchers" then
        local list = {}
        for _, w in ipairs(watchers) do
            list[#list + 1] = { id = w.id, name = w.name, event = w.eventName, triggers = w.triggerCount, lastError = w.lastError }
        end
        result = list
    elseif action == "snapshot" then
        result = fullSnapshot(cmd.varNames or {})
    elseif action == "queryVar" then
        local vt = (cmd.table == "VarClient") and var.VarClient or var.VarPlayer
        local v = (type(vt) == "table") and vt[cmd.name] or nil
        if type(v) == "table" and v.value ~= nil then
            result = v.value
        else
            result = v
        end
    elseif action == "getLogs" then
        local copy = {}
        for i, v in ipairs(logs) do copy[i] = v end
        result = copy
    else
        err = "ação desconhecida: " .. tostring(action)
    end
    -- respond
    bridgePost("/result", { id = id, ok = (err == nil), result = result, error = err }, nil)
end

local function pollBridge()
    if not bridgeEnabled then return end
    -- poll bridge
    local ok, err = pcall(function()
        if not Plugin.HasPermission(PluginPermissions.httpAccess) then return end
        local base = Plugin.urls.mcpbridge
        if base == nil then return end
        local req = HTTPRequest.new(base, "/commands")
        req:Get(function(request)
            -- GET /commands
            if not request.successful then
                local newStatus = "falha HTTP " .. tostring(request.responseCode)
                if newStatus ~= bridgeStatus then
                    bridgeStatus = newStatus
                    statusChanged = true
                end
                postLogsRequested = true
                return
            end
            local newStatus = "conectado (HTTP " .. tostring(request.responseCode) .. ")"
            if newStatus ~= bridgeStatus then
                bridgeStatus = newStatus
                statusChanged = true
            end
            local cmds = json.decode(request.data)
            if type(cmds) == "table" then
                for _, c in ipairs(cmds) do
                    receivedCommands[#receivedCommands + 1] = c
                end
                if #receivedCommands > 0 then
                    processCommandsRequested = true
                end
            end
            postLogsRequested = true
        end)
    end)
    if not ok then
        logMsg("pollBridge erro: " .. tostring(err))
    end
end

-- -------------------------------------------------------------------
-- UI (PrettyUI)
-- -------------------------------------------------------------------
local contentEventID = "mcp.content"
local settingsEventID = "mcp.settings"
local contentView = nil
local settingsView = nil
local contentParent = nil
local contentTabs = nil
local lastTabIndex = 1
local watchersCountLabel = nil
local lastBridgeStatus = nil
local statusChanged = false

-- UI state
local varNamesText = ""
local watcherNameText = "novo watcher"
local watcherEventText = "VarTransmit"
local watcherCodeText = "return tostring(event and event.var and event.var.configName or event)"
local selectedWatcherId = nil
local bridgeStatusLabel = nil

local populateContent
local function rebuildContent(tabIndex)
    if tabIndex ~= nil then lastTabIndex = tabIndex end
    if contentView then
        pcall(function() contentView:Destroy() end)
        contentView = nil
    end
    if contentParent ~= nil and populateContent ~= nil then
        populateContent({ component = contentParent })
        if contentTabs ~= nil and lastTabIndex ~= nil then
            pcall(function() contentTabs:SetActive(lastTabIndex) end)
        end
    end
end

populateContent = function(event)
    local parent = event.component
    if parent == nil then
        logMsg("Camada de conteúdo indisponível.")
        return
    end
    contentParent = parent
    if contentView then
        pcall(function() contentView:Destroy() end)
        contentView = nil
    end
    contentView = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height,
    })

    contentView:AddTitle("RuneScape MCP Bridge")
    contentView:AddText("Ponte de introspecção para IA. Somente leitura: não altera o jogo.")
    contentView:AddText("50 ticks = ~1 segundo (cliente roda 50 ticks/s).")

    -- Status
    contentView:AddText("Status bridge: " .. bridgeStatus)
    watchersCountLabel = contentView:AddText("Watchers ativos: " .. tostring(#watchers))

    -- Tabs
    local tabs = contentView:AddTabs({
        { text = "Introspecção" },
        { text = "Watchers" },
        { text = "Bridge" },
        { text = "Logs" },
    }, { height = 420 })
    contentTabs = tabs

    -- Tab 1: Introspection
    local page1 = tabs:GetPage(1)
    page1:AddTitle("Snapshots (somente leitura)")
    page1:AddText("Snapshot (selecione o texto e use Ctrl+C para copiar):")
    local snapField = page1:AddTextField({ text = "", disabled = false, maxLength = 99999 })
    page1:AddSimpleButton("Snapshot Player (nível, skills, coord)", function()
        local s = json.encode(snapshotPlayer())
        if snapField then snapField:SetText(s, false) end
        -- snapshot logged via UI only
    end)
    page1:AddSimpleButton("Snapshot Inventory", function()
        local s = json.encode(snapshotInventory())
        if snapField then snapField:SetText(s, false) end
        -- snapshot logged via UI only
    end)
    page1:AddSimpleButton("Snapshot NPCs", function()
        local s = json.encode(snapshotNPCs())
        if snapField then snapField:SetText(s, false) end
        -- snapshot logged via UI only
    end)
    page1:AddSimpleButton("Snapshot Players", function()
        local s = json.encode(snapshotPlayers())
        if snapField then snapField:SetText(s, false) end
        -- snapshot logged via UI only
    end)

    page1:AddTitle("Variáveis")
    local varField = page1:AddTextField({ placeholder = "VarPlayer/VarClient name (um por linha)", height = 60, disabled = false })
    page1:AddSimpleButton("Ler variáveis", function()
        local names = {}
        for line in (varField:GetText() or ""):gmatch("[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then names[#names + 1] = trimmed end
        end
        local s = json.encode(snapshotVars(names))
        if snapField then snapField:SetText(s, false) end
        -- snapshot logged via UI only
    end)
    page1:AddSimpleButton("Snapshot completo", function()
        local names = {}
        for line in (varField:GetText() or ""):gmatch("[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then names[#names + 1] = trimmed end
        end
        local s = json.encode(fullSnapshot(names))
        if snapField then snapField:SetText(s, false) end
        -- snapshot logged via UI only
    end)

    -- Tab 2: Watchers
    local page2 = tabs:GetPage(2)
    page2:AddTitle("Novo watcher (código executado quando o evento ocorre)")
    page2:AddText("Nome do watcher:")
    local wName = page2:AddTextField({ placeholder = "ex.: onVarChange", text = watcherNameText, disabled = false })
    page2:AddText("Evento (ex.: VarTransmit, ServerLogic, Logic, SkillTransmit):")
    local wEvent = page2:AddTextField({ placeholder = "ServerLogic", text = watcherEventText, disabled = false })
    page2:AddText("Código Lua (recebe a tabela 'event'):")
    local wCode = page2:AddTextField({ placeholder = "return tostring(event)", text = watcherCodeText, height = 100, disabled = false })
    page2:AddText("Filtro opcional (interpretado pelo seu código):")
    local wFilter = page2:AddTextField({ placeholder = "ex.: nome da var", disabled = false })
    page2:AddSimpleButton("Adicionar watcher", function()
        local name = wName:GetText()
        local ev = wEvent:GetText()
        local code = wCode:GetText()
        local filter = wFilter:GetText()
        local w, e = addWatcher(name, ev, code, filter, true)
        if w == nil then
            logMsg("Falha ao adicionar watcher: " .. tostring(e))
        else
            watcherNameText = name
            watcherEventText = ev
            watcherCodeText = code
            rebuildContent()
            -- reopen? just log
        end
    end)

    page2:AddTitle("Watchers ativos")
    page2:AddSimpleButton("Atualizar lista", function()
        rebuildContent(2)
    end)
    if #watchers == 0 then
        page2:AddText("Nenhum watcher.")
    else
        for _, w in ipairs(watchers) do
            local watcher = w
            page2:AddText(string.format("#%d %s [%s] triggers=%d", watcher.id, watcher.name, watcher.eventName, watcher.triggerCount or 0))
            if watcher.lastError then
                page2:AddText("  erro: " .. watcher.lastError)
            elseif watcher.lastResult ~= nil then
                page2:AddText("  último: " .. safeToString(watcher.lastResult))
            end
            page2:AddSimpleButton("Remover #" .. watcher.id, function()
                removeWatcherById(watcher.id, true)
                rebuildContent()
            end)
        end
    end

    -- Tab 3: Bridge
    local page3 = tabs:GetPage(3)
    page3:AddTitle("HTTP Bridge (conexão com o MCP)")
    page3:AddText("Conecta ao servidor bridge em 127.0.0.1:8765.")
    bridgeStatusLabel = page3:AddText("Status: " .. bridgeStatus)
    page3:AddSimpleButton("Ativar bridge", function()
        if not Plugin.HasPermission(PluginPermissions.httpAccess) then
            bridgeStatus = "sem permissão httpAccess"
            logMsg("Bridge não ativada: conceda httpAccess (ppr runescape-mcp).")
            statusChanged = true
            return
        end
        bridgeEnabled = true
        bridgeStatus = "ativado (polling...)"
        bridgeTickCounter = 0
        logMsg("Bridge ativada.")
        statusChanged = true
    end)
    page3:AddSimpleButton("Desativar bridge", function()
        bridgeEnabled = false
        bridgeStatus = "desativado"
        logMsg("Bridge desativada.")
        statusChanged = true
    end)
    page3:AddSimpleButton("Poll agora", function()
        bridgeEnabled = true
        manualPollRequested = true
        logMsg("Poll manual solicitado.")
    end)
    page3:AddSimpleButton("Atualizar status", function()
        rebuildContent(3)
    end)
    page3:AddText("Intervalo de polling em ticks do cliente (50 = ~1s; 1 tick = ~20ms).")
    local intervalField = page3:AddTextField({ placeholder = "intervalo em ticks (padrão 50)", text = tostring(pollIntervalTicks), disabled = false })
    page3:AddSimpleButton("Aplicar intervalo", function()
        local n = tonumber(intervalField:GetText())
        if n == nil or n < 1 then
            logMsg("Intervalo inválido.")
            return
        end
        pollIntervalTicks = math.floor(n)
        PersistentDB:SetInt("mcp.poll.interval", pollIntervalTicks)
        logMsg("Intervalo de polling: " .. tostring(pollIntervalTicks) .. " ticks.")
    end)

    -- Tab 4: Logs
    local page4 = tabs:GetPage(4)
    page4:AddTitle("Logs recentes (somente leitura)")
    if #logs == 0 then
        page4:AddText("(vazio)")
    else
        local start = math.max(1, #logs - 49)
        for i = start, #logs do
            page4:AddText(tostring(logs[i]))
        end
    end
    page4:AddSimpleButton("Atualizar logs (recarrega aba)", function()
        rebuildContent(4)
    end)
end

local function populateSettings(event)
    local parent = event.component
    if parent == nil then return end
    if settingsView then
        pcall(function() settingsView:Destroy() end)
        settingsView = nil
    end
    settingsView = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height,
    })
    settingsView:AddTitle("MCP Bridge - Configurações")
    settingsView:AddText("Permissões opcionais: httpAccess, chatAccess.")
    settingsView:AddText("Declaração de URLs: mcpbridge -> http://127.0.0.1:8765")
    settingsView:AddText("PrettyUI é dependência obrigatória (mod.io 6398181).")
end

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe(contentEventID)
    Event.SettingsLayerReady.Unsubscribe(settingsEventID)
    Event.Logic.Unsubscribe("mcp.logic")
    -- unsubscribe watchers
    for _, w in ipairs(watchers) do
        unsubscribeWatcher(w)
    end
    if contentView then pcall(function() contentView:Destroy() end); contentView = nil end
    if settingsView then pcall(function() settingsView:Destroy() end); settingsView = nil end
    saveWatchers()
end

-- -------------------------------------------------------------------
-- Init
-- -------------------------------------------------------------------
buildEventMap()

-- load persisted watchers
loadWatchers()

-- server logic for bridge polling
Event.Logic.Subscribe("mcp.logic", function(logicEvent)
    if not bridgeEnabled and not manualPollRequested and not postLogsRequested and not processCommandsRequested then return end
    local ok, err = pcall(function()
        bridgeTickCounter = bridgeTickCounter + 1
        -- tick
        if manualPollRequested then
            manualPollRequested = false
            pollBridge()
            return
        end
        if processCommandsRequested then
            processCommandsRequested = false
            local cmds = receivedCommands
            receivedCommands = {}
            for _, c in ipairs(cmds) do
                local ok, err = pcall(handleCommand, c)
                if not ok then
                    logMsg("handleCommand erro: " .. tostring(err))
                end
            end
            return
        end
        if statusChanged then
            statusChanged = false
            rebuildContent(3)
        end
        if postLogsRequested then
            postLogsRequested = false
            if bridgeEnabled then
                local base = Plugin.urls.mcpbridge
                if base ~= nil then
                    local body = json.encode({ logs = logs })
                    local postReq = HTTPRequest.new(base, "/logs")
                    postReq:AddHeader("Content-Type", "application/json")
                    postReq:Post(body, function(pr)
                        -- POST /logs
                    end)
                end
            end
            return
        end
        if bridgeEnabled and bridgeTickCounter >= pollIntervalTicks then
            bridgeTickCounter = 0
            pollBridge()
        end
    end)
    if not ok then
        logMsg("Erro no tick da bridge: " .. tostring(err))
        postLogsRequested = true
        bridgeEnabled = false
        bridgeStatus = "erro: " .. tostring(err)
        if bridgeStatusLabel then bridgeStatusLabel.content = "Status: " .. bridgeStatus end
    end
end)
Event.ContentLayerReady.Subscribe(contentEventID, populateContent)
Event.SettingsLayerReady.Subscribe(settingsEventID, populateSettings)

logMsg("RuneScape MCP Bridge carregado. Abra o painel Plugins e selecione o ícone.")
