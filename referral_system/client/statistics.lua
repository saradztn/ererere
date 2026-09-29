--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Statistics page
--========================================================--
--  NovaUI charts driven by the real server series:
--    area  -> referrals of the last 7 days
--    donut -> referral status breakdown
--    bar   -> rewards paid during the week
--  No random or hardcoded values are ever drawn.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state

local PAGE = { key = "statistics", label = "الاحصائيات", icon = "chart" }
ReferralClient.pages = ReferralClient.pages or {}
ReferralClient.pages.statistics = PAGE

local W = UI.layout.contentWidth
local H = UI.layout.pageHeight

local refs = {}

--============================================================--
--  SUPPORTING STAT CARDS
--============================================================--
local function buildMiniStats(parent, y)
    local w, xs = UI.rowX(4)
    local h = 96
    refs.mini = {}

    local specs = {
        { name = "miniAvgLevel", title = "متوسط المستوى", icon = "user" },
        { name = "miniAvgPlay", title = "متوسط وقت اللعب", icon = "clock" },
        { name = "miniCompleted", title = "احالات مكتملة", icon = "check" },
        { name = "miniRejected", title = "احالات مرفوضة", icon = "error" },
    }

    for index, spec in ipairs(specs) do
        local card = UI.statCard(parent, xs[index], y, w, h, {
            name = spec.name, title = spec.title, icon = spec.icon, value = 0,
        })
        refs.mini[index] = card
    end
    return h
end

--============================================================--
--  CHARTS
--============================================================--
local function buildCharts(parent, y)
    local cardH = H - y - 6
    local leftW = 546
    local rightW = W - leftW - 14

    --  chart 1 : area
    local card1 = UI.card(parent, 0, y, leftW, cardH, "احالات آخر 7 أيام", "chart",
        { name = "chartReferrals" })
    if card1 then
        refs.area = UI.create(card1, "chart", {
            x = 14, y = 52, width = leftW - 28, height = cardH - 68,
            name = "chartArea",
            chartType = "area",
            data = {},
            color = "#60A5FA",
            showGrid = true,
            showLegend = false,
        })
        UI.create(card1, "icon", {
            x = leftW - 52, y = 16, width = 30, height = 30,
            name = "growthIcon", path = "assets/icons/growth.png", alpha = 200,
        })
        refs.areaEmpty = UI.emptyBlock(card1, 14, 52, leftW - 28, cardH - 68,
            "لا توجد بيانات بعد", "سجل الاحالات يظهر هنا", "chart")
    end

    --  chart 2 : donut
    local card2 = UI.card(parent, leftW + 14, y, rightW, cardH, "حالة الاحالات", "info",
        { name = "chartStatus" })
    if card2 then
        refs.donut = UI.create(card2, "chart", {
            x = 14, y = 52, width = rightW - 28, height = cardH - 100,
            name = "chartDonut",
            chartType = "donut",
            data = {},
            showLegend = true,
        })
        refs.donutEmpty = UI.emptyBlock(card2, 14, 52, rightW - 28, cardH - 100,
            "لا توجد احالات", "ابدأ بدعوة لاعبين", "users")
    end
end

local function buildRewardChart(parent, y)
    --  chart 3 : bar, full width under the other two
    local card = UI.card(parent, 0, y, W, H - y, "المكافآت خلال الأسبوع", "coins",
        { name = "chartRewards" })
    if not card then return end
    refs.bar = UI.create(card, "chart", {
        x = 14, y = 52, width = W - 28, height = H - y - 68,
        name = "chartBar",
        chartType = "bar",
        data = {},
        color = "#4ADE80",
        showGrid = true,
    })
    refs.barEmpty = UI.emptyBlock(card, 14, 52, W - 28, H - y - 68,
        "لا توجد مكافآت هذا الاسبوع", "المكافآت تظهر هنا بعد الاستلام", "coins")
end

--============================================================--
--  BUILD
--============================================================--
function PAGE.build(parent)
    local panel = UI.panel(parent, 0, 0, W, H, { name = "pageStatistics" })
    if not panel then return nil end

    buildMiniStats(panel, 0)
    buildCharts(panel, 106)
    buildRewardChart(panel, 106 + 176 + 10)
    return panel
end

--============================================================--
--  DATA BINDING
--============================================================--
local function toggle(element, visible, dataElement, data)
    if not element then return end
    if visible then
        N.call(element, "setVisible", true)
        if dataElement then UI.setChartData(dataElement, data) end
    else
        N.call(element, "setVisible", false)
    end
end

function PAGE.onData(panel, data)
    if not panel or not N.isElement(panel) then return end
    if type(data) ~= "table" then return end

    local stats = data.stats or {}
    local series = data.series or {}

    --  supporting cards
    local mini = {
        tostring(stats.avgLevel or 0),
        Referral.formatDuration(stats.avgPlaytime or 0),
        tostring(stats.completed or 0),
        tostring(stats.rejected or 0),
    }
    for index, card in ipairs(refs.mini or {}) do
        if card and mini[index] then N.patch(card, { value = mini[index] }) end
    end

    --  chart 1 : area
    local daily = series.daily or {}
    toggle(refs.areaEmpty, #daily == 0)
    if #daily > 0 then
        N.call(refs.area, "setVisible", true)
        UI.setChartData(refs.area, daily, "area")
    else
        N.call(refs.area, "setVisible", false)
    end

    --  chart 2 : donut
    local status = series.status or {}
    toggle(refs.donutEmpty, #status == 0)
    if #status > 0 then
        N.call(refs.donut, "setVisible", true)
        UI.setChartData(refs.donut, status, "donut")
    else
        N.call(refs.donut, "setVisible", false)
    end

    --  chart 3 : bar
    local rewards = series.rewards or {}
    local hasRewardData = false
    for _, point in ipairs(rewards) do
        if (tonumber(point.value) or 0) > 0 then
            hasRewardData = true
            break
        end
    end
    toggle(refs.barEmpty, not hasRewardData)
    if hasRewardData then
        N.call(refs.bar, "setVisible", true)
        UI.setChartData(refs.bar, rewards, "bar")
    else
        N.call(refs.bar, "setVisible", false)
    end
end

ReferralClient.navigation.register(PAGE)
