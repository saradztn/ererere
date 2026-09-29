--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Server / Rewards
--========================================================--
--  Reward eligibility, payout, claiming and milestone bonuses.
--  The client can never define an amount, a status or a claim.
--========================================================--

ReferralServer = ReferralServer or {}
local W = {}
ReferralServer.rewards = W

local V = ReferralServer.validation
local S = ReferralServer.storage
local R = ReferralServer.referrals

--============================================================--
--  PAYOUT
--============================================================--
---When a reward was handed over (falls back to its creation time).
function W.timestamp(rewardRow)
    if type(rewardRow) ~= "table" then return Referral.now() end
    local paid = tonumber(rewardRow.paid_at) or 0
    if paid > 0 then return paid end
    return tonumber(rewardRow.created_at) or Referral.now()
end

---Give money (or call the custom handler). Returns the paid amount.
function W.payout(player, amount, referralRow)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 or not isElement(player) then return 0 end

    local cfg = ReferralConfig.rewards
    if type(cfg.handler) == "function" then
        local ok, err = pcall(cfg.handler, player, amount, referralRow)
        if not ok then
            Referral.warn("custom reward handler failed:", tostring(err))
        end
        return amount
    end

    if cfg.giveMoney then
        if givePlayerMoney then
            givePlayerMoney(player, amount)
            return amount
        end
        Referral.warn("givePlayerMoney is not available on this server build")
    end
    return 0
end

--============================================================--
--  SETTLE
--  Called when a referral reaches its requirements: create the
--  reward row, pay it immediately when the owner is online and
--  autoPay is on, otherwise leave it pending for a later claim.
--============================================================--
function W.settle(referralRow, silent)
    if type(referralRow) ~= "table" then return false end
    if referralRow.status == "completed" or referralRow.status == "rejected" then
        return false
    end

    local invitee = S.getPlayerById(referralRow.invitee_id)
    if not invitee or not V.requirementsMet(invitee) then return false end

    local owner = S.getPlayerById(referralRow.owner_id)
    if not owner then return false end

    --  never trust an incoming amount, always recompute
    local amount = V.computeRewardAmount()
    local now = Referral.now()

    S.updateReferral(referralRow.id, {
        status = "active",
        reward_amount = amount,
        completed_at = now,
    })

    --  avoid duplicate reward rows for the same referral
    local rewardId
    for _, reward in ipairs(S.getRewardsByOwner(owner.id)) do
        if tonumber(reward.referral_id) == tonumber(referralRow.id)
            and reward.type == "referral" then
            rewardId = reward.id
            break
        end
    end
    if not rewardId then
        rewardId = S.createReward(owner.id, referralRow.id, "referral", amount, "pending")
    end

    local ownerPlayer = getPlayerFromSerial and getPlayerFromSerial(owner.serial)
    local online = ownerPlayer and isElement(ownerPlayer) or false

    if online and ReferralConfig.rewards.autoPay then
        --  markPaid writes status + paid_at on the real reward row
        W.markPaid({ id = rewardId, amount = amount }, ownerPlayer, amount, silent)
    end

    S.updateReferral(referralRow.id, { status = "completed" })
    W.checkMilestones(owner, silent)

    if online then
        ReferralServer.sendProfile(ownerPlayer)
        triggerEvent(Referral.events.onCompleted, resourceRoot, ownerPlayer, referralRow.id)
    end
    return true
end

---Mark a reward row as paid and hand the money over.
function W.markPaid(rewardRow, player, amount, silent)
    amount = amount or (rewardRow and tonumber(rewardRow.amount) or 0)
    if amount <= 0 or not isElement(player) then return false end

    if rewardRow and rewardRow.id then
        S.updateReward(rewardRow.id, { status = "paid", paid_at = Referral.now() })
    end

    local paid = W.payout(player, amount)
    if paid > 0 and not silent then
        ReferralServer.notifyPlayer(player, {
            type     = "success",
            title    = "تم استلام المكافاة",
            message  = "اضيفت " .. Referral.formatMoney(paid) .. " الى رصيدك",
            duration = 3600,
        })
        triggerClientEvent(player, Referral.events.rewardPaid, resourceRoot, {
            amount = paid, text = Referral.formatMoney(paid),
        })
        if ReferralConfig.ui.sounds.enabled then
            triggerClientEvent(player, Referral.events.notify, resourceRoot,
                { type = "success", sound = ReferralConfig.ui.sounds.reward })
        end
    end

    triggerEvent(Referral.events.onRewardPaid, resourceRoot, player, paid)
    return paid
end

--============================================================--
--  MILESTONE BONUS
--============================================================--
function W.checkMilestones(ownerRow, silent)
    if type(ownerRow) ~= "table" then return end
    local completed = S.countReferrals(ownerRow.id, "completed")
    --  the tier that has just been crossed (completed == tier.count)
    for _, tier in ipairs(ReferralConfig.rewards.milestones or {}) do
        if completed == (tier.count or -1) then
            local already
            for _, reward in ipairs(S.getRewardsByOwner(ownerRow.id)) do
                if reward.type == "milestone" and tonumber(reward.amount) == (tier.reward or 0) then
                    already = true
                    break
                end
            end
            if already then return end

            local milestoneId = S.createReward(ownerRow.id, 0, "milestone",
                tier.reward or 0, "pending")
            local ownerPlayer = getPlayerFromSerial and getPlayerFromSerial(ownerRow.serial)
            if ownerPlayer and isElement(ownerPlayer) then
                if ReferralConfig.rewards.autoPay then
                    W.markPaid({ id = milestoneId, amount = tier.reward },
                        ownerPlayer, tier.reward, silent)
                elseif ReferralConfig.rewards.notifyOwner then
                    ReferralServer.notifyPlayer(ownerPlayer, {
                        type = "success",
                        title = "مكافاة مرحلية",
                        message = "وصلت الى " .. tostring(tier.label or "") ..
                            " - المكافاة جاهزة للاستلام",
                        duration = 4000,
                    })
                end
            end
            return
        end
    end
end

--============================================================--
--  CLAIM
--============================================================--
function W.claim(player, rewardId)
    if not ReferralConfig.enabled then
        return { ok = false, errorKey = "disabled", message = ReferralServer.errors.disabled }
    end
    local ok, serial = V.validatePlayer(player)
    if not ok then
        return { ok = false, errorKey = "not_eligible", message = ReferralServer.errors.not_eligible }
    end

    local row = S.ensurePlayer(player)
    if not row then
        return { ok = false, errorKey = "not_eligible", message = ReferralServer.errors.not_eligible }
    end

    rewardId = tonumber(rewardId) or 0
    local target
    for _, reward in ipairs(S.getRewardsByOwner(row.id)) do
        if tonumber(reward.id) == rewardId then target = reward break end
    end
    if not target then
        return { ok = false, errorKey = "no_reward", message = ReferralServer.errors.no_reward }
    end
    if target.status == "paid" then
        return { ok = false, errorKey = "no_reward", message = ReferralServer.errors.no_reward }
    end

    local paid = W.markPaid(target, player, tonumber(target.amount) or 0)
    if paid <= 0 then
        return { ok = false, errorKey = "no_reward", message = ReferralServer.errors.no_reward }
    end

    ReferralServer.sendProfile(player)
    return { ok = true, amount = paid, message = "تم استلام المكافاة بنجاح" }
end

---Pay every pending reward of a player (called on join).
function W.payPending(player, silent)
    local row = S.ensurePlayer(player)
    if not row then return 0 end
    local paid = 0
    for _, reward in ipairs(S.getRewardsByOwner(row.id)) do
        if reward.status ~= "paid" and (tonumber(reward.amount) or 0) > 0 then
            if W.markPaid(reward, player, tonumber(reward.amount) or 0, silent) > 0 then
                paid = paid + 1
            end
        end
    end
    if paid > 0 then
        ReferralServer.sendProfile(player)
    end
    return paid
end

--============================================================--
--  READ MODEL
--============================================================--
function W.getViews(ownerRow)
    local out = {}
    if type(ownerRow) ~= "table" then return out end

    local nameById = {}
    for _, referral in ipairs(S.getReferralsByOwner(ownerRow.id)) do
        local invitee = S.getPlayerById(referral.invitee_id)
        if invitee then
            nameById[tonumber(referral.id)] =
                (invitee.account ~= "" and invitee.account) or "لاعب"
        end
    end

    for _, reward in ipairs(S.getRewardsByOwner(ownerRow.id)) do
        local isPaid = reward.status == "paid"
        local typeLabel = reward.type == "milestone" and "مكافاة مرحلية" or "مكافاة احالة"
        out[#out + 1] = {
            id          = reward.id,
            referralId  = tonumber(reward.referral_id) or 0,
            referral    = (reward.type == "milestone")
                and "هدف مرحلي" or (nameById[tonumber(reward.referral_id)] or "احالة"),
            type        = reward.type,
            typeLabel   = typeLabel,
            amount      = tonumber(reward.amount) or 0,
            amountText  = Referral.formatMoney(reward.amount),
            status      = isPaid and "paid" or "pending",
            statusLabel = isPaid and "مستلمة" or "معلقة",
            statusColor = isPaid and "#4ADE80" or "#FBBF24",
            statusBadge = isPaid and "success" or "warning",
            date        = Referral.formatDate(W.timestamp(reward)),
            relative    = Referral.formatRelative(W.timestamp(reward)),
            claimable   = (not isPaid) and ReferralConfig.rewards.autoPay == false,
        }
    end
    return out
end
