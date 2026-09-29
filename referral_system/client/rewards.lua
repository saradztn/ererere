--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Rewards page
--========================================================--
--  Received / pending / total KPI cards plus the full reward
--  history table with claim support for pending rewards.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state

local PAGE = { key = "rewards", label = "المكافآت", icon = "gift" }
ReferralClient.pages = ReferralClient.pages or {}
ReferralClient.pages.rewards = PAGE

local W = UI.layout.contentWidth
local H = UI.layout.pageHeight

local refs = {}

--============================================================--
--  KPI CARDS
--============================================================--
local function buildKpis(parent)
    local w, xs = UI.rowX(3)
    local h = 118

    local cards = {
        { name = "rewardReceived", title = "المستلمة", icon = "check",
          color = "#4ADE80", customIcon = "assets/icons/wallet.png" },
        { name = "rewardPending", title = "المعلقة", icon = "clock",
          color = "#FBBF24", customIcon = "assets/icons/coins.png" },
        { name = "rewardTotal", title = "الاجمالي", icon = "chart",
          color = "#60A5FA", customIcon = "assets/icons/reward.png",
          extraIcon = "assets/icons/achievement.png" },
    }

    refs.kpi = {}
    for index, spec in ipairs(cards) do
        local card = UI.statCard(parent, xs[index], 0, w, h, {
            name = spec.name, title = spec.title, icon = spec.icon,
            value = 0, color = spec.color,
        })
        if card then
            UI.create(card, "icon", {
                x = w - 46, y = 14, width = 26, height = 26,
                name = spec.name .. "Icon", path = spec.customIcon, alpha = 210,
            })
        end
        refs.kpi[index] = card
    end
    return h
end

--============================================================--
--  HISTORY TABLE
--============================================================--
local function buildHistory(parent, y)
    local card = UI.card(parent, 0, y, W, H - y, "سجل المكافآت", "gift", {
        name = "rewardsHistory",
    })
    if not card then return end

    refs.empty = UI.emptyBlock(card, 14, 54, W - 28, H - y - 68,
        "لا توجد مكافآت معلقة",
        "عند اكمال احالة تظهر المكافأة هنا",
        "gift")

    refs.table = UI.create(card, "table", {
        x = 14, y = 54, width = W - 28, height = H - y - 68,
        name = "rewardsTable",
        columns = UI.rewardColumns(),
        rows = {},
        sortable = true,
        rowHeight = 40,
        selectable = true,
        virtualized = true,
        emptyText = "لا توجد مكافآت",
    })

    refs.claim = UI.button(card, W - 150, 14, 132, 26, "استلام المعلقة", {
        name = "rewardsClaim", icon = "coins", variant = "primary",
    })
    if refs.claim then
        N.on(refs.claim, "click", function()
            local pending = nil
            for _, reward in ipairs(ST.rewards()) do
                if reward.status ~= "paid" then
                    pending = reward
                    break
                end
            end
            if not pending then
                UI.toastInfo("لا يوجد شيء للاستلام", "كل المكافآت مستلمة")
                return
            end
            ST.claimReward(pending.id)
        end)
    end

    if refs.table then
        N.on(refs.table, "select", function(_, row)
            local id = type(row) == "table" and row.id or row
            for _, reward in ipairs(ST.rewards()) do
                if reward.id == id and reward.status ~= "paid" then
                    ST.claimReward(reward.id)
                    return
                end
            end
        end)
    end
end

--============================================================--
--  BUILD
--============================================================--
function PAGE.build(parent)
    local panel = UI.panel(parent, 0, 0, W, H, { name = "pageRewards" })
    if not panel then return nil end

    buildKpis(panel)
    buildHistory(panel, 130)
    return panel
end

--============================================================--
--  DATA BINDING
--============================================================--
function PAGE.onData(panel, data)
    if not panel or not isElement(panel) then return end
    if type(data) ~= "table" or not data.stats then return end

    local stats = data.stats
    local values = {
        Referral.formatMoney(stats.earned or 0),
        Referral.formatMoney(stats.pendingRewards or 0),
        Referral.formatMoney(stats.totalRewards or 0),
    }
    for index, card in ipairs(refs.kpi or {}) do
        if card and values[index] then
            N.patch(card, { value = values[index] })
        end
    end

    local rows = ST.filteredRewards()
    if #rows == 0 then
        N.call(refs.table, "setVisible", false)
        N.call(refs.empty, "setVisible", true)
        return
    end

    N.call(refs.empty, "setVisible", false)
    N.call(refs.table, "setVisible", true)
    UI.setRows(refs.table, rows)
end

ReferralClient.navigation.register(PAGE)
