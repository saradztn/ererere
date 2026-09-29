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
--  NOVAUI v3.0.0 MOCK
--  Implements the documented API surface only. Unknown methods
--  return nil so the resource's defensive paths are exercised.
--============================================================--
TEST.elements = {}
TEST.notifications = {}
TEST.elementCount = 0

local function applySetter(el, key, value)
    local setter = "set" .. key:sub(1, 1):upper() .. key:sub(2)
    if el[setter] then
        el[setter](el, value)
        return true
    end
    return false
end

local ElementMeta = {}
ElementMeta.__index = function(t, key)
    local value = rawget(ElementMeta, key)
    if value ~= nil then return value end
    return nil
end

local function newElement(kind, props, parent)
    TEST.elementCount = TEST.elementCount + 1
    local el = {
        __element = true, kind = kind, props = props or {},
        children = {}, listeners = {}, parent = parent,
        visible = props and props.visible ~= false,
        alpha = 255, text = props and props.text, value = props and props.value,
        enabled = true, x = props and props.x, y = props and props.y,
        width = props and props.width, height = props and props.height,
        id = TEST.elementCount,
    }
    setmetatable(el, { __index = ElementMeta })
    TEST.elements[#TEST.elements + 1] = el
    if parent then parent.children[#parent.children + 1] = el end
    return el
end

function ElementMeta:create(kind, props)
    return newElement(kind, props, self)
end
function ElementMeta:addChild(child) self.children[#self.children + 1] = child return self end
function ElementMeta:removeChild(child)
    for i, c in ipairs(self.children) do
        if c == child then table.remove(self.children, i) break end
    end
    return self
end
function ElementMeta:clearChildren() self.children = {} return self end
function ElementMeta:setPosition(x, y) self.x, self.y = x, y return self end
function ElementMeta:getPosition() return self.x, self.y end
function ElementMeta:getScreenPosition() return 0, 0 end
function ElementMeta:setSize(w, h) self.width, self.height = w, h return self end
function ElementMeta:getSize() return self.width, self.height end
function ElementMeta:setVisible(v) self.visible = v and true or false return self end
function ElementMeta:show() self.visible = true return self end
function ElementMeta:hide() self.visible = false return self end
function ElementMeta:toggle() self.visible = not self.visible return self end
function ElementMeta:isVisible() return self.visible end
function ElementMeta:setEnabled(v) self.enabled = v and true or false return self end
function ElementMeta:isEnabled() return self.enabled end
function ElementMeta:setAlpha(a) self.alpha = a return self end
function ElementMeta:getAlpha() return self.alpha end
function ElementMeta:setText(t) self.text = t return self end
function ElementMeta:getText() return self.text end
function ElementMeta:setValue(v) self.value = v return self end
function ElementMeta:getValue() return self.value end
function ElementMeta:setTooltip(t) self.tooltip = t return self end
function ElementMeta:focus() self.focused = true return self end
function ElementMeta:blur() self.focused = false return self end
function ElementMeta:bringToFront() self.z = 99 return self end
function ElementMeta:sendToBack() self.z = 0 return self end
function ElementMeta:animate(props) self.animated = props return self end
function ElementMeta:update(props)
    if type(props) ~= "table" then return self end
    for key, value in pairs(props) do
        self.props[key] = value
        applySetter(self, key, value)
    end
    return self
end
function ElementMeta:destroy() self.destroyed = true self.visible = false return self end
function ElementMeta:on(name, fn) self.listeners[name] = self.listeners[name] or {} self.listeners[name][#self.listeners[name] + 1] = fn return self end
function ElementMeta:once(name, fn) self.listeners[name] = self.listeners[name] or {} self.listeners[name][#self.listeners[name] + 1] = fn return self end
function ElementMeta:off(name, fn)
    if not self.listeners[name] then return self end
    for i, f in ipairs(self.listeners[name]) do
        if f == fn then table.remove(self.listeners[name], i) break end
    end
    return self
end
function ElementMeta:removeAllListeners() self.listeners = {} return self end
function ElementMeta:fire(name, ...)
    if not self.listeners[name] then return end
    for _, fn in ipairs(self.listeners[name]) do
        fn(self, ...)
    end
end
function ElementMeta:setRows(rows) self.rows = rows return self end
function ElementMeta:setData(data) self.data = data return self end
function ElementMeta:setItems(items) self.items = items return self end
function ElementMeta:setFilter(q) self.filter = q return self end
function ElementMeta:setSort(key, desc) self.sortKey, self.sortDesc = key, desc return self end

--  NovaUI v3 exposes the factory as a METHOD (self first), which is what
--  MTA reports as 'NovaUI:create' when a call fails.
NovaUI = {}
function NovaUI:create(kind, props)
    --  the real NovaUI v3 factory is a METHOD: calling it dot style passes
    --  the component type as `self` and blows up inside the library.
    assert(type(self) == "table", "create must be called as NovaUI:create(kind, props)")
    assert(type(kind) == "string", "create expects a component type string")
    return newElement(kind, props, nil)
end
function NovaUI:notify(props) TEST.notifications[#TEST.notifications + 1] = props end
function NovaUI:animate(el, props) if el then el.animated = props end end
function NovaUI:setFont(path) TEST.font = path end
function NovaUI:useFont(path) TEST.font = TEST.font or path end
function NovaUI:helperProbe() return "ok" end

function TEST.findElements(kind)
    local out = {}
    for _, el in ipairs(TEST.elements) do
        if el.kind == kind then out[#out + 1] = el end
    end
    return out
end
function TEST.findByName(name)
    for _, el in ipairs(TEST.elements) do
        if el.props and el.props.name == name then return el end
    end
    return nil
end
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

print("== client ==")
ReferralConfig.debug = false

--  start the resource (client.lua attached onClientResourceStart)
triggerEvent("onClientResourceStart", resourceRoot)
check("client initialised", ReferralClient.initialized == true)
check("F6 bound", TEST.keys["F6"] ~= nil)
check("command bound", TEST.commands["referral"] ~= nil)

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
check("window count is 1", #TEST.findElements("window") == 1, #TEST.findElements("window"))

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
local heroCode = TEST.findByName("heroCode")
check("hero code rendered", heroCode and heroCode.text == "RAOUF-X72K", heroCode and heroCode.text)
local nextTitle = TEST.findByName("nextRewardTitle")
check("next reward text", nextTitle and nextTitle.text:find("18 من 25", 1, true) ~= nil,
    nextTitle and nextTitle.text)
local progress = TEST.findByName("nextRewardProgress")
check("progress value", progress and progress.value == 72, progress and progress.value)
local hint = TEST.findByName("nextRewardHint")
check("next reward hint", hint and hint.text:find("150,000", 1, true) ~= nil, hint and hint.text)
check("kpi cards created", #TEST.findElements("statscard") == 4, #TEST.findElements("statscard"))

--  recent referrals list rows
local recentList = TEST.findByName("recentList")
check("recent list filled", recentList and recentList.rows and #recentList.rows == 6,
    recentList and recentList.rows and #recentList.rows)

--  navigation
ReferralClient.navigation.show("referrals")
check("referrals page active", ReferralClient.navigation.current() == "referrals")
local referralsPanel = TEST.findByName("pageReferrals")
check("referrals page visible", referralsPanel and referralsPanel.visible == true)
local dashboardPanel = TEST.findByName("pageDashboard")
check("dashboard hidden", dashboardPanel and dashboardPanel.visible == false)
local breadcrumb = TEST.findByName("referralBreadcrumb")
check("breadcrumb updated", breadcrumb and breadcrumb.props.items[2].text == "الاحالات",
    breadcrumb and breadcrumb.props.items[2].text)

--  table rows + search + filter
local referralsTable = TEST.findByName("referralsTable")
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
check("empty state visible", TEST.findByName("emptyBlock") ~= nil)
ReferralClient.state.setQuery("")

--  row selection opens the detail dialog
local detail = ReferralClient.dialogs.openDetail(sorted[1])
check("detail dialog created", detail ~= nil)
check("timeline created", #TEST.findElements("timeline") >= 1)
ReferralClient.dialogs.close("detail")
check("detail dialog destroyed", detail.destroyed == true)

--  share dialog
local share = ReferralClient.dialogs.openShare()
check("share dialog created", share ~= nil)
check("clipboard message", TEST.clips[#TEST.clips] == nil)
local copyMessage = TEST.findByName("shareCopyMessage")
copyMessage:fire("click")
check("invite message copied", TEST.clips[#TEST.clips]:find("RAOUF-X72K", 1, true) ~= nil,
    TEST.clips[#TEST.clips])
check("copy sound played", #TEST.sounds >= 1)
ReferralClient.dialogs.close("share")

--  apply code dialog
local apply = ReferralClient.dialogs.openApplyCode()
check("apply dialog created", apply ~= nil)
local edit = TEST.findByName("applyEdit")
check("edit focused", edit and edit.focused == true)
edit:setValue("RAOUF-X72K")
TEST.findByName("applySubmit"):fire("click")
check("apply code sent to server",
    TEST.lastServerEvent.name == "referral:applyCode" and TEST.lastServerEvent.args[1] == "RAOUF-X72K",
    TEST.lastServerEvent.args and TEST.lastServerEvent.args[1])
ReferralClient.dialogs.close("apply")

--  rewards page
ReferralClient.navigation.show("rewards")
local rewardsPanel = TEST.findByName("pageRewards")
check("rewards page visible", rewardsPanel and rewardsPanel.visible == true)
check("reward kpi cards built", #TEST.findElements("statscard") == 7, #TEST.findElements("statscard"))
local rewardsTable = TEST.findByName("rewardsTable")
check("rewards table filled", rewardsTable and #rewardsTable.rows == 2,
    rewardsTable and #rewardsTable.rows)
TEST.findByName("rewardsClaim"):fire("click")
check("claim sent", TEST.lastServerEvent.name == "referral:claimReward",
    TEST.lastServerEvent.name)

--  statistics page
ReferralClient.navigation.show("statistics")
check("area chart data", TEST.findByName("chartArea").data ~= nil
    and #TEST.findByName("chartArea").data == 7)
check("donut chart data", TEST.findByName("chartDonut").data ~= nil
    and #TEST.findByName("chartDonut").data == 3)
check("bar chart data", TEST.findByName("chartBar").data ~= nil
    and #TEST.findByName("chartBar").data == 7)

--  conditions page
ReferralClient.navigation.show("conditions")
check("stepper created", TEST.findByName("conditionsStepper") ~= nil)
check("timeline created", TEST.findByName("conditionsTimeline") ~= nil)
check("accordion created", TEST.findByName("conditionsAccordion") ~= nil)

--  back to dashboard
ReferralClient.navigation.show("dashboard")
check("dashboard visible again", TEST.findByName("pageDashboard").visible == true)
check("dashboard data still bound", TEST.findByName("heroCode").text == "RAOUF-X72K")

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
check("window hidden", ReferralClient.main.window.visible == false)
check("cursor hidden", TEST.cursor == false)
check("dialogs closed", ReferralClient.dialogs.isOpen("share") == false)
ReferralClient.main.open()
check("reopen works", ReferralClient.main.visible == true)
check("still one window", #TEST.findElements("window") == 1, #TEST.findElements("window"))

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

--  notification helper (method style, like the real NovaUI v3)
local notificationsBefore = #TEST.notifications
NovaUI:notify({ type = "success", title = "تم النسخ", message = "تم نسخ كود الاحالة بنجاح" })
check("notification fired", #TEST.notifications == notificationsBefore + 1,
    #TEST.notifications)

--  REGRESSION: the user's server reported
--  "call: failed to call 'NovaUI:create'" because the bridge called the
--  factory dot style while NovaUI v3 defines it as a method.
ReferralClient.novaui.reset()
check("method style factory works (user bug)",
    ReferralClient.novaui.create("window", { title = "probe" }) ~= nil)
check("factory style detected as method",
    (function()
        local ui = ReferralClient.novaui.get()
        local ok = pcall(ui.create, ui, "label", {})
        return ok
    end)())

--  the bridge must survive BOTH factory conventions
ReferralClient.novaui.reset()
check("bridge auto detects method style",
    ReferralClient.novaui.create("label", { text = "probe" }) ~= nil)
ReferralClient.novaui.reset()
local originalCreate = NovaUI.create
NovaUI.create = function(kind, props) return originalCreate(NovaUI, kind, props) end
check("bridge falls back to function style",
    ReferralClient.novaui.create("label", { text = "probe" }) ~= nil)
NovaUI.create = originalCreate
ReferralClient.novaui.reset()

--  a build that only accepts a single props table must still work
ReferralClient.novaui.reset()
local savedCreate = NovaUI.create
NovaUI.create = function(self, a, b)
    if type(a) == "table" then
        local nova = (type(self) == "table") and self or NovaUI
        return savedCreate(nova, a.type or "label", a)
    end
    error("single table convention only")
end
check("single table convention works",
    ReferralClient.novaui.create("window", { title = "probe" }) ~= nil)
check("convention remembered",
    ReferralClient.novaui.create("panel", {}) ~= nil)
NovaUI.create = savedCreate
ReferralClient.novaui.reset()

--  a build that computes its own z order from props.level and dies when the
--  caller omits it ("attempt to perform arithmetic on field 'level'")
ReferralClient.novaui.reset()
local layeringCreate = NovaUI.create
NovaUI.create = function(self, kind, props)
    assert(type(self) == "table", "must be called method style")
    if type(props) ~= "table" or props.level == nil then
        error("attempt to perform arithmetic on field 'level' (a nil value)")
    end
    return layeringCreate(self, kind, props)
end
local layeringElement = ReferralClient.novaui.create("window", { title = "probe" })
check("build missing props.level still gets a window",
    layeringElement ~= nil and layeringElement.kind == "window",
    ReferralClient.novaui.diagnose():sub(1, 240))
local diag2 = ReferralClient.novaui.diagnose()
check("layering fallback is reported",
    diag2:find("+ layering props", 1, true) ~= nil, diag2:sub(1, 200))
NovaUI.create = layeringCreate
ReferralClient.novaui.reset()

--  a factory that always returns nil must fail loudly but never crash
ReferralClient.novaui.reset()
NovaUI.create = function() return nil end
local logBefore = #TEST.log
local nilResult = ReferralClient.novaui.create("window", {})
check("nil returning factory is contained", nilResult == nil)
local logged = ""
for i = logBefore + 1, #TEST.log do logged = logged .. tostring(TEST.log[i]) end
check("failure is logged with the reason",
    logged:find("could not create window", 1, true) ~= nil, logged:sub(1, 160))
local diag = ReferralClient.novaui.diagnose()
check("diagnostic shows probe return values",
    diag:find("probe results", 1, true) ~= nil and diag:find("-> ok nil", 1, true) ~= nil,
    diag:sub(1, 240))
check("diagnostic lists exported functions",
    diag:find("exports=", 1, true) ~= nil)
NovaUI.create = savedCreate
ReferralClient.novaui.reset()

--  a broken factory must not crash the resource
local broken = { create = function() error("boom") end }
ReferralClient.novaui.reset()
check("broken factory is contained",
    (function()
        local saved = NovaUI
        NovaUI = broken
        local ui = ReferralClient.novaui.resolve(true)
        local ok = pcall(function() return ReferralClient.novaui.create("window", {}) end)
        NovaUI = saved
        ReferralClient.novaui.reset()
        return ok == true
    end)())
check("diagnostic reports the failure reason",
    type(ReferralClient.novaui.diagnose()) == "string")

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
