--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Server / Referral logic
--========================================================--
--  Owns the referral lifecycle:
--    code generation, code redemption, progress evaluation
--    and the read models sent to the NovaUI client.
--  No SQL lives here - storage.lua is the only database layer.
--========================================================--

ReferralServer = ReferralServer or {}
local R = {}
ReferralServer.referrals = R

local V = ReferralServer.validation
local S = ReferralServer.storage

--============================================================--
--  CODE GENERATION
--============================================================--
local function randomPart(length)
    local alphabet = ReferralConfig.code.alphabet
    local out = {}
    for _ = 1, length do
        local index = math.random(#alphabet)
        out[#out + 1] = alphabet:sub(index, index)
    end
    return table.concat(out)
end

local function accountPrefix(account)
    if not ReferralConfig.code.useAccountPrefix then return "" end
    local base = (account or ""):gsub("[^%a%d]", ""):upper()
    if #base == 0 then base = "PLAYER" end
    return base:sub(1, ReferralConfig.code.prefixLength)
end

---Create a unique code for a player row (retries on collision).
function R.generateCode(playerRow)
    local length = math.max(4, math.floor(ReferralConfig.code.length or 8))
    for _ = 1, 40 do
        local prefix = accountPrefix(playerRow and playerRow.account)
        local code = prefix ~= "" and (prefix .. "-" .. randomPart(length)) or randomPart(length)
        if #code <= 24 and not S.getPlayerByCode(code) then
            return code
        end
    end
    return "REF-" .. randomPart(length + 4)
end

---Make sure the player row owns a code, generating it on first need.
function R.ensureCode(player)
    local row = S.ensurePlayer(player)
    if not row then return nil, nil end
    if not row.code or row.code == "" then
        local code = R.generateCode(row)
        S.updatePlayer(row.id, { code = code })
        row.code = code
    end
    return row, row.code
end

--============================================================--
--  REDEMPTION
--============================================================--
---Validate + apply a referral code. Fully server side.
---@return table result { ok, errorKey, message, code, referralId }
function R.applyCode(player, code)
    local ok, errorKey, context = V.canApplyCode(player, code)
    if not ok then
        --  NOTE: the attempt is deliberately NOT cleared here, otherwise the
        --  cooldown / rate limit would never trigger for brute force attempts.
        return {
            ok = false,
            errorKey = errorKey,
            message = ReferralServer.errors[errorKey] or ReferralServer.errors.invalid_code,
        }
    end

    local owner, invitee = context.owner, context.invitee
    local amount = V.computeRewardAmount()

    local referralId = S.createReferral(owner.id, invitee.id,
        ReferralConfig.defaultStatus, amount)

    S.updatePlayer(invitee.id, { used_code = context.code, referred_by = owner.id })
    V.clearAttempts(owner.serial)
    V.clearAttempts(invitee.serial)

    local referral = S.getReferralById(referralId)
    Referral.log("code applied:", context.code, "->", invitee.account)

    --  the invited player may already satisfy the requirements
    R.evaluate(player, true)

    --  notify the owner when he is online
    local ownerPlayer = getPlayerFromSerial and getPlayerFromSerial(owner.serial)
    if ownerPlayer and isElement(ownerPlayer) then
        ReferralServer.notifyPlayer(ownerPlayer, {
            type    = "success",
            title   = "احالة جديدة",
            message = "استخدم " .. tostring(invitee.account) .. " كود الاحالة الخاص بك",
            duration = 3200,
        })
        ReferralServer.sendProfile(ownerPlayer)
    end

    triggerEvent(Referral.events.onCodeApplied, resourceRoot,
        ownerPlayer or owner.serial, player, context.code, referralId)

    return {
        ok = true,
        code = context.code,
        referralId = referralId,
        message = "تم تطبيق كود الاحالة بنجاح",
        referral = referral,
    }
end

--============================================================--
--  PROGRESS EVALUATION
--============================================================--
---Re-check one invited player against the configured requirements.
---Called when level or playtime changes and right after redemption.
function R.evaluate(player, silent)
    if not isElement(player) then return false end
    local row = S.ensurePlayer(player)
    if not row then return false end

    local referral = S.getReferralByInvitee(row.id)
    if not referral then return false end
    if referral.status == "rejected" or referral.status == "completed" then
        return false
    end

    local req = ReferralConfig.requirements
    local now = Referral.now()
    local changed = false

    if req.requireLevel and (tonumber(row.level) or 0) >= (tonumber(req.level) or 1)
        and (tonumber(referral.level_reached_at) or 0) == 0 then
        S.updateReferral(referral.id, { level_reached_at = now })
        referral.level_reached_at = now
        changed = true
    end

    if req.requirePlaytime and (tonumber(row.playtime_minutes) or 0)
        >= (tonumber(req.playtimeMinutes) or 0)
        and (tonumber(referral.playtime_reached_at) or 0) == 0 then
        S.updateReferral(referral.id, { playtime_reached_at = now })
        referral.playtime_reached_at = now
        changed = true
    end

    if V.requirementsMet(row) then
        if referral.status == "pending" then
            S.updateReferral(referral.id, { status = "active" })
            referral.status = "active"
            changed = true
        end
        --  requirements satisfied -> hand over to the reward layer
        ReferralServer.rewards.settle(referral, silent)
    end

    if changed then
        --  refresh the owner's dashboard when he is online
        local owner = S.getPlayerById(referral.owner_id)
        local ownerPlayer = owner and getPlayerFromSerial and getPlayerFromSerial(owner.serial)
        if ownerPlayer and isElement(ownerPlayer) then
            ReferralServer.sendProfile(ownerPlayer)
        end
    end
    return changed
end

---Refresh every referral owned by a player (used after level changes).
function R.evaluateAllForOwner(ownerRow)
    if type(ownerRow) ~= "table" then return end
    for _, referral in ipairs(S.getReferralsByOwner(ownerRow.id)) do
        if referral.status ~= "completed" and referral.status ~= "rejected" then
            local invitee = S.getPlayerById(referral.invitee_id)
            if invitee and V.requirementsMet(invitee) then
                if referral.status == "pending" then
                    S.updateReferral(referral.id, { status = "active" })
                    referral.status = "active"
                end
                ReferralServer.rewards.settle(referral, true)
            end
        end
    end
end

--============================================================--
--  READ MODELS (what the UI receives)
--============================================================--
local function inviteeName(inviteeRow)
    if type(inviteeRow) ~= "table" then return "لاعب" end
    local player = getPlayerFromSerial and getPlayerFromSerial(inviteeRow.serial)
    if player and isElement(player) then
        local name = getPlayerName(player)
        if name and name ~= "" then return name end
    end
    if inviteeRow.account and inviteeRow.account ~= "" then return inviteeRow.account end
    return "لاعب"
end

local function timelineFor(referralRow, playerRow)
    local req = ReferralConfig.requirements
    local levelDone = (tonumber(referralRow.level_reached_at) or 0) > 0
    local playDone  = (tonumber(referralRow.playtime_reached_at) or 0) > 0
    local done      = (tonumber(referralRow.completed_at) or 0) > 0

    return {
        { label = "تم استخدام الكود",        done = true,    at = referralRow.code_used_at },
        { label = "تم التسجيل",              done = true,    at = referralRow.registered_at },
        { label = "تم الوصول للمستوى " .. tostring(req.level or 1),
          done = levelDone, at = referralRow.level_reached_at },
        { label = "تم استكمال وقت اللعب",    done = playDone, at = referralRow.playtime_reached_at },
        { label = "المكافاة مكتملة",         done = done,    at = referralRow.completed_at },
    }
end

---Build the row model used by the referrals table and the detail dialog.
function R.buildView(referralRow)
    if type(referralRow) ~= "table" then return nil end
    local invitee = S.getPlayerById(referralRow.invitee_id) or {}
    local status  = Referral.getStatusInfo(referralRow.status)
    local progress = V.requirementProgress(referralRow, invitee)
    local minutes = tonumber(invitee.playtime_minutes) or 0

    return {
        id            = referralRow.id,
        player        = inviteeName(invitee),
        account       = invitee.account or "",
        level         = tonumber(invitee.level) or 0,
        playtime      = minutes,
        playtimeText  = Referral.formatPlaytime(minutes),
        registeredAt  = tonumber(referralRow.registered_at) or 0,
        registeredText = Referral.formatDate(referralRow.registered_at),
        relativeText  = Referral.formatRelative(referralRow.registered_at),
        status        = referralRow.status,
        statusLabel   = status.label,
        statusColor   = status.color,
        statusBadge   = status.badge,
        reward        = tonumber(referralRow.reward_amount) or 0,
        rewardText    = Referral.formatMoney(referralRow.reward_amount),
        progress      = progress,
        timeline      = timelineFor(referralRow, invitee),
        requirements  = {
            level           = tonumber(ReferralConfig.requirements.level) or 1,
            playtimeMinutes = tonumber(ReferralConfig.requirements.playtimeMinutes) or 0,
        },
    }
end

function R.getViews(ownerRow)
    local out = {}
    if type(ownerRow) ~= "table" then return out end
    for _, referral in ipairs(S.getReferralsByOwner(ownerRow.id)) do
        local view = R.buildView(referral)
        if view then out[#out + 1] = view end
    end
    return out
end

--============================================================--
--  MILESTONES
--============================================================--
function R.milestoneFor(completedCount)
    local tiers = ReferralConfig.rewards.milestones or {}
    local reached, next
    for _, tier in ipairs(tiers) do
        if completedCount >= (tier.count or 0) then
            if not reached or (tier.count or 0) > (reached.count or 0) then reached = tier end
        else
            if not next or (tier.count or 0) < (next.count or 0) then next = tier end
        end
    end
    return reached, next
end

function R.milestoneInfo(completedCount)
    local reached, next = R.milestoneFor(completedCount)
    local info = {
        completed = completedCount,
        current   = reached,
        next      = next,
    }
    if next then
        local target = next.count or 1
        info.remaining = math.max(0, target - completedCount)
        info.target    = target
        info.percent   = Referral.percent(completedCount, target)
        info.reward    = next.reward or 0
        info.label     = next.label or ""
    else
        info.remaining = 0
        info.target    = completedCount
        info.percent   = 100
        info.reward    = reached and reached.reward or 0
        info.label     = reached and reached.label or ""
    end
    return info
end

--============================================================--
--  FULL PROFILE (the single payload the UI renders from)
--============================================================--
function R.buildProfile(player)
    local row, code = R.ensureCode(player)
    if not row then return nil end
    code = code or row.code or ""

    local referrals = S.getReferralsByOwner(row.id)
    local views = {}
    local counts = { total = 0, pending = 0, active = 0, completed = 0, rejected = 0 }
    local levelSum, playtimeSum, counted = 0, 0, 0

    for _, referral in ipairs(referrals) do
        counts.total = counts.total + 1
        counts[referral.status] = (counts[referral.status] or 0) + 1
        local view = R.buildView(referral)
        if view then
            views[#views + 1] = view
            levelSum = levelSum + view.level
            playtimeSum = playtimeSum + view.playtime
            counted = counted + 1
        end
    end

    local summary = S.getRewardSummary(row.id)
    local milestone = R.milestoneInfo(counts.completed)

    --  status breakdown for the donut chart (real data, not placeholders)
    local donut = {}
    for _, status in ipairs(Referral.getStatuses()) do
        local value = counts[status.key] or 0
        if value > 0 then
            donut[#donut + 1] = { label = status.label, value = value, color = status.color }
        end
    end

    --  7 day registration series
    local daily = {}
    for _, bucket in ipairs(S.getDailySeries(row.id, 7)) do
        daily[#daily + 1] = { label = bucket.label, value = bucket.value }
    end

    --  weekly reward series
    local weekly = {}
    for _, bucket in ipairs(S.getRewardSeries(row.id, 7)) do
        weekly[#weekly + 1] = { label = bucket.label, value = bucket.value }
    end

    local eligible, eligibleError = V.isEligibleForCode(row)

    return {
        ok        = true,
        code      = code,
        usedCode  = row.used_code or "",
        canUseCode = eligible and true or false,
        eligibleError = eligibleError,
        generatedAt = Referral.now(),
        requirements = {
            level           = tonumber(ReferralConfig.requirements.level) or 1,
            playtimeMinutes = tonumber(ReferralConfig.requirements.playtimeMinutes) or 0,
            requireLevel    = ReferralConfig.requirements.requireLevel and true or false,
            requirePlaytime = ReferralConfig.requirements.requirePlaytime and true or false,
        },
        stats = {
            total        = counts.total,
            pending      = counts.pending or 0,
            active       = counts.active or 0,
            completed    = counts.completed or 0,
            rejected     = counts.rejected or 0,
            earned       = summary.paid,
            pendingRewards = summary.pending,
            totalRewards = summary.paid + summary.pending,
            conversion   = Referral.percent(counts.completed, counts.total),
            avgLevel     = counted > 0 and Referral.round(levelSum / counted, 1) or 0,
            avgPlaytime  = counted > 0 and math.floor(playtimeSum / counted) or 0,
            milestone    = milestone,
        },
        referrals = views,
        rewards   = ReferralServer.rewards.getViews(row),
        series    = { daily = daily, status = donut, rewards = weekly },
    }
end
