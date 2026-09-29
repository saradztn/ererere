--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Shared (client + server)
--========================================================--
--  Loaded on both sides. Holds the event names, the shared
--  helpers and the small pure functions used by every layer.
--========================================================--

Referral = Referral or {}
Referral.version = "1.0.0"

--============================================================--
--  EVENT NAMES
--  One place to rename a network event.
--============================================================--
Referral.events = {
    -- client -> server
    requestProfile   = "referral:requestProfile",
    applyCode        = "referral:applyCode",
    claimReward      = "referral:claimReward",
    -- server -> client
    profileData      = "referral:profileData",
    applyResult      = "referral:applyResult",
    stateChanged     = "referral:stateChanged",
    notify           = "referral:notify",
    rewardPaid       = "referral:rewardPaid",
    openUI           = "referral:openUI",
    -- gamemode integration (server side, triggerServerEvent on "resourceRoot")
    reportLevel      = "referral:reportLevel",
    reportPlaytime   = "referral:reportPlaytime",
    -- fired by this resource (server side, addEventHandler)
    onCodeApplied    = "onReferralCodeApplied",
    onCompleted      = "onReferralCompleted",
    onRewardPaid     = "onReferralRewardPaid",
    onRejected       = "onReferralRejected",
}

--============================================================--
--  TIME
--============================================================--
function Referral.now()
    return getRealTime().timestamp
end

--============================================================--
--  NUMBERS
--  Arabic UI, latin digits (the standard for MTA dashboards).
--============================================================--
function Referral.formatNumber(value)
    local n = tonumber(value) or 0
    n = math.floor(n)
    local formatted = tostring(n)
    while true do
        local new, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        formatted = new
        if count == 0 then break end
    end
    return formatted
end

function Referral.formatMoney(value, withCurrency)
    local cfg = ReferralConfig or {}
    local text = Referral.formatNumber(value)
    if withCurrency == nil then withCurrency = true end
    if withCurrency and cfg.rewards and cfg.rewards.currency then
        text = text .. " " .. cfg.rewards.currency
    end
    return text
end

function Referral.formatCompact(value)
    local n = tonumber(value) or 0
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000):gsub("%.0M", "M")
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000):gsub("%.0K", "K")
    end
    return tostring(math.floor(n))
end

--  95 -> "1 س 35 د"
function Referral.formatDuration(minutes)
    local m = math.floor(tonumber(minutes) or 0)
    if m < 60 then return m .. " د" end
    local h = math.floor(m / 60)
    local rest = m % 60
    if rest == 0 then return h .. " س" end
    return h .. " س " .. rest .. " د"
end

function Referral.formatPlaytime(minutes)
    return Referral.formatDuration(minutes)
end

--  timestamp -> "2026/09/29"
function Referral.formatDate(timestamp)
    local t = getRealTime(math.floor(tonumber(timestamp) or Referral.now()))
    return string.format("%04d/%02d/%02d", t.year + 1900, t.month + 1, t.monthday)
end

function Referral.formatDateTime(timestamp)
    local t = getRealTime(math.floor(tonumber(timestamp) or Referral.now()))
    return string.format("%04d/%02d/%02d - %02d:%02d",
        t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

--  timestamp -> "قبل 3 ايام"
function Referral.formatRelative(timestamp)
    local ts = math.floor(tonumber(timestamp) or 0)
    local diff = Referral.now() - ts
    if diff < 0 then diff = 0 end
    if diff < 60 then return "الان" end
    if diff < 3600 then return "قبل " .. math.floor(diff / 60) .. " دقيقة" end
    if diff < 86400 then return "قبل " .. math.floor(diff / 3600) .. " ساعة" end
    if diff < 2592000 then return "قبل " .. math.floor(diff / 86400) .. " يوم" end
    if diff < 31536000 then return "قبل " .. math.floor(diff / 2592000) .. " شهر" end
    return "قبل " .. math.floor(diff / 31536000) .. " سنة"
end

--============================================================--
--  STATUS HELPERS
--============================================================--
function Referral.getStatuses()
    local out = {}
    local cfg = ReferralConfig or {}
    if cfg.statusOrder then
        for _, key in ipairs(cfg.statusOrder) do
            local info = cfg.statuses and cfg.statuses[key]
            if info then out[#out + 1] = { key = key, label = info.label, color = info.color, badge = info.badge } end
        end
    end
    if #out == 0 and cfg.statuses then
        for key, info in pairs(cfg.statuses) do
            out[#out + 1] = { key = key, label = info.label, color = info.color, badge = info.badge }
        end
    end
    return out
end

function Referral.getStatusInfo(key)
    local cfg = ReferralConfig or {}
    local info = cfg.statuses and cfg.statuses[key]
    if not info then
        return { key = key or "unknown", label = key or "غير معروف", color = "#9AA4B2", badge = "default" }
    end
    return {
        key   = key,
        label = info.label,
        color = info.color,
        badge = info.badge or "default",
    }
end

function Referral.isValidStatus(key)
    local cfg = ReferralConfig or {}
    return (cfg.statuses and cfg.statuses[key]) and true or false
end

--============================================================--
--  MISC HELPERS
--============================================================--
function Referral.trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s*(.-)%s*$", "%1"))
end

function Referral.upper(text)
    if type(text) ~= "string" then return "" end
    return text:upper()
end

function Referral.round(value, decimals)
    local n = tonumber(value) or 0
    local mult = 10 ^ (decimals or 0)
    return math.floor(n * mult + 0.5) / mult
end

function Referral.clamp(value, min, max)
    local n = tonumber(value) or min
    if n < min then return min end
    if n > max then return max end
    return n
end

function Referral.percent(part, total)
    part = tonumber(part) or 0
    total = tonumber(total) or 0
    if total <= 0 then return 0 end
    return Referral.round((part / total) * 100)
end

function Referral.contains(list, value)
    if type(list) ~= "table" then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

function Referral.count(table_)
    if type(table_) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(table_) do n = n + 1 end
    return n
end

function Referral.deepCopy(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and Referral.deepCopy(value) or value
    end
    return copy
end

--  Debug output that stays silent unless config.debug is on.
function Referral.log(...)
    if not (ReferralConfig and ReferralConfig.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    outputDebugString("[REFERRAL] " .. table.concat(parts, " "), 3)
end

function Referral.warn(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    outputDebugString("[REFERRAL] " .. table.concat(parts, " "), 2)
end
