--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Server / Validation
--========================================================--
--  Pure, server side rules. The client is never trusted for
--  reward amounts, ownership, status or completion state.
--  Every function returns: ok (boolean), errorKey, extraData
--========================================================--

ReferralServer = ReferralServer or {}
local V = {}
ReferralServer.validation = V

--============================================================--
--  ERROR MESSAGES (single source of truth, reused by the UI)
--============================================================--
ReferralServer.errors = {
    disabled      = "نظام الاحالة متوقف حاليا",
    invalid_code  = "الكود غير صالح",
    self_code     = "لا يمكنك استخدام كودك الخاص",
    already_used  = "لقد استخدمت كود احالة مسبقا",
    unavailable   = "هذا الكود غير متاح حاليا",
    owner_limit   = "وصل صاحب الكود الى الحد الاقصى من الاحالات",
    cooldown      = "انتظر قليلا قبل المحاولة مرة اخرى",
    rate_limited  = "محاولات كثيرة - حاول بعد قليل",
    not_eligible  = "لا يمكنك استخدام كود احالة الان",
    no_data       = "تعذر تحميل بيانات الاحالة",
    no_reward     = "لا توجد مكافاة متاحة للاستلام",
    not_owner     = "هذه المكافاة لا تخصك",
}

--  in-memory rate limiting (also persisted through the abuse table)
local attempts = {}

--============================================================--
--  IDENTITY
--============================================================--
---Validate that we are dealing with a real, connected player.
function V.validatePlayer(player)
    if not isElement(player) or getElementType(player) ~= "player" then
        return false, "not_eligible"
    end
    local serial = getPlayerSerial(player)
    if not serial or serial == "" then
        return false, "not_eligible"
    end
    return true, serial
end

function V.getAccountName(player)
    if not isElement(player) then return "" end
    local account = getPlayerAccount(player)
    if not account then return "" end
    return getAccountName(account) or ""
end

--============================================================--
--  CODE FORMAT
--============================================================--
function V.validateCodeFormat(code)
    if type(code) ~= "string" then return false, nil end
    code = Referral.trim(code):upper()
    if code == "" then return false, nil end

    local cfg = ReferralConfig.code
    local minLength = math.floor(cfg.length * 0.5)
    if #code < minLength or #code > 24 then return false, nil end

    for i = 1, #code do
        local char = code:sub(i, i)
        if not char:match("[A-Z0-9%-_]") then return false, nil end
    end
    return true, code
end

--============================================================--
--  RATE LIMITING / COOLDOWN
--============================================================--
local function bucket(serial)
    attempts[serial] = attempts[serial] or { times = {}, lastAttempt = 0 }
    return attempts[serial]
end

---True when the player must wait before trying again.
function V.isCoolingDown(serial)
    if not serial then return false end
    local data = bucket(serial)
    local cfg = ReferralConfig.code
    return (Referral.now() - data.lastAttempt) < (cfg.cooldownSeconds or 5)
end

function V.registerAttempt(serial)
    if not serial then return end
    local data = bucket(serial)
    data.lastAttempt = Referral.now()
    data.times[#data.times + 1] = data.lastAttempt
end

---True when too many attempts happened inside the attempt window.
function V.isRateLimited(serial)
    if not serial then return true end
    local cfg = ReferralConfig.code
    local data = bucket(serial)
    local window = Referral.now() - (cfg.attemptWindow or 60)
    local recent = 0
    for i = #data.times, 1, -1 do
        if data.times[i] >= window then recent = recent + 1 end
    end
    return recent >= (cfg.maxAttempts or 5)
end

function V.clearAttempts(serial)
    if serial then attempts[serial] = nil end
end

function V.forgetPlayer(player)
    if not isElement(player) then return end
    local serial = getPlayerSerial(player)
    if serial then attempts[serial] = nil end
end

--============================================================--
--  ELIGIBILITY
--  A player may enter a code only when they are not linked yet.
--============================================================--
function V.isEligibleForCode(playerRow)
    if type(playerRow) ~= "table" then return false end
    if (tonumber(playerRow.referred_by) or 0) > 0 then
        return false, "already_used"
    end
    return true
end

--============================================================--
--  FULL CODE CHECK
--  Returns: ok, errorKey, context { owner, invitee }
--============================================================--
function V.canApplyCode(player, code)
    if not ReferralConfig.enabled then return false, "disabled" end

    local ok, serialOrError = V.validatePlayer(player)
    if not ok then return false, serialOrError end
    local serial = serialOrError

    local formatted, cleanCode = V.validateCodeFormat(code)
    if not formatted then return false, "invalid_code" end

    if V.isRateLimited(serial) then
        ReferralServer.storage.logAbuse(serial, V.getAccountName(player), "rate_limited",
            "code=" .. tostring(cleanCode))
        return false, "rate_limited"
    end

    if V.isCoolingDown(serial) then
        return false, "cooldown"
    end

    V.registerAttempt(serial)

    local invitee = ReferralServer.storage.ensurePlayer(player)
    if not invitee then return false, "not_eligible" end

    local owner = ReferralServer.storage.getPlayerByCode(cleanCode)
    if not owner or not owner.id then return false, "invalid_code" end

    --  self referral: same serial, same account or the same database row
    if owner.serial == serial or (owner.id == invitee.id)
        or (owner.account ~= "" and owner.account == invitee.account) then
        ReferralServer.storage.logAbuse(serial, invitee.account, "self_referral",
            "code=" .. tostring(cleanCode))
        return false, "self_code"
    end

    --  duplicate referral: this player already used a code
    if (tonumber(invitee.referred_by) or 0) > 0 then
        ReferralServer.storage.logAbuse(serial, invitee.account, "duplicate_referral",
            "code=" .. tostring(cleanCode))
        return false, "already_used"
    end

    local existing = ReferralServer.storage.getReferralByInvitee(invitee.id)
    if existing then
        ReferralServer.storage.logAbuse(serial, invitee.account, "duplicate_referral_row",
            "code=" .. tostring(cleanCode))
        return false, "already_used"
    end

    --  inviter limits
    if ReferralConfig.maxReferrals and ReferralConfig.maxReferrals > 0 then
        if ReferralServer.storage.countReferrals(owner.id) >= ReferralConfig.maxReferrals then
            return false, "owner_limit"
        end
    end

    if ReferralConfig.maxOpenReferralsPerOwner
        and ReferralConfig.maxOpenReferralsPerOwner > 0 then
        if ReferralServer.storage.countReferrals(owner.id, "pending")
            >= ReferralConfig.maxOpenReferralsPerOwner then
            return false, "owner_limit"
        end
    end

    return true, nil, { owner = owner, invitee = invitee, code = cleanCode }
end

--============================================================--
--  REWARD / REQUIREMENT CHECKS (used by the reward layer)
--============================================================--
---Are the configured requirements satisfied by the stored row?
function V.requirementsMet(playerRow)
    if type(playerRow) ~= "table" then return false end
    local req = ReferralConfig.requirements

    if req.requireLevel then
        if (tonumber(playerRow.level) or 0) < (tonumber(req.level) or 1) then
            return false
        end
    end
    if req.requirePlaytime then
        if (tonumber(playerRow.playtime_minutes) or 0) < (tonumber(req.playtimeMinutes) or 0) then
            return false
        end
    end
    if req.requireLoginDays then
        if (tonumber(playerRow.login_days) or 0) < (tonumber(req.loginDays) or 1) then
            return false
        end
    end
    return true
end

---Progress of a single referral towards its requirements (0..1 per item).
function V.requirementProgress(referralRow, playerRow)
    local req = ReferralConfig.requirements
    local items = {}

    local levelDone = not req.requireLevel
        or (tonumber(playerRow and playerRow.level) or 0) >= (tonumber(req.level) or 1)
    items[#items + 1] = {
        key   = "level",
        label = "الوصول الى المستوى " .. tostring(req.level or 1),
        done  = levelDone,
        value = tostring(playerRow and playerRow.level or 0),
    }

    local minutes = tonumber(playerRow and playerRow.playtime_minutes) or 0
    local playDone = not req.requirePlaytime or minutes >= (tonumber(req.playtimeMinutes) or 0)
    items[#items + 1] = {
        key   = "playtime",
        label = "اكمال " .. Referral.formatDuration(req.playtimeMinutes or 0) .. " لعب",
        done  = playDone,
        value = Referral.formatDuration(minutes),
    }

    local doneCount = 0
    for _, item in ipairs(items) do
        if item.done then doneCount = doneCount + 1 end
    end
    return {
        items = items,
        done  = doneCount,
        total = #items,
        percent = Referral.percent(doneCount, #items),
    }
end

---Never let a caller inject a reward amount: always recompute it here.
function V.computeRewardAmount()
    local cfg = ReferralConfig.rewards
    return math.max(0, math.floor(tonumber(cfg.perReferral) or 0))
end
