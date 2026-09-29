--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Dashboard page
--========================================================--
--  Hero referral code card, KPI stat cards, recent referrals
--  and the next reward progression. Everything reads from the
--  server snapshot in client/state.lua.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state

local PAGE = { key = "dashboard", label = "الرئيسية", icon = "dashboard" }
ReferralClient.pages = ReferralClient.pages or {}
ReferralClient.pages.dashboard = PAGE

local W = UI.layout.contentWidth
local H = UI.layout.pageHeight

--  component references, updated in place when data arrives
local refs = {}

--============================================================--
--  HELPERS
--============================================================--
local function money(value)
    return Referral.formatMoney(value)
end

local function inviteMessage(code)
    return "انضم الى السيرفر واستخدم كود الاحالة الخاص بي:\n" .. tostring(code)
end

local function last7Total(series)
    local total = 0
    for _, point in ipairs(series or {}) do
        total = total + (tonumber(point.value) or 0)
    end
    return total
end

--============================================================--
--  HERO / REFERRAL CODE CARD
--============================================================--
local function buildHero(parent, x, y, w, h)
    local card = UI.card(parent, x, y, w, h, nil, nil, {
        name = "heroCodeCard", variant = "accent",
    })
    if not card then return end

    --  custom icon (AI generated, part of assets/icons)
    UI.create(card, "icon", {
        x = w - 58, y = 20, width = 38, height = 38,
        name = "heroIcon", path = "assets/icons/referral.png",
        alpha = 220,
    })
    UI.create(card, "icon", {
        x = w - 96, y = 30, width = 22, height = 22,
        name = "heroLinkIcon", path = "assets/icons/referral-link.png",
        alpha = 150,
    })

    UI.label(card, 20, 20, w - 90, 20, "كود الاحالة الخاص بك",
        { name = "heroLabel", size = 12, alpha = 190 })

    refs.code = UI.label(card, 20, 42, w - 90, 46, "--------",
        { name = "heroCode", size = 34, mono = true })
    if refs.code then
        N.on(refs.code, "click", function()
            ReferralClient.dialogs.openShare()
        end)
    end

    UI.divider(card, 20, 98, w - 40)

    refs.copyButton = UI.button(card, 20, 108, 138, 32, "نسخ الكود", {
        name = "heroCopy", icon = "copy", variant = "primary",
    })
    if refs.copyButton then
        N.on(refs.copyButton, "click", function(self)
            local code = ST.code()
            if code == "" then
                UI.toastError("تعذر النسخ", "لم يتم تحميل الكود بعد")
                return
            end
            if UI.copyToClipboard(code) then
                UI.sound("copy")
                UI.flashIcon(self, "copy", "check", 1800)
                UI.notify({
                    type = "success",
                    title = "تم النسخ",
                    message = "تم نسخ كود الاحالة بنجاح",
                    duration = 2800,
                })
            else
                UI.toastError("تعذر النسخ", "المتصفح او النظام منع النسخ")
            end
        end)
    end

    refs.shareButton = UI.button(card, 166, 108, 152, 32, "مشاركة الكود", {
        name = "heroShare", icon = "share",
    })
    if refs.shareButton then
        N.on(refs.shareButton, "click", function()
            ReferralClient.dialogs.openShare()
        end)
    end

    --  status line: whether this player already used a code
    refs.heroNote = UI.label(card, 330, 114, w - 350, 24, "",
        { name = "heroNote", size = 11, alpha = 160 })
end

--============================================================--
--  NEXT REWARD / PROGRESSION
--============================================================--
local function buildNextReward(parent, x, y, w, h)
    local card = UI.card(parent, x, y, w, h, "المكافأة القادمة", "gift", {
        name = "nextRewardCard",
    })
    if not card then return end

    UI.create(card, "icon", {
        x = w - 52, y = 16, width = 30, height = 30,
        name = "nextRewardIcon", path = "assets/icons/milestone.png", alpha = 200,
    })

    refs.nextTitle = UI.label(card, 18, 54, w - 70, 22, "3 من 5 احالات مكتملة",
        { name = "nextRewardTitle", size = 13 })

    refs.progress = UI.create(card, "progressbar", {
        x = 18, y = 82, width = w - 36, height = 14,
        name = "nextRewardProgress", value = 0, max = 100,
        showLabel = true, color = "#4ADE80",
    })

    refs.progressLabel = UI.label(card, 18, 100, w - 36, 20, "0%",
        { name = "nextRewardPercent", size = 12, alpha = 180 })

    refs.nextHint = UI.label(card, 18, 120, w - 36, 22,
        "متبقي لاعبان للحصول على: 25,000 $",
        { name = "nextRewardHint", size = 12 })
end

--============================================================--
--  KPI STAT CARDS
--============================================================--
local function buildKpis(parent, y)
    local w, xs = UI.rowX(4)
    local h = 118

    refs.kpi = {}

    local cards = {
        { name = "kpiTotal", title = "اجمالي الاحالات", icon = "users",
          color = "#60A5FA", customIcon = "assets/icons/team.png",
          extraIcon = "assets/icons/growth.png" },
        { name = "kpiActive", title = "الاحالات النشطة", icon = "activity",
          color = "#4ADE80", customIcon = "assets/icons/activity.png" },
        { name = "kpiEarned", title = "المكافآت المكتسبة", icon = "coins",
          color = "#FBBF24", customIcon = "assets/icons/coins.png" },
        { name = "kpiRate", title = "معدل التحويل", icon = "chart",
          color = "#A78BFA", customIcon = "assets/icons/analytics.png" },
    }

    for index, spec in ipairs(cards) do
        local card = UI.statCard(parent, xs[index], y, w, h, {
            name  = spec.name,
            title = spec.title,
            icon  = spec.icon,
            value = 0,
            color = spec.color,
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
--  RECENT REFERRALS
--============================================================--
local function buildRecent(parent, x, y, w, h)
    local card = UI.card(parent, x, y, w, h, "اخر الاحالات", "users", {
        name = "recentCard",
    })
    if not card then return end

    refs.recentEmpty = nil
    refs.recentList = UI.create(card, "list", {
        x = 14, y = 52, width = w - 28, height = h - 66,
        name = "recentList",
        rows = {},
        rowHeight = 34,
        showBadge = true,
    })

    refs.recentMore = UI.button(card, w - 130, 14, 112, 26, "عرض الكل", {
        name = "recentMore", icon = "chevron-left", variant = "ghost",
    })
    if refs.recentMore then
        N.on(refs.recentMore, "click", function()
            ReferralClient.navigation.show("referrals")
        end)
    end
end

--============================================================--
--  QUICK ACTIONS
--============================================================--
local function buildQuickActions(parent, x, y, w, h)
    local card = UI.card(parent, x, y, w, h, "اجراءات سريعة", "sliders", {
        name = "quickCard",
    })
    if not card then return end

    local actions = {
        { text = "نسخ رسالة الدعوة", icon = "share", run = function()
            ReferralClient.dialogs.openShare()
        end },
        { text = "استخدام كود احالة", icon = "key", run = function()
            ReferralClient.dialogs.openApplyCode()
        end },
        { text = "شروط المكافآت", icon = "info", run = function()
            ReferralClient.navigation.show("conditions")
        end },
    }

    for index, action in ipairs(actions) do
        local button = UI.button(card, 16, 52 + (index - 1) * 42, w - 32, 34, action.text, {
            name = "quick" .. index, icon = action.icon, align = "right",
        })
        if button then
            N.on(button, "click", function() action.run() end)
        end
    end
end

--============================================================--
--  BUILD
--============================================================--
function PAGE.build(parent)
    local panel = UI.panel(parent, 0, 0, W, H, { name = "pageDashboard" })
    if not panel then return nil end

    --  row 1 : hero + next reward
    buildHero(panel, 0, 0, 546, 150)
    buildNextReward(panel, 560, 0, 302, 150)

    --  row 2 : KPI cards
    buildKpis(panel, 162)

    --  row 3 : recent referrals + quick actions
    buildRecent(panel, 0, 296, 546, H - 296)
    buildQuickActions(panel, 560, 296, 302, H - 296)

    --  entrance animation (soft stagger)
    UI.stagger({ refs.code, refs.progress }, 90)

    return panel
end

--============================================================--
--  DATA BINDING
--============================================================--
function PAGE.onData(panel, data)
    if not panel or not isElement(panel) then return end
    if type(data) ~= "table" or not data.stats then return end

    local stats = data.stats

    --  hero code
    if refs.code then
        N.patch(refs.code, { text = (data.code ~= "" and data.code) or "--------" })
    end

    if refs.heroNote then
        if data.canUseCode then
            N.patch(refs.heroNote, {
                text = "تقدر تستخدم كود احالة لاعب ثاني للحصول على مزايا البداية",
                alpha = 170,
            })
        else
            N.patch(refs.heroNote, {
                text = "استخدمت كود احالة مسبقا - شارك كودك واجمع المكافآت",
                alpha = 170,
            })
        end
    end

    --  next reward progression
    local milestone = stats.milestone or {}
    if refs.nextTitle then
        N.patch(refs.nextTitle, {
            text = string.format("%d من %d احالات مكتملة",
                milestone.completed or 0, milestone.target or 0),
        })
    end
    if refs.progress then
        N.patch(refs.progress, { value = milestone.percent or 0, max = 100 })
    end
    if refs.progressLabel then
        N.patch(refs.progressLabel, { text = tostring(milestone.percent or 0) .. "%" })
    end
    if refs.nextHint then
        if milestone.next then
            N.patch(refs.nextHint, {
                text = string.format("متبقي %s للحصول على: %s",
                    (milestone.remaining == 1) and "لاعب واحد" or
                    (tostring(milestone.remaining) .. " لاعبين"),
                    money(milestone.reward or 0)),
            })
        else
            N.patch(refs.nextHint, { text = "اكملت كل الاهداف - احسنت" })
        end
    end

    --  KPI cards
    local series = (data.series and data.series.daily) or {}
    local week = last7Total(series)

    local values = {
        { value = stats.total or 0,    caption = "اخر 7 ايام: " .. week },
        { value = stats.active or 0,   caption = "قيد التحقق: " .. (stats.pending or 0) },
        { value = money(stats.earned or 0), caption = "معلقة: " .. money(stats.pendingRewards or 0) },
        { value = tostring(stats.conversion or 0) .. "%", caption = "مكتملة: " .. (stats.completed or 0) },
    }

    for index, card in ipairs(refs.kpi or {}) do
        local spec = values[index]
        if card and spec then
            N.patch(card, { value = spec.value, caption = spec.caption })
        end
    end

    --  recent referrals list
    if refs.recentList then
        local rows = {}
        local limit = ReferralConfig.ui.recentCount or 6
        for index, referral in ipairs(data.referrals or {}) do
            if index > limit then break end
            rows[#rows + 1] = {
                id       = referral.id,
                text     = referral.player,
                subtitle = referral.registeredText .. " - " .. referral.rewardText,
                badge    = referral.statusLabel,
                color    = referral.statusColor,
                icon     = "user",
            }
        end
        UI.setRows(refs.recentList, rows)
    end
end

--============================================================--
--  REGISTER
--============================================================--
ReferralClient.navigation.register(PAGE)
