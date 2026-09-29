#!/usr/bin/env python3
"""
Dev tooling: executes the Referral System resource inside a real Lua VM
(lupa) against mocked MTA:SA server/client APIs and a mocked NovaUI v3.0.0.

It proves that the resource actually runs:
  * server logic (codes, self referral, duplicates, requirements, rewards)
  * client UI construction, navigation and data binding
  * loading / empty / error states
  * no duplicate windows, no nil errors

Run:  python3 tools/test_resource.py
"""
import os
import sys

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RESOURCE = os.path.join(ROOT, "referral_system")

SERVER_ORDER = [
    "server/storage.lua",
    "server/validation.lua",
    "server/referrals.lua",
    "server/rewards.lua",
    "server/main.lua",
    "server.lua",
]
CLIENT_ORDER = [
    "client/novaui.lua",
    "client/ui.lua",
    "client/state.lua",
    "client/navigation.lua",
    "client/dashboard.lua",
    "client/referrals.lua",
    "client/rewards.lua",
    "client/statistics.lua",
    "client/conditions.lua",
    "client/dialogs.lua",
    "client/main.lua",
    "client.lua",
]

MTA_STUBS = r"""
--============================================================--
--  MTA:SA SERVER/CLIENT API STUBS (test only)
--============================================================--
unpack = unpack or table.unpack

TEST = { log = {}, players = {}, money = {}, cursor = false, keys = {}, commands = {},
         handlers = {}, timers = {}, sounds = {}, notifications = {}, clips = {} }

local tick = 0
function getTickCount() tick = tick + 1 return tick end
function isTimer(t) return type(t) == "table" and t.alive == true end
function killTimer(t) if type(t) == "table" then t.alive = false end end
function setTimer(fn, ms, times)
    local t = { alive = true, fn = fn, ms = ms or 1000, times = times or 1, fires = 0 }
    TEST.timers[#TEST.timers + 1] = t
    return t
end
function TEST.fireTimers(times)
    for _, t in ipairs(TEST.timers) do
        if t.alive then
            for _ = 1, (times or 1) do
                if t.alive then t.fn() t.fires = t.fires + 1 end
            end
        end
    end
end

function outputDebugString(msg, level)
    TEST.log[#TEST.log + 1] = tostring(msg)
    if TEST.verbose then print("   [lua] " .. tostring(msg)) end
end
function outputChatBox(msg) TEST.log[#TEST.log + 1] = "chat:" .. tostring(msg) end

function getRealTime(ts)
    ts = ts or os.time()
    local t = os.date("*t", ts)
    return { timestamp = ts, year = t.year - 1900, month = t.month - 1,
             monthday = t.day, hour = t.hour, minute = t.min, second = t.sec }
end

--  elements -------------------------------------------------
local function isMtaElement(value)
    return type(value) == "table" and (value.__element or value.__player) == true
end
function isElement(value) return isMtaElement(value) end
function getElementType(value) return isMtaElement(value) and value.elementType or false end
function destroyElement(value) if isMtaElement(value) then value.destroyed = true end end

--  players --------------------------------------------------
function TEST.newPlayer(name, serial, account)
    local p = { __player = true, elementType = "player", name = name, serial = serial,
                account = account, level = 1, playtime = 0, money = 0 }
    TEST.players[#TEST.players + 1] = p
    return p
end
function getPlayerName(p) return isMtaElement(p) and p.name or false end
function getPlayerSerial(p) return isMtaElement(p) and p.serial or false end
function getPlayerAccount(p)
    if not isMtaElement(p) then return false end
    return { __account = true, name = p.account }
end
function getAccountName(acc) return type(acc) == "table" and acc.name or nil end
function getPlayerFromSerial(serial)
    for _, p in ipairs(TEST.players) do
        if p.serial == serial then return p end
    end
    return false
end
function getElementsByType(kind)
    if kind ~= "player" then return {} end
    local out = {}
    for _, p in ipairs(TEST.players) do
        if not p.quit then out[#out + 1] = p end
    end
    return out
end
function givePlayerMoney(p, amount) p.money = (p.money or 0) + (amount or 0) TEST.money[#TEST.money + 1] = { p, amount } end

--  resources ------------------------------------------------
resourceRoot = { __resource = true, name = "referral_system" }
localPlayer = { __player = true, elementType = "player", name = "localPlayer", serial = "LOCAL", account = "raouf" }
function getResourceFromName(name) return { __resource = true, name = name } end
function getResourceName(res) return type(res) == "table" and res.name or "" end
function getResourceState(res) return "running" end
function getResources() return { getResourceFromName("NovaUI") } end
function getResourceExportedFunctions(res)
    TEST.exports = TEST.exports or {}
    return TEST.exports[getResourceName(res)] or { "create", "notify", "animate", "setFont" }
end
function get(key)
    local v = TEST.settings and TEST.settings[key]
    return v
end

--  events ---------------------------------------------------
function addEvent(name, allow)
    TEST.handlers[name] = TEST.handlers[name] or { allow = allow, fns = {} }
end
--  MTA semantics: handlers attached to the SOURCE element receive only the
--  event arguments, handlers attached to root receive the source first.
function addEventHandler(name, attached, fn)
    local entry = TEST.handlers[name] or { allow = nil, fns = {} }
    entry.fns[#entry.fns + 1] = { fn = fn, attached = attached }
    TEST.handlers[name] = entry
end
function removeEventHandler() end
function triggerEvent(name, source, ...)
    local entry = TEST.handlers[name]
    if not entry or not entry.fns then return true end
    for _, handler in ipairs(entry.fns) do
        local deliver = true
        local args = { ... }
        if handler.attached ~= nil and handler.attached ~= source then
            deliver = false
        end
        if deliver then
            local ok, err
            if handler.attached == nil then
                --  attached to root: receives the source element first
                ok, err = pcall(handler.fn, source, unpack(args))
            else
                --  attached to the source element: receives the arguments only
                ok, err = pcall(handler.fn, unpack(args))
            end
            if not ok then error("event " .. name .. " failed: " .. tostring(err)) end
        end
    end
    return true
end
function triggerClientEvent(player, name, resource, ...)
    TEST.lastClientEvent = { name = name, player = player, args = { ... } }
    return triggerEvent(name, player, ...)
end
function triggerServerEvent(name, resource, ...)
    TEST.lastServerEvent = { name = name, args = { ... } }
    return triggerEvent(name, localPlayer, ...)
end

--  input / ui helpers ---------------------------------------
function bindKey(key, state, fn) TEST.keys[key] = fn end
function unbindKey(key) TEST.keys[key] = nil end
function addCommandHandler(name, fn) TEST.commands[name] = fn end
function showCursor(state) TEST.cursor = state end
function setClipboard(text) TEST.clips[#TEST.clips + 1] = text return true end
function playSound(path) TEST.sounds[#TEST.sounds + 1] = path end
function setTimerCount() return #TEST.timers end

--  database (records the calls, returns empty result sets) --
TEST.db = { connects = {}, execs = {}, queries = {} }
function dbConnect(kind, ...)
    TEST.db.connects[#TEST.db.connects + 1] = { kind = kind, ... }
    return { __db = true }
end
function dbExec(db, sql, ...) TEST.db.execs[#TEST.db.execs + 1] = sql return true end
function dbQuery(db, sql, ...) TEST.db.queries[#TEST.db.queries + 1] = sql return { __query = true } end
function dbPoll(qh, timeout) return {} end
function dbFree() end
"""

NOVAUI_MOCK = r"""
--============================================================--
--  NOVAUI v3.0.0 MOCK  (mirrors the REAL export contract)
--============================================================--
--  MTA gives every resource its own Lua VM, so a global `NovaUI` table created
--  inside the NovaUI resource is NOT reachable from another resource. The only
--  way in is the export list NovaUI declares in its meta.xml, and novaCreate
--  returns a component ID - not a component.
--
--  This mock therefore exposes exactly those exports and behaves the way the
--  real library does:
--    * novaCreate(typeName, props, parentId) -> id (number) | false
--    * the onClick/onChange/onHover/onFocus/onBlur/onClose/onSubmit props are
--      bound by the library itself, exactly like Component:init does
--    * events that are NOT auto-bound (select, sort, minimize, doubleClick)
--      only work through novaOn - which is why that export exists
--
--  TEST helpers used by the checks below:
--    TEST.click(id) / TEST.change(id, value) / TEST.emit(id, event, ...)
--    TEST.destroyed(id) / TEST.props(id) / TEST.components()
--============================================================--
TEST.elements     = {}
TEST.notifications = {}
TEST.confirms     = {}
TEST.themes       = {}
TEST.elementCount = 0
TEST.destroyedIds = {}
TEST.calls        = {}

local function nextId()
    TEST.elementCount = TEST.elementCount + 1
    return TEST.elementCount
end

--  the props NovaUI binds itself when a component is created
local PROP_EVENTS = {
    click = "onClick", change = "onChange", hover = "onHover",
    focus = "onFocus", blur = "onBlur", close = "onClose", submit = "onSubmit",
}

local function newComponent(typeName, props, parentId)
    local comp = {
        id       = nextId(),
        type     = tostring(typeName):lower(),
        props    = props or {},
        parent   = parentId,
        children = {},
        visible  = (props or {}).visible ~= false,
        value    = (props or {}).value,
        text     = tostring((props or {}).text or ""),
        handlers = {},
        alive    = true,
    }
    --  the data components keep their rows reachable both ways
    comp.rows = (props or {}).rows or (props or {}).data
    comp.data = (props or {}).data or (props or {}).rows
    for event, propName in pairs(PROP_EVENTS) do
        local fn = comp.props[propName]
        if type(fn) == "function" then comp.handlers[event] = fn end
    end
    TEST.elements[comp.id] = comp
    return comp
end

local function resolve(elementOrId)
    if type(elementOrId) == "table" and elementOrId.id then return elementOrId end
    return TEST.elements[elementOrId]
end

--============================================================--
--  EXPORTED FUNCTIONS (the names NovaUI declares in meta.xml)
--============================================================--
function novaCreate(typeName, props, parentId)
    if type(typeName) ~= "string" or typeName == "" then return false end
    if props ~= nil and type(props) ~= "table" then props = {} end
    local comp = newComponent(typeName, props, parentId)
    if parentId and TEST.elements[parentId] then
        table.insert(TEST.elements[parentId].children, comp.id)
    end
    return comp.id
end

function novaDestroy(elementOrId)
    local comp = resolve(elementOrId)
    if not comp or not comp.alive then return false end
    comp.alive = false
    TEST.destroyedIds[comp.id] = true
    TEST.elements[comp.id] = nil
    return true
end

function novaSetVisible(elementId, visible)
    local comp = resolve(elementId)
    if not comp then return false end
    comp.visible = visible ~= false
    return true
end

function novaUpdate(elementId, newProps)
    local comp = resolve(elementId)
    if not comp or type(newProps) ~= "table" then return false end
    for k, v in pairs(newProps) do comp.props[k] = v end
    if newProps.text ~= nil then comp.text = tostring(newProps.text) end
    if newProps.value ~= nil then comp.value = newProps.value end
    if newProps.visible ~= nil then comp.visible = newProps.visible ~= false end
    if newProps.rows ~= nil or newProps.data ~= nil then
        comp.rows = newProps.rows or newProps.data
        comp.data = newProps.data or newProps.rows
    end
    return true
end

function novaCall(elementId, methodName, ...)
    local comp = resolve(elementId)
    if not comp then return false end
    TEST.calls[#TEST.calls + 1] = { id = comp.id, method = methodName, args = { ... } }
    if methodName == "setRows" or methodName == "setData" or methodName == "setItems" then
        local rows = (...)
        comp.props.data = rows
        comp.props.rows = rows
        comp.rows, comp.data = rows, rows
        return true
    elseif methodName == "setFilter" then
        comp.props.filter = (...)
        return true
    elseif methodName == "setSort" or methodName == "sortBy" then
        comp.props.sortColumn = (...)
        return true
    elseif methodName == "setType" then
        comp.props.chartType = (...)
        return true
    elseif methodName == "setText" then
        comp.text = tostring((...))
        return true
    elseif methodName == "setValue" then
        comp.value = (...)
        return true
    elseif methodName == "setVisible" then
        comp.visible = (...) ~= false
        return true
    elseif methodName == "bringToFront" or methodName == "focus" then
        return true
    elseif methodName == "destroy" then
        return novaDestroy(comp.id)
    end
    return false
end

function novaOn(elementId, eventName, handler)
    local comp = resolve(elementId)
    if not comp or type(handler) ~= "function" then return false end
    comp.handlers[eventName] = handler
    return true
end

function novaOnce(elementId, eventName, handler)
    local comp = resolve(elementId)
    if not comp or type(handler) ~= "function" then return false end
    local fired = false
    comp.handlers[eventName] = function(...)
        if fired then return end
        fired = true
        return handler(...)
    end
    return true
end

function novaOff(elementId, eventName, handler)
    local comp = resolve(elementId)
    if not comp then return false end
    if handler == nil then
        comp.handlers[eventName] = nil
    elseif comp.handlers[eventName] == handler then
        comp.handlers[eventName] = nil
    end
    return true
end

function novaAnimate(elementId, spec)
    local comp = resolve(elementId)
    if not comp or type(spec) ~= "table" then return false end
    return true
end

function novaGetValue(elementId)
    local comp = resolve(elementId)
    return comp and comp.value or nil
end

function novaSetText(elementId, text)
    local comp = resolve(elementId)
    if not comp then return false end
    comp.text = tostring(text)
    return true
end

function novaNotify(options)
    TEST.notifications[#TEST.notifications + 1] = options or {}
    return nextId()
end

function novaConfirm(options)
    TEST.confirms[#TEST.confirms + 1] = options or {}
    return nextId()
end

function novaSetTheme(themeName)
    TEST.themes[#TEST.themes + 1] = themeName
    return true
end

function novaCreateTheme(name, definition, baseTheme)
    TEST.themes[#TEST.themes + 1] = name
    return true
end

function novaScale(value)
    return math.floor((tonumber(value) or 0) * 1.0)
end

--============================================================--
--  the exports table, exactly as MTA builds it:
--  exports[name].ANYTHING is a function even when the resource
--  never declared it - which is why the bridge must ask
--  getResourceExportedFunctions() what is really there.
--============================================================--
local NOVA_EXPORTS = {
    "novaCreate", "novaDestroy", "novaSetTheme", "novaCreateTheme", "novaScale",
    "novaNotify", "novaConfirm", "novaSetVisible", "novaOn", "novaOnce", "novaOff",
    "novaUpdate", "novaCall", "novaAnimate", "novaGetValue", "novaSetText",
}

local exportsMT = {}
exportsMT.__index = function(tbl, key)
    if type(key) ~= "string" then key = tostring(key) end
    --  a real export resolves to the function, anything else to a stub that
    --  fails when called - the same trap MTA sets
    for _, name in ipairs(NOVA_EXPORTS) do
        if name == key and type(_G[key]) == "function" then
            return function(_, ...) return _G[key](...) end
        end
    end
    return function() error("call: failed to call '" .. tostring(key) .. "' [string \"?\"]", 0) end
end

exports = setmetatable({}, {
    __index = function(tbl, key)
        if type(key) ~= "string" then key = tostring(key) end
        if key:lower() == "novaui" or key:lower() == "nova" or key:lower() == "nova_ui"
            or key:lower() == "nova-ui" or key:lower() == "novauiv3" then
            return setmetatable({}, exportsMT)
        end
        return setmetatable({}, exportsMT)
    end
})

function getResourceFromName(name)
    local lowered = tostring(name):lower()
    if lowered == "novaui" or lowered == "nova" or lowered == "nova_ui"
        or lowered == "nova-ui" or lowered == "novauiv3" then
        return { __resource = true, name = name }
    end
    return nil
end

function getResourceState(res)
    return res and res.__resource and "running" or nil
end

function getResourceName(res)
    return res and res.name or "unknown"
end

function getResources()
    return { getResourceFromName("NovaUI") }
end

function getResourceExportedFunctions(res)
    if not res or not res.__resource then return nil end
    return NOVA_EXPORTS
end

--============================================================--
--  TEST HELPERS (drive the mock the way a player would)
--============================================================--
function TEST.props(id)
    local comp = TEST.elements[id]
    return comp and comp.props or nil
end

function TEST.component(id)
    return TEST.elements[id]
end

function TEST.components()
    return TEST.elements
end

function TEST.wasDestroyed(id)
    return TEST.destroyedIds[id] == true
end

function TEST.emit(id, event, ...)
    local comp = TEST.elements[id]
    if not comp then return false end
    local handler = comp.handlers[event]
    if type(handler) ~= "function" then return false end
    handler(...)
    return true
end

function TEST.click(id, ...)
    return TEST.emit(id, "click", ...)
end

function TEST.change(id, value)
    local comp = TEST.elements[id]
    if not comp then return false end
    comp.value = value
    return TEST.emit(id, "change", value)
end

function TEST.select(id, row, index)
    return TEST.emit(id, "select", row, index)
end

function TEST.sort(id, key, ascending)
    return TEST.emit(id, "sort", key, ascending)
end

function TEST.children(id)
    local comp = TEST.elements[id]
    return comp and comp.children or {}
end

function TEST.visible(id)
    local comp = TEST.elements[id]
    return comp and comp.visible or false
end

--  the global NovaUI table does NOT exist for another resource (own VM)
NovaUI = nil
"""

SERVER_TESTS = r"""
--============================================================--
--  SERVER TESTS
--============================================================--
local failures, checks = {}, 0
local function check(label, condition, detail)
    checks = checks + 1
    if condition then
        print(string.format("  PASS  %s", label))
    else
        print(string.format("  FAIL  %s %s", label, detail and ("-> " .. tostring(detail)) or ""))
        failures[#failures + 1] = label
    end
end

print("== server ==")

--  switch storage to the memory backend for a deterministic run
ReferralConfig.storage.backend = "memory"
ReferralConfig.debug = true

--  fire onResourceStart (registered by server/main.lua)
triggerEvent("onResourceStart", resourceRoot)
check("server initialised", ReferralServer.storage.isReady() == true)
check("storage backend is memory", ReferralServer.storage.backendName() == "memory")

--  players
local A = TEST.newPlayer("Raouf", "SERIAL-A", "raouf")
local B = TEST.newPlayer("Sara", "SERIAL-B", "sara")
local C = TEST.newPlayer("Karim", "SERIAL-C", "karim")
local D = TEST.newPlayer("Lina", "SERIAL-D", "lina")

triggerEvent("onPlayerJoin", A)
triggerEvent("onPlayerJoin", B)
triggerEvent("onPlayerJoin", C)
triggerEvent("onPlayerJoin", D)

local codeA = ReferralServer.main.getReferralCode(A)
check("code generated", type(codeA) == "string" and #codeA >= 8, codeA)
check("code uses account prefix", codeA:sub(1, 5) == "RAOUF", codeA)
check("code is stable", ReferralServer.main.getReferralCode(A) == codeA)

--  B uses A's code
local result = ReferralServer.referrals.applyCode(B, codeA)
check("valid code accepted", result.ok == true, result.message)
check("success message", result.message == "تم تطبيق كود الاحالة بنجاح", result.message)

--  B tries his own code
local ownCode = ReferralServer.main.getReferralCode(B)
result = ReferralServer.referrals.applyCode(B, ownCode)
check("self referral blocked", result.ok == false and result.errorKey == "self_code",
    result.errorKey or result.message)

--  C uses a bogus code
result = ReferralServer.referrals.applyCode(C, "ZZZZ-9999")
check("invalid code rejected", result.ok == false and result.errorKey == "invalid_code",
    result.errorKey or result.message)

--  cooldown after an attempt
result = ReferralServer.referrals.applyCode(C, codeA)
check("cooldown enforced", result.ok == false and result.errorKey == "cooldown",
    result.errorKey or result.message)
ReferralConfig.code.cooldownSeconds = 0
result = ReferralServer.referrals.applyCode(C, codeA)
check("code accepted after cooldown", result.ok == true, result.errorKey or result.message)

--  duplicate referral
ReferralConfig.code.cooldownSeconds = 0
result = ReferralServer.referrals.applyCode(C, codeA)
check("duplicate referral blocked", result.ok == false and result.errorKey == "already_used",
    result.errorKey or result.message)

--  D uses A's code as well
result = ReferralServer.referrals.applyCode(D, codeA)
check("second invitee accepted", result.ok == true, result.errorKey or result.message)

--  requirements are enforced
ReferralConfig.requirements.level = 3
ReferralConfig.requirements.playtimeMinutes = 60
ReferralConfig.rewards.perReferral = 5000

local profile = ReferralServer.referrals.buildProfile(A)
check("profile built", type(profile) == "table" and profile.ok == true)
check("referral count is 3", profile.stats.total == 3, profile.stats.total)
check("all referrals pending", profile.stats.pending == 3, profile.stats.pending)
check("no reward yet", profile.stats.earned == 0, profile.stats.earned)

--  B reaches the level but not the playtime
ReferralServer.main.setLevel(B, 5)
profile = ReferralServer.referrals.buildProfile(A)
check("requirements incomplete -> still pending",
    profile.stats.completed == 0 and profile.stats.pending == 3,
    tostring(profile.stats.completed) .. "/" .. tostring(profile.stats.pending))
check("no money paid", TEST.money[1] == nil)

--  B completes the playtime -> reward
ReferralServer.main.addPlaytime(B, 90)
profile = ReferralServer.referrals.buildProfile(A)
check("referral completed", profile.stats.completed == 1, profile.stats.completed)
check("reward earned", profile.stats.earned == 5000, profile.stats.earned)
check("money paid once", TEST.money[1] and TEST.money[1][2] == 5000, TEST.money[1] and TEST.money[1][2])
check("reward total", profile.stats.totalRewards == 5000, profile.stats.totalRewards)

--  reward row model
check("rewards view has one entry", #profile.rewards == 1, #profile.rewards)
check("reward marked paid", profile.rewards[1].status == "paid", profile.rewards[1].status)
check("reward amount text", profile.rewards[1].amountText == "5,000 $", profile.rewards[1].amountText)

--  D completes too -> milestone at 5 is not reached yet
ReferralServer.main.setLevel(D, 4)
ReferralServer.main.addPlaytime(D, 120)
profile = ReferralServer.referrals.buildProfile(A)
check("two completed referrals", profile.stats.completed == 2, profile.stats.completed)
check("conversion rate", profile.stats.conversion == 67, profile.stats.conversion)

--  charts use real data
check("daily series has 7 points", #profile.series.daily == 7, #profile.series.daily)
check("daily series counts today", profile.series.daily[7].value == 3, profile.series.daily[7].value)
check("donut has completed slice", #profile.series.status >= 1, #profile.series.status)
check("reward series has 7 points", #profile.series.rewards == 7, #profile.series.rewards)
check("reward series total", profile.series.rewards[7].value == 10000, profile.series.rewards[7].value)

--  referral view model
local view = profile.referrals[1]
check("view has player name", type(view.player) == "string" and #view.player > 0, view.player)
check("view has level", view.level == 4, view.level)
check("view has playtime text", view.playtimeText == "2 س", view.playtimeText)
check("view has status label", view.statusLabel == "مكتمل", view.statusLabel)
check("view has timeline", #view.timeline == 5, #view.timeline)
check("view timeline last done", view.timeline[5].done == true)

--  milestone: force 5 completed referrals
for i = 1, 3 do
    local p = TEST.newPlayer("Bot" .. i, "BOT-" .. i, "bot" .. i)
    triggerEvent("onPlayerJoin", p)
    ReferralServer.referrals.applyCode(p, codeA)
    ReferralServer.main.setLevel(p, 10)
    ReferralServer.main.addPlaytime(p, 200)
end
profile = ReferralServer.referrals.buildProfile(A)
check("five completed referrals", profile.stats.completed == 5, profile.stats.completed)
check("milestone reward paid", profile.stats.earned == (25000 + 5000 * 5),
    profile.stats.earned)
check("milestone row present", (function()
    for _, r in ipairs(profile.rewards) do
        if r.type == "milestone" then return true end
    end
    return false
end)())

--  max referrals limit
ReferralConfig.maxReferrals = 5
local E = TEST.newPlayer("Extra", "SERIAL-E", "extra")
triggerEvent("onPlayerJoin", E)
result = ReferralServer.referrals.applyCode(E, codeA)
check("owner limit enforced", result.ok == false and result.errorKey == "owner_limit",
    result.errorKey or result.message)
ReferralConfig.maxReferrals = 0

--  eligibility flag for a fresh player
local F = TEST.newPlayer("Fresh", "SERIAL-F", "fresh")
triggerEvent("onPlayerJoin", F)
profile = ReferralServer.referrals.buildProfile(F)
check("fresh player can use a code", profile.canUseCode == true, tostring(profile.canUseCode))
check("fresh player code exists", #profile.code >= 8, profile.code)
check("fresh player has empty lists", #profile.referrals == 0 and #profile.rewards == 0)
check("empty donut", #profile.series.status == 0, #profile.series.status)

--  claim flow (autoPay disabled)
ReferralConfig.rewards.autoPay = false
local G = TEST.newPlayer("Claimer", "SERIAL-G", "claimer")
triggerEvent("onPlayerJoin", G)
ReferralServer.referrals.applyCode(G, codeA)
ReferralServer.main.setLevel(G, 9)
ReferralServer.main.addPlaytime(G, 100)
profile = ReferralServer.referrals.buildProfile(A)
check("pending reward created", profile.stats.pendingRewards == 5000, profile.stats.pendingRewards)
local claim = ReferralServer.rewards.claim(A, profile.rewards[1].id)
check("claim succeeds", claim.ok == true, claim.message)
check("claim pays the amount", claim.amount == 5000, claim.amount)
local claimAgain = ReferralServer.rewards.claim(A, profile.rewards[1].id)
check("double claim blocked", claimAgain.ok == false, claimAgain.errorKey)
ReferralConfig.rewards.autoPay = true

--  server -> client payload
check("profile event sent to client",
    TEST.lastClientEvent and TEST.lastClientEvent.name == "referral:profileData",
    TEST.lastClientEvent and TEST.lastClientEvent.name)

--  sqlite path does not crash (records the statements)
ReferralConfig.storage.backend = "sqlite"
ReferralServer.storage.init()
check("sqlite connect attempted", #TEST.db.connects >= 1, #TEST.db.connects)
check("schema statements executed", #TEST.db.execs >= 4, #TEST.db.execs)

print(string.format("\n  %d checks, %d failures", checks, #failures))
if #failures > 0 then error("server tests failed: " .. table.concat(failures, ", ")) end
"""

CLIENT_TESTS = r"""
--============================================================--
--  CLIENT TESTS
--============================================================--
local failures, checks = {}, 0
local function check(label, condition, detail)
    checks = checks + 1
    if condition then
        print(string.format("  PASS  %s", label))
    else
        print(string.format("  FAIL  %s %s", label, detail and ("-> " .. tostring(detail)) or ""))
        failures[#failures + 1] = label
    end
end

--  every NovaUI component the mock created, in creation order
local function elementsOf(kind)
    local out = {}
    for _, comp in pairs(TEST.elements) do
        if comp.type == kind then out[#out + 1] = comp end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function byName(name)
    for _, comp in pairs(TEST.elements) do
        if comp.props and comp.props.name == name then return comp end
    end
    return nil
end

print("== client ==")
ReferralConfig.debug = false

--  start the resource (client.lua attached onClientResourceStart)
triggerEvent("onClientResourceStart", resourceRoot)
check("client initialised", ReferralClient.initialized == true)
check("F6 bound", TEST.keys["F6"] ~= nil)
check("command bound", TEST.commands["referral"] ~= nil)

--  MTA gives every resource its own VM, so the NovaUI global is unreachable:
--  the bridge MUST find the library through its exports, not through a global
check("global NovaUI is nil (own VM)", NovaUI == nil, tostring(NovaUI))
check("novaCreate is exported", type(exports.NovaUI.novaCreate) == "function")
check("bridge resolves NovaUI via exports",
    ReferralClient.novaui.resolve() ~= nil, tostring(ReferralClient.novaui.name()))
check("resolved through exports", (ReferralClient.novaui.name() or ""):find("exports", 1, true) ~= nil,
    tostring(ReferralClient.novaui.name()))

--  open the window
local opened = ReferralClient.main.open()
check("window opens", opened == true)
check("window created", ReferralClient.main.window ~= nil)
check("cursor shown", TEST.cursor == true)
local firstWindow = ReferralClient.main.window
check("loading state shown", ReferralClient.main.statusKind == "loading",
    tostring(ReferralClient.main.statusKind))
check("data requested", TEST.lastServerEvent and TEST.lastServerEvent.name == "referral:requestProfile",
    TEST.lastServerEvent and TEST.lastServerEvent.name)

--  no duplicate window on a second open
ReferralClient.main.open()
check("no duplicate window", ReferralClient.main.window == firstWindow)
check("window count is 1", #elementsOf("window") == 1, #elementsOf("window"))
check("handle was flushed into a real component", firstWindow.id ~= nil, tostring(firstWindow.id))

--  feed a real shaped payload
local payload = {
    ok = true,
    code = "RAOUF-X72K",
    usedCode = "",
    canUseCode = true,
    generatedAt = 1000,
    requirements = { level = 3, playtimeMinutes = 60 },
    stats = {
        total = 24, pending = 4, active = 2, completed = 18, rejected = 0,
        earned = 185000, pendingRewards = 25000, totalRewards = 210000,
        conversion = 75, avgLevel = 6.4, avgPlaytime = 320,
        milestone = { completed = 18, target = 25, remaining = 7, percent = 72,
                      reward = 150000, next = { count = 25, reward = 150000 } },
    },
    referrals = {},
    rewards = {
        { id = 1, referralId = 1, referral = "sara", type = "referral", typeLabel = "مكافاة احالة",
          amount = 5000, amountText = "5,000 $", status = "paid", statusLabel = "مستلمة",
          statusColor = "#4ADE80", date = "2026/09/20", relative = "قبل 9 يوم", claimable = false },
        { id = 2, referralId = 2, referral = "هدف مرحلي", type = "milestone",
          typeLabel = "مكافاة مرحلية", amount = 25000, amountText = "25,000 $",
          status = "pending", statusLabel = "معلقة", statusColor = "#FBBF24",
          date = "2026/09/21", relative = "قبل 8 يوم", claimable = true },
    },
    series = {
        daily = { { label = "23/09", value = 1 }, { label = "24/09", value = 3 },
                  { label = "25/09", value = 2 }, { label = "26/09", value = 4 },
                  { label = "27/09", value = 5 }, { label = "28/09", value = 3 },
                  { label = "29/09", value = 6 } },
        status = { { label = "نشط", value = 2, color = "#4ADE80" },
                   { label = "قيد التحقق", value = 4, color = "#FBBF24" },
                   { label = "مكتمل", value = 18, color = "#60A5FA" } },
        rewards = { { label = "23/09", value = 5000 }, { label = "24/09", value = 15000 },
                    { label = "25/09", value = 0 }, { label = "26/09", value = 25000 },
                    { label = "27/09", value = 0 }, { label = "28/09", value = 10000 },
                    { label = "29/09", value = 5000 } },
    },
}
for i = 1, 24 do
    payload.referrals[#payload.referrals + 1] = {
        id = i, player = "player" .. i, account = "acc" .. i, level = 3 + (i % 7),
        playtime = 60 * i, playtimeText = (i) .. " س",
        registeredAt = 1700000000 + i * 3600,
        registeredText = "2026/09/" .. string.format("%02d", (i % 28) + 1),
        relativeText = "قبل يوم",
        status = (i % 4 == 0 and "completed") or (i % 4 == 1 and "active")
            or (i % 4 == 2 and "pending") or "rejected",
        statusLabel = "حالة", statusColor = "#4ADE80", statusBadge = "success",
        reward = 5000, rewardText = "5,000 $",
        progress = { done = 2, total = 2, percent = 100, items = {} },
        timeline = { { label = "تم استخدام الكود", done = true },
                     { label = "تم التسجيل", done = true },
                     { label = "المستوى", done = true },
                     { label = "وقت اللعب", done = true },
                     { label = "المكافاة مكتملة", done = true } },
    }
end

triggerClientEvent(localPlayer, "referral:profileData", resourceRoot, payload)

check("data stored", ReferralClient.state.get() ~= nil)
check("loading cleared", ReferralClient.main.statusKind == nil,
    tostring(ReferralClient.main.statusKind))

--  dashboard bindings
local heroCode = byName("heroCode")
check("hero code rendered", heroCode and heroCode.text == "RAOUF-X72K", heroCode and heroCode.text)
local nextTitle = byName("nextRewardTitle")
check("next reward text", nextTitle and nextTitle.text:find("18 من 25", 1, true) ~= nil,
    nextTitle and nextTitle.text)
local progress = byName("nextRewardProgress")
check("progress value", progress and progress.value == 72, progress and progress.value)
local hint = byName("nextRewardHint")
check("next reward hint", hint and hint.text:find("150,000", 1, true) ~= nil, hint and hint.text)
check("kpi cards created", #elementsOf("statscard") == 4, #elementsOf("statscard"))

--  recent referrals list rows
local recentList = byName("recentList")
check("recent list filled", recentList and recentList.rows and #recentList.rows == 6,
    recentList and recentList.rows and #recentList.rows)

--  navigation
ReferralClient.navigation.show("referrals")
check("referrals page active", ReferralClient.navigation.current() == "referrals")
local referralsPanel = byName("pageReferrals")
check("referrals page visible", referralsPanel and referralsPanel.visible == true)
local dashboardPanel = byName("pageDashboard")
check("dashboard hidden", dashboardPanel and dashboardPanel.visible == false)
local breadcrumb = byName("referralBreadcrumb")
check("breadcrumb updated", breadcrumb and breadcrumb.props.items[2].text == "الاحالات",
    breadcrumb and breadcrumb.props.items[2].text)

--  table rows + search + filter
local referralsTable = byName("referralsTable")
check("table filled", referralsTable and referralsTable.rows and #referralsTable.rows == 24,
    referralsTable and #referralsTable.rows)
ReferralClient.state.setQuery("player3")
check("search filters", #ReferralClient.state.filteredReferrals() == 1,
    #ReferralClient.state.filteredReferrals())
ReferralClient.state.setQuery("player1")
check("search matches a prefix", #ReferralClient.state.filteredReferrals() == 11,
    #ReferralClient.state.filteredReferrals())
ReferralClient.state.setQuery("")
ReferralClient.state.setStatusFilter("completed")
check("status filter", #ReferralClient.state.filteredReferrals() == 6,
    #ReferralClient.state.filteredReferrals())
ReferralClient.state.setStatusFilter("all")
ReferralClient.state.setSort("level", true)
local sorted = ReferralClient.state.filteredReferrals()
check("sorting works", sorted[1].level >= sorted[#sorted].level, sorted[1].level)

--  empty state
ReferralClient.state.setQuery("zzzz-nothing")
check("empty state visible", byName("emptyBlock") ~= nil)
ReferralClient.state.setQuery("")

--  row selection opens the detail dialog
local detail = ReferralClient.dialogs.openDetail(sorted[1])
check("detail dialog created", detail ~= nil)
check("detail dialog flushed", detail.id ~= nil, tostring(detail.id))
check("timeline created", #elementsOf("timeline") >= 1)
local detailId = detail.id
ReferralClient.dialogs.close("detail")
check("detail dialog destroyed", detailId ~= nil and TEST.wasDestroyed(detailId),
    tostring(detailId))
check("dialog marked dead", detail.alive == false)

--  share dialog
local share = ReferralClient.dialogs.openShare()
check("share dialog created", share ~= nil)
local copyMessage = byName("shareCopyMessage")
check("copy button created", copyMessage ~= nil)
TEST.click(copyMessage.id)
check("invite message copied", TEST.clips[#TEST.clips]:find("RAOUF-X72K", 1, true) ~= nil,
    TEST.clips[#TEST.clips])
check("copy sound played", #TEST.sounds >= 1)
ReferralClient.dialogs.close("share")

--  apply code dialog
local apply = ReferralClient.dialogs.openApplyCode()
check("apply dialog created", apply ~= nil)
local edit = byName("applyEdit")
check("edit created", edit ~= nil)
edit.value = "RAOUF-X72K"
TEST.click(byName("applySubmit").id)
check("apply code sent to server",
    TEST.lastServerEvent.name == "referral:applyCode" and TEST.lastServerEvent.args[1] == "RAOUF-X72K",
    TEST.lastServerEvent.args and TEST.lastServerEvent.args[1])
ReferralClient.dialogs.close("apply")

--  rewards page
ReferralClient.navigation.show("rewards")
local rewardsPanel = byName("pageRewards")
check("rewards page visible", rewardsPanel and rewardsPanel.visible == true)
check("reward kpi cards built", #elementsOf("statscard") == 7, #elementsOf("statscard"))
local rewardsTable = byName("rewardsTable")
check("rewards table filled", rewardsTable and #rewardsTable.rows == 2,
    rewardsTable and #rewardsTable.rows)
TEST.click(byName("rewardsClaim").id)
check("claim sent", TEST.lastServerEvent.name == "referral:claimReward",
    TEST.lastServerEvent.name)

--  statistics page
ReferralClient.navigation.show("statistics")
check("area chart data", byName("chartArea").data ~= nil
    and #byName("chartArea").data == 7)
check("donut chart data", byName("chartDonut").data ~= nil
    and #byName("chartDonut").data == 3)
check("bar chart data", byName("chartBar").data ~= nil
    and #byName("chartBar").data == 7)

--  conditions page
ReferralClient.navigation.show("conditions")
check("stepper created", byName("conditionsStepper") ~= nil)
check("timeline created", byName("conditionsTimeline") ~= nil)
check("accordion created", byName("conditionsAccordion") ~= nil)

--  back to dashboard
ReferralClient.navigation.show("dashboard")
check("dashboard visible again", byName("pageDashboard").visible == true)
check("dashboard data still bound", byName("heroCode").text == "RAOUF-X72K")

--  error state
triggerClientEvent(localPlayer, "referral:profileData", resourceRoot,
    { ok = false, errorKey = "no_data", message = "تعذر تحميل بيانات الاحالة" })
check("error state shown", ReferralClient.main.statusKind == "error",
    tostring(ReferralClient.main.statusKind))

--  recovery
triggerClientEvent(localPlayer, "referral:profileData", resourceRoot, payload)
check("error state cleared", ReferralClient.main.statusKind == nil)

--  close / reopen
ReferralClient.main.close()
check("window hidden", firstWindow.id ~= nil and TEST.visible(firstWindow.id) == false,
    tostring(firstWindow.id))
check("cursor hidden", TEST.cursor == false)
check("dialogs closed", ReferralClient.dialogs.isOpen("share") == false)
ReferralClient.main.open()
check("reopen works", ReferralClient.main.visible == true)
check("still one window", #elementsOf("window") == 1, #elementsOf("window"))

--  command handler
TEST.commands["referral"]("referral", "close")
check("command closes", ReferralClient.main.visible == false)
TEST.commands["referral"]("referral", "")
check("command opens", ReferralClient.main.visible == true)

--  keybind
TEST.keys["F6"]()
check("F6 toggles", ReferralClient.main.visible == false)
TEST.keys["F6"]()
check("F6 toggles back", ReferralClient.main.visible == true)

--  exports
check("export getReferralCode", ReferralClient.main.getReferralCode() == "RAOUF-X72K")
check("export getReferralStats", ReferralClient.main.getReferralStats().total == 24)

--  notification goes through the real export, never through a global
local notificationsBefore = #TEST.notifications
ReferralClient.novaui.notify({ type = "success", title = "تم النسخ", message = "تم نسخ كود الاحالة بنجاح" })
check("notification fired", #TEST.notifications == notificationsBefore + 1,
    #TEST.notifications)

--============================================================--
--  NOVAUI BRIDGE CONTRACT
--  These are the checks that would have caught the user's bug.
--============================================================--
print("== novaui bridge ==")

--  REGRESSION 1 (the user's actual failure):
--  MTA's exports table returns a FUNCTION for ANY key, even one the resource
--  never declared. Indexing it therefore proves nothing, and calling the stub
--  raises "call: failed to call 'NovaUI:create' [string \"?\"]" - which is
--  exactly the error the user saw. The bridge must ask
--  getResourceExportedFunctions() what is really exported.
ReferralClient.novaui.reset()
check("exports table hands back a stub for undeclared keys",
    type(exports.NovaUI.novaCreate) == "function")
check("bridge does not trust the exports table blindly",
    (function()
        --  a resource that exports nothing NovaUI shaped must not resolve
        local saved = getResourceExportedFunctions
        getResourceExportedFunctions = function() return { "someOtherExport" } end
        local ok = ReferralClient.novaui.resolve(true)
        getResourceExportedFunctions = saved
        ReferralClient.novaui.reset()
        return ok == nil
    end)(), "resolved a resource that exports nothing NovaUI shaped")

--  novaCreate returns an ID, not a component - the bridge must wrap it
ReferralClient.novaui.reset()
local window = ReferralClient.novaui.create("window", { title = "probe" })
check("create returns a handle", window ~= nil and window.id == nil,
    window and tostring(window.id))
ReferralClient.novaui.flush()
check("handle flushed into a real id", window.id ~= nil, tostring(window.id))
check("window really exists in NovaUI", TEST.component(window.id) ~= nil)
check("handle reports its kind", window.kind == "window", window.kind)

--  children are created against the parent id
local panel = ReferralClient.novaui.child(window, "panel", { name = "probePanel" })
ReferralClient.novaui.flush()
check("child created", panel ~= nil and panel.id ~= nil, panel and tostring(panel.id))
check("child attached to its parent",
    (function()
        for _, childId in ipairs(TEST.children(window.id)) do
            if childId == panel.id then return true end
        end
        return false
    end)(), tostring(panel.id))

--  events registered before the flush reach NovaUI as bound props
ReferralClient.novaui.reset()
local clicked = 0
local btn = ReferralClient.novaui.create("button", { text = "اضغط" })
ReferralClient.novaui.on(btn, "click", function() clicked = clicked + 1 end)
ReferralClient.novaui.flush()
check("click prop bound by NovaUI", TEST.props(btn.id).onClick ~= nil)
TEST.click(btn.id)
check("click handler fired", clicked == 1, tostring(clicked))

--  an event NovaUI does NOT bind from props still works through novaOn
ReferralClient.novaui.reset()
local selected = nil
local row = ReferralClient.novaui.create("table", { name = "probeTable" })
ReferralClient.novaui.on(row, "select", function(r) selected = r end)
ReferralClient.novaui.flush()
check("select bound through novaOn", TEST.emit(row.id, "select", { id = 7 }))
check("select handler fired", selected ~= nil and selected.id == 7, tostring(selected))

--  update / patch
ReferralClient.novaui.patch(row, { rows = { { id = 1 } } })
ReferralClient.novaui.flush()
check("patch applied", TEST.props(row.id).rows ~= nil and #TEST.props(row.id).rows == 1,
    TEST.props(row.id).rows and #TEST.props(row.id).rows)

--  setVisible goes through the dedicated export
ReferralClient.novaui.call(panel, "setVisible", false)
check("setVisible applied", TEST.visible(panel.id) == false)

--  setter methods with no dedicated export fall back to novaCall
ReferralClient.novaui.call(row, "setRows", { { id = 1 }, { id = 2 } })
check("setRows applied through novaCall", #TEST.props(row.id).data == 2,
    TEST.props(row.id).data and #TEST.props(row.id).data)

--  a missing NovaUI must degrade, never throw
ReferralClient.novaui.reset()
check("missing NovaUI is contained",
    (function()
        local savedResolve = getResourceFromName
        getResourceFromName = function() return nil end
        local savedResources = getResources
        getResources = function() return {} end
        local ok, err = pcall(function()
            return ReferralClient.novaui.create("window", {})
        end)
        getResourceFromName = savedResolve
        getResources = savedResources
        ReferralClient.novaui.reset()
        return ok == true and err == nil
    end)(), tostring(err))

--  the diagnostic must name the real exported functions
local diag = ReferralClient.novaui.diagnose()
check("diagnostic lists real exports",
    diag:find("novaCreate", 1, true) ~= nil and diag:find("novaOn", 1, true) ~= nil,
    diag:sub(1, 240))
check("diagnostic shows probe return values",
    diag:find("probe results", 1, true) ~= nil, diag:sub(1, 200))

print(string.format("\n  %d checks, %d failures", checks, #failures))
if #failures > 0 then error("client tests failed: " .. table.concat(failures, ", ")) end
"""


def load(runtime, relative):
    path = os.path.join(RESOURCE, relative)
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    runtime.execute(source)
    return path


def main():
    runtime = LuaRuntime()
    runtime.execute(MTA_STUBS)
    runtime.execute(NOVAUI_MOCK)

    # shared
    for name in ("config.lua", "shared.lua"):
        load(runtime, name)

    # server
    for name in SERVER_ORDER:
        load(runtime, name)
    runtime.execute(SERVER_TESTS)

    # fresh runtime for the client side (separate Lua state like MTA does)
    runtime2 = LuaRuntime()
    runtime2.execute(MTA_STUBS)
    runtime2.execute(NOVAUI_MOCK)
    for name in ("config.lua", "shared.lua"):
        load(runtime2, name)
    for name in CLIENT_ORDER:
        load(runtime2, name)
    runtime2.execute(CLIENT_TESTS)

    print("\nALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
