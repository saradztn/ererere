--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / UI helpers
--========================================================--
--  Thin wrappers around NovaUI components. They standardise
--  the props used by this resource (spacing, sizes, empty /
--  loading / error states) but never draw anything themselves.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = {}
ReferralClient.ui = UI

--============================================================--
--  LAYOUT MODEL
--  Coordinates are NovaUI coordinates (already scaled).
--  Children are positioned relative to their parent.
--============================================================--
UI.layout = {
    sidebarWidth  = 238,
    contentWidth  = 862,
    contentHeight = 564,
    topbarHeight  = 52,
    pageHeight    = 512,
    padding       = 16,
    gap           = 14,
}

--  derived geometry helpers -------------------------------------------
function UI.bodyGeometry()
    local side = (ReferralConfig.ui.sidebarSide or "right") == "left" and "left" or "right"
    local w = UI.layout.contentWidth
    local x = (side == "left") and UI.layout.sidebarWidth or 0
    return x, 0, w, UI.layout.contentHeight
end

function UI.rowX(count, gap)
    gap = gap or UI.layout.gap
    local total = UI.layout.contentWidth
    local w = math.floor((total - gap * (count - 1)) / count)
    local xs = {}
    for i = 1, count do
        xs[i] = (i - 1) * (w + gap)
    end
    return w, xs
end

--============================================================--
--  SOUND (micro interaction feedback)
--============================================================--
function UI.sound(name)
    if not ReferralConfig.ui.sounds.enabled then return end
    local path = ReferralConfig.ui.sounds[name]
    if not path then return end
    if type(playSound) ~= "function" then return end
    pcall(playSound, path)
end

--============================================================--
--  CLIPBOARD
--============================================================--
function UI.copyToClipboard(text)
    if type(text) ~= "string" or text == "" then return false end
    if type(setClipboard) ~= "function" then return false end
    local ok = pcall(setClipboard, text)
    return ok
end

--============================================================--
--  NOTIFICATIONS
--============================================================--
function UI.notify(props)
    return N.notify(props)
end

function UI.toastSuccess(title, message)
    UI.sound("reward")
    UI.notify({ type = "success", title = title, message = message, duration = 2800 })
end

function UI.toastError(title, message)
    UI.sound("error")
    UI.notify({ type = "error", title = title, message = message, duration = 3200 })
end

function UI.toastInfo(title, message)
    UI.notify({ type = "info", title = title, message = message, duration = 2600 })
end

--============================================================--
--  PRIMITIVE WRAPPERS
--============================================================--
function UI.create(parent, kind, props)
    if not parent then
        Referral.warn("UI.create called without a parent for", kind)
        return nil
    end
    return N.child(parent, kind, props or {})
end

function UI.label(parent, x, y, w, h, text, props)
    props = props or {}
    props.x, props.y, props.width, props.height = x, y, w, h
    props.text = text
    return UI.create(parent, "label", props)
end

function UI.button(parent, x, y, w, h, text, props)
    props = props or {}
    props.x, props.y, props.width, props.height = x, y, w, h
    props.text = text
    return UI.create(parent, "button", props)
end

function UI.icon(parent, x, y, size, name, props)
    props = props or {}
    props.x, props.y = x, y
    props.width, props.height = size, size
    props.icon = name
    return UI.create(parent, "icon", props)
end

function UI.divider(parent, x, y, w, props)
    props = props or {}
    props.x, props.y, props.width = x, y, w
    props.height = props.height or 1
    return UI.create(parent, "divider", props)
end

function UI.spacer(parent, x, y, w, h)
    return UI.create(parent, "spacer", { x = x, y = y, width = w, height = h })
end

function UI.badge(parent, x, y, w, h, text, color)
    return UI.create(parent, "badge", {
        x = x, y = y, width = w, height = h,
        text = text, color = color,
    })
end

function UI.panel(parent, x, y, w, h, props)
    props = props or {}
    props.x, props.y, props.width, props.height = x, y, w, h
    return UI.create(parent, "panel", props)
end

--============================================================--
--  CARD
--  Returns the card element; children are placed relative to it.
--============================================================--
function UI.card(parent, x, y, w, h, title, icon, props)
    props = props or {}
    props.x, props.y, props.width, props.height = x, y, w, h
    props.title = title
    if icon then props.icon = icon end
    local card = UI.create(parent, "card", props)
    if not card then
        --  degrade to a plain panel so the page still renders
        card = UI.panel(parent, x, y, w, h, { name = props.name or "card" })
    end
    return card
end

--============================================================--
--  STAT CARD (KPI)
--============================================================--
function UI.statCard(parent, x, y, w, h, opts)
    opts = opts or {}
    local props = {
        x = x, y = y, width = w, height = h,
        title   = opts.title or "",
        value   = opts.value or 0,
        icon    = opts.icon or "chart",
        caption = opts.caption or opts.subtitle,
        color   = opts.color,
    }
    if opts.trend then
        props.trend = {
            value = opts.trend,
            direction = opts.trendDirection or "up",
        }
    end
    if opts.sparkline then
        props.sparkline = opts.sparkline
    end
    --  optional second (custom) icon drawn on top of the NovaUI icon slot
    if opts.extraIcon then
        props.iconPath = opts.extraIcon
    end
    local card = UI.create(parent, "statscard", props)
    if not card then
        card = UI.panel(parent, x, y, w, h, { name = "statscard" })
        UI.label(card, UI.layout.padding, UI.layout.padding + 6, w - 32, 20, opts.title or "",
            { name = "statTitle", size = 12 })
        UI.label(card, UI.layout.padding, UI.layout.padding + 28, w - 32, 34, tostring(opts.value or 0),
            { name = "statValue", size = 26 })
    end
    if opts.extraIcon then
        UI.create(card, "icon", {
            x = w - 46, y = 14, width = 26, height = 26,
            name = (props.name or "stat") .. "ExtraIcon",
            path = opts.extraIcon, alpha = 210,
        })
    end
    return card
end

--============================================================--
--  STATE BLOCKS
--  Empty / loading / error are real NovaUI components, never
--  blank space.
--============================================================--
function UI.loadingBlock(parent, x, y, w, h, text)
    local block = UI.panel(parent, x, y, w, h, { name = "loadingBlock" })
    if not block then return nil end
    UI.create(block, "spinner", {
        x = math.floor(w / 2) - 14, y = math.floor(h / 2) - 34,
        width = 28, height = 28, name = "loadingSpinner",
    })
    UI.label(block, 16, math.floor(h / 2) + 4, w - 32, 24, text or "جاري تحميل البيانات",
        { name = "loadingText", align = "center", size = 13 })
    return block
end

function UI.emptyBlock(parent, x, y, w, h, title, message, icon)
    local block = UI.panel(parent, x, y, w, h, { name = "emptyBlock" })
    if not block then return nil end
    UI.icon(block, math.floor(w / 2) - 18, 22, 36, icon or "info", { name = "emptyIcon", alpha = 170 })
    UI.label(block, 16, 68, w - 32, 26, title or "لا توجد بيانات",
        { name = "emptyTitle", align = "center", size = 15 })
    if message and message ~= "" then
        UI.label(block, 24, 96, w - 48, 44, message,
            { name = "emptyMessage", align = "center", size = 12, alpha = 170 })
    end
    return block
end

function UI.errorBlock(parent, x, y, w, h, message, onRetry)
    local block = UI.panel(parent, x, y, w, h, { name = "errorBlock" })
    if not block then return nil end
    UI.icon(block, math.floor(w / 2) - 18, 20, 36, "warning", { name = "errorIcon" })
    UI.label(block, 16, 64, w - 32, 26, message or UI.defaultErrorMessage(),
        { name = "errorTitle", align = "center", size = 14 })
    if onRetry then
        local button = UI.button(block, math.floor(w / 2) - 60, 100, 120, 34, "اعادة المحاولة",
            { name = "errorRetry", icon = "refresh" })
        if button then
            N.on(button, "click", function() onRetry() end)
        end
    end
    return block
end

--  default message so the error block never renders a nil label
function UI.defaultErrorMessage()
    return "تعذر تحميل بيانات الاحالة"
end

--============================================================--
--  ANIMATIONS
--  Entrance: fade + small slide, soft stagger. NovaUI owns the
--  easing, we only describe intent.
--============================================================--
function UI.fadeIn(element, delay)
    if not element then return end
    N.animate(element, {
        alpha  = 255,
        offset = 0,
        duration = 320,
        easing = "outCubic",
        delay  = delay or 0,
    })
end

function UI.slideIn(element, delay, distance)
    if not element then return end
    N.animate(element, {
        alpha    = 255,
        offsetY  = distance or 12,
        duration = 380,
        easing   = "outCubic",
        delay    = delay or 0,
    })
end

function UI.stagger(elements, delayStep)
    delayStep = delayStep or 45
    for index, element in ipairs(elements) do
        UI.slideIn(element, (index - 1) * delayStep)
    end
end

---Briefly swap an icon (copy -> check micro interaction).
function UI.flashIcon(element, fromIcon, toIcon, duration)
    if not element then return end
    N.patch(element, { icon = toIcon })
    setTimer(function()
        if N.isElement(element) then
            N.patch(element, { icon = fromIcon })
        end
    end, duration or 1600, 1)
end

--============================================================--
--  TABLE HELPERS
--============================================================--
---Convert our row model into the column layout NovaUI tables use.
function UI.referralColumns()
    return {
        { key = "id",            title = "ID",            width = 60,  align = "center" },
        { key = "player",        title = "اللاعب",        width = 190 },
        { key = "registeredText",title = "تاريخ التسجيل", width = 130, align = "center" },
        { key = "level",         title = "المستوى",       width = 90,  align = "center" },
        { key = "playtimeText",  title = "مدة اللعب",     width = 110, align = "center" },
        { key = "statusLabel",   title = "الحالة",        width = 120, align = "center" },
        { key = "rewardText",    title = "المكافاة",      width = 120, align = "center" },
    }
end

function UI.rewardColumns()
    return {
        { key = "referral",   title = "الاحالة",       width = 220 },
        { key = "typeLabel",  title = "نوع المكافاة",  width = 170 },
        { key = "amountText", title = "القيمة",        width = 130, align = "center" },
        { key = "statusLabel",title = "الحالة",        width = 120, align = "center" },
        { key = "date",       title = "التاريخ",       width = 130, align = "center" },
    }
end

---Keep a NovaUI table in sync with a fresh array of rows.
function UI.setRows(tableElement, rows)
    if not tableElement then return false end
    if type(tableElement.setRows) == "function" then
        return N.call(tableElement, "setRows", rows)
    end
    if type(tableElement.setData) == "function" then
        return N.call(tableElement, "setData", rows)
    end
    if type(tableElement.setItems) == "function" then
        return N.call(tableElement, "setItems", rows)
    end
    return N.patch(tableElement, { rows = rows })
end

function UI.setTableFilter(tableElement, query)
    if not tableElement then return false end
    if type(tableElement.setFilter) == "function" then
        return N.call(tableElement, "setFilter", query)
    end
    return N.patch(tableElement, { filter = query })
end

function UI.setTableSort(tableElement, key, descending)
    if not tableElement then return false end
    if type(tableElement.setSort) == "function" then
        return N.call(tableElement, "setSort", key, descending)
    end
    return N.patch(tableElement, { sortKey = key, sortDescending = descending })
end

function UI.setChartData(chartElement, data, chartType)
    if not chartElement then return false end
    if type(chartElement.setData) == "function" then
        local ok = N.call(chartElement, "setData", data)
        if ok and chartType and type(chartElement.setType) == "function" then
            N.call(chartElement, "setType", chartType)
        end
        return ok
    end
    return N.patch(chartElement, { data = data, chartType = chartType })
end
