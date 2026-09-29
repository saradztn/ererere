--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Server / Bootstrap
--========================================================--
--  Wires storage, referral logic, rewards and the network
--  layer together. Also owns the playtime / level tracking.
--========================================================--

ReferralServer = ReferralServer or {}
local M = {}
ReferralServer.main = M

local S = ReferralServer.storage
local V = ReferralServer.validation
local R = ReferralServer.referrals
local W = ReferralServer.rewards

--  runtime tracking state (never persisted, rebuilt on start)
local playtime = {}   -- player -> { minutes, lastTick }
local levels   = {}   -- player -> level

--============================================================--
--  HELPERS
--============================================================--
function ReferralServer.sendProfile(player)
    if not isElement(player) then return false end
    local payload = R.buildProfile(player)
    if not payload then
        triggerClientEvent(player, Referral.events.profileData, resourceRoot,
            { ok = false, errorKey = "no_data", message = ReferralServer.errors.no_data })
        return false
    end
    triggerClientEvent(player, Referral.events.profileData, resourceRoot, payload)
    return true
end

function ReferralServer.notifyPlayer(player, props)
    if not isElement(player) then return end
    triggerClientEvent(player, Referral.events.notify, resourceRoot, props)
end

--============================================================--
--  LEVEL / PLAYTIME SOURCES
--============================================================--
function M.readLevel(player)
    local cfg = ReferralConfig.tracking.level
    local level = nil

    if cfg.source == "export" and cfg.resource ~= "" and cfg.functionName ~= "" then
        local ok, exp = pcall(function() return exports[cfg.resource] end)
        if ok and type(exp) == "table" and type(exp[cfg.functionName]) == "function" then
            local okCall, value = pcall(exp[cfg.functionName], player)
            if okCall and tonumber(value) then level = math.floor(tonumber(value)) end
        end
    elseif cfg.source == "elementData" and cfg.elementData ~= "" then
        local value = getElementData(player, cfg.elementData)
        if tonumber(value) then level = math.floor(tonumber(value)) end
    end

    if not level or level <= 0 then level = cfg.default or 1 end
    return level
end

---Store the level of a player and re-evaluate his referral.
function M.setLevel(player, level)
    if not isElement(player) then return false end
    level = math.max(1, math.floor(tonumber(level) or 1))
    levels[player] = level

    local row = S.ensurePlayer(player)
    if not row then return false end
    if (tonumber(row.level) or 0) ~= level then
        S.updatePlayer(row.id, { level = level })
        R.evaluate(player, true)
    end
    return true
end

function M.addPlaytime(player, minutes)
    if not isElement(player) then return false end
    minutes = math.floor(tonumber(minutes) or 0)
    if minutes <= 0 then return false end

    local row = S.ensurePlayer(player)
    if not row then return false end
    S.updatePlayer(row.id, {
        playtime_minutes = (tonumber(row.playtime_minutes) or 0) + minutes,
    })
    R.evaluate(player, true)
    return true
end

--============================================================--
--  PLAYTIME TIMER
--  Accumulates real playtime and flushes whole minutes to the
--  database, then re-checks referral requirements.
--============================================================--
local function flushPlaytime()
    if not ReferralConfig.tracking.playtime then return end
    local tick = getTickCount()

    for _, player in ipairs(getElementsByType("player")) do
        local data = playtime[player]
        if data then
            local delta = tick - data.last
            data.last = tick
            --  ignore absurd deltas (server lag, resource restart)
            if delta > 0 and delta < 600000 then
                data.minutes = data.minutes + (delta / 60000)
                local whole = math.floor(data.minutes)
                if whole >= 1 then
                    data.minutes = data.minutes - whole
                    local row = S.ensurePlayer(player)
                    if row then
                        S.updatePlayer(row.id, {
                            playtime_minutes = (tonumber(row.playtime_minutes) or 0) + whole,
                        })
                        R.evaluate(player, true)
                    end
                end
            end
        end
    end
end

--============================================================--
--  NETWORK HANDLERS
--============================================================--
local function onRequestProfile()
    if not ReferralConfig.enabled then
        triggerClientEvent(source, Referral.events.profileData, resourceRoot, {
            ok = false, errorKey = "disabled", message = ReferralServer.errors.disabled,
        })
        return
    end
    local ok, err = pcall(function() ReferralServer.sendProfile(source) end)
    if not ok then
        Referral.warn("sendProfile failed:", tostring(err))
        triggerClientEvent(source, Referral.events.profileData, resourceRoot, {
            ok = false, errorKey = "no_data", message = ReferralServer.errors.no_data,
        })
    end
end

local function onApplyCode(code)
    if not ReferralConfig.enabled then
        triggerClientEvent(source, Referral.events.applyResult, resourceRoot, {
            ok = false, errorKey = "disabled", message = ReferralServer.errors.disabled,
        })
        return
    end

    local result
    local ok, err = pcall(function() result = R.applyCode(source, code) end)
    if not ok then
        Referral.warn("applyCode failed:", tostring(err))
        result = {
            ok = false, errorKey = "no_data", message = ReferralServer.errors.no_data,
        }
    end
    triggerClientEvent(source, Referral.events.applyResult, resourceRoot, result)
end

local function onClaimReward(rewardId)
    local result
    local ok, err = pcall(function() result = W.claim(source, rewardId) end)
    if not ok then
        Referral.warn("claim failed:", tostring(err))
        result = { ok = false, errorKey = "no_reward", message = ReferralServer.errors.no_reward }
    end
    triggerClientEvent(source, Referral.events.applyResult, resourceRoot, {
        ok = result.ok, claim = true, errorKey = result.errorKey,
        message = result.message, amount = result.amount,
    })
end

local function onReportLevel(level)
    M.setLevel(source, level)
end

local function onReportPlaytime(minutes)
    M.addPlaytime(source, minutes)
end

--============================================================--
--  PLAYER LIFECYCLE
--============================================================--
local function onPlayerJoin()
    local row = S.ensurePlayer(source)
    if not row then return end
    playtime[source] = { minutes = 0, lastTick = getTickCount() }
    levels[source] = M.readLevel(source)

    --  a returning owner collects rewards earned while offline
    if ReferralConfig.enabled then
        setTimer(function()
            if isElement(source) then W.payPending(source, false) end
        end, 2500, 1)
    end
end

local function onPlayerQuit()
    playtime[source] = nil
    levels[source] = nil
    V.forgetPlayer(source)
end

--============================================================--
--  INIT
--============================================================--
function M.init()
    math.randomseed(getRealTime().timestamp + getTickCount())

    if not S.init() then
        Referral.warn("running without a database - data will not persist")
    end

    addEvent(Referral.events.requestProfile, true)
    addEvent(Referral.events.applyCode, true)
    addEvent(Referral.events.claimReward, true)
    addEvent(Referral.events.reportLevel, true)
    addEvent(Referral.events.reportPlaytime, true)

    addEventHandler(Referral.events.requestProfile, resourceRoot, onRequestProfile)
    addEventHandler(Referral.events.applyCode, resourceRoot, onApplyCode)
    addEventHandler(Referral.events.claimReward, resourceRoot, onClaimReward)
    addEventHandler(Referral.events.reportLevel, resourceRoot, onReportLevel)
    addEventHandler(Referral.events.reportPlaytime, resourceRoot, onReportPlaytime)

    addEventHandler("onPlayerJoin", root, onPlayerJoin)
    addEventHandler("onPlayerQuit", root, onPlayerQuit)

    local flushMs = math.max(5, (ReferralConfig.storage.playtimeFlushSeconds or 30)) * 1000
    setTimer(flushPlaytime, flushMs, 0)

    for _, player in ipairs(getElementsByType("player")) do
        playtime[player] = { minutes = 0, lastTick = getTickCount() }
        levels[player] = M.readLevel(player)
    end

    Referral.log("server ready | storage:", S.backendName())
end

addEventHandler("onResourceStart", resourceRoot, M.init)

--============================================================--
--  SERVER EXPORTS (for other resources / gamemodes)
--============================================================--
function M.getReferralCode(player)
    local row = S.ensurePlayer(player)
    if not row then return "" end
    if not row.code or row.code == "" then
        local _, code = R.ensureCode(player)
        return code or ""
    end
    return row.code
end

function M.getReferralStats(player)
    local payload = R.buildProfile(player)
    if not payload then return nil end
    return payload.stats
end

function M.getReferrals(player)
    local payload = R.buildProfile(player)
    if not payload then return {} end
    return payload.referrals
end

function M.isReferredBy(player, ownerSerial)
    local row = S.ensurePlayer(player)
    if not row or (tonumber(row.referred_by) or 0) == 0 then return false end
    local owner = S.getPlayerById(row.referred_by)
    if not owner then return false end
    return owner.serial == ownerSerial
end
