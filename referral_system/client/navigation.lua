--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Navigation
--========================================================--
--  NovaUI sidebar + breadcrumb + lazy page container.
--  Pages are built once and then shown/hidden with
--  setVisible(), so navigation never rebuilds the interface.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local NAV = {}
ReferralClient.navigation = NAV

NAV.pages  = {}     -- key -> { label, icon, panel, built, onShow, onData }
NAV.order  = { "dashboard", "referrals", "rewards", "statistics", "conditions" }
NAV.active = nil
NAV.body   = nil
NAV.breadcrumb = nil
NAV.sidebar = nil
NAV.topbar = nil
NAV.pageContainer = nil

--============================================================--
--  PAGE REGISTRY
--  Every page module registers itself here.
--============================================================--
function NAV.register(page)
    if type(page) ~= "table" or not page.key then return false end
    NAV.pages[page.key] = page
    if not Referral.contains(NAV.order, page.key) then
        NAV.order[#NAV.order + 1] = page.key
    end
    return true
end

function NAV.get(key)
    return NAV.pages[key]
end

--============================================================--
--  SIDEBAR ITEMS
--============================================================--
function NAV.sidebarItems()
    local items = {}
    for _, key in ipairs(NAV.order) do
        local page = NAV.pages[key]
        if page then
            items[#items + 1] = {
                id    = key,
                text  = page.label,
                icon  = page.icon,
                badge = page.badge,
            }
        end
    end
    return items
end

--============================================================--
--  TOP BAR
--============================================================--
local function buildTopbar(parent)
    local w = UI.layout.contentWidth
    local bar = UI.panel(parent, 0, 0, w, UI.layout.topbarHeight, { name = "referralTopbar" })
    if not bar then return nil end

    NAV.breadcrumb = UI.create(bar, "breadcrumb", {
        x = 16, y = 12, width = 460, height = 28,
        name = "referralBreadcrumb",
        items = { { text = "نظام الاحالة", icon = "home" }, { text = "الرئيسية" } },
    })

    local x = w - 16

    --  apply a referral code (eligible players only)
    x = x - 168
    NAV.applyButton = UI.button(bar, x, 10, 152, 32, "استخدام كود", {
        name = "topbarApplyCode", icon = "key", variant = "primary",
    })
    if NAV.applyButton then
        N.on(NAV.applyButton, "click", function()
            ReferralClient.dialogs.openApplyCode()
        end)
    end

    --  refresh the data
    x = x - 46
    NAV.refreshButton = UI.button(bar, x, 10, 38, 32, "", {
        name = "topbarRefresh", icon = "refresh", variant = "ghost",
        tooltip = "تحديث البيانات",
    })
    if NAV.refreshButton then
        N.on(NAV.refreshButton, "click", function()
            NAV.refresh()
        end)
    end

    return bar
end

--============================================================--
--  BUILD
--============================================================--
function NAV.build(body)
    if not body then
        Referral.warn("navigation: missing body container")
        return false
    end
    NAV.body = body

    --  page container sits under the top bar
    NAV.pageContainer = UI.create(body, "container", {
        x = 0, y = UI.layout.topbarHeight + 8,
        width = UI.layout.contentWidth,
        height = UI.layout.pageHeight,
        name = "referralPages",
    })
    if not NAV.pageContainer then
        NAV.pageContainer = body
    end

    NAV.topbar = buildTopbar(body)
    return true
end

---Attach the sidebar (called by main.lua after the window exists).
function NAV.setSidebar(sidebar)
    NAV.sidebar = sidebar
    if not sidebar then return end
    N.on(sidebar, "select", function(_, itemId)
        NAV.show(itemId)
    end)
    N.on(sidebar, "change", function(_, itemId)
        if itemId ~= NAV.active then
            NAV.show(itemId)
        end
    end)
end

--============================================================--
--  PAGE SWITCHING
--============================================================--
local function ensureBuilt(key)
    local page = NAV.pages[key]
    if not page then return nil end

    if not page.built or not page.panel then
        local panel = nil
        if type(page.build) == "function" then
            local ok, result = pcall(page.build, NAV.pageContainer)
            if ok then
                panel = result
            else
                Referral.warn("page build failed:", key, tostring(result))
            end
        end
        if not panel then
            panel = UI.panel(NAV.pageContainer, 0, 0, UI.layout.contentWidth, UI.layout.pageHeight,
                { name = "page_" .. key })
        end
        page.panel = panel
        page.built = true

        if page.onData then
            pcall(page.onData, panel, ReferralClient.state.data)
        end
        if page.subscribe ~= false then
            ReferralClient.state.subscribe(key, function(data)
                if page.panel and N.isElement(page.panel) and type(page.onData) == "function" then
                    pcall(page.onData, page.panel, data)
                end
            end)
        end
        N.flush()
    end
    return page
end

---Show a page, hide the others, update breadcrumb + sidebar.
function NAV.show(key)
    if not NAV.pages[key] then key = "dashboard" end
    if not NAV.pages[key] then return false end

    local page = ensureBuilt(key)
    if not page or not page.panel then return false end

    --  hide every other page (retained components, no rebuild)
    for otherKey, other in pairs(NAV.pages) do
        if other.panel and N.isElement(other.panel) and otherKey ~= key then
            N.call(other.panel, "setVisible", false)
        end
    end

    N.call(page.panel, "setVisible", true)
    N.call(page.panel, "bringToFront")
    UI.fadeIn(page.panel, 0)
    N.flush()

    NAV.active = key

    if NAV.breadcrumb then
        N.patch(NAV.breadcrumb, {
            items = {
                { text = "نظام الاحالة", icon = "home" },
                { text = page.label, icon = page.icon },
            },
        })
    end

    if NAV.sidebar then
        N.patch(NAV.sidebar, { active = key, selected = key })
    end

    if type(page.onShow) == "function" then
        pcall(page.onShow, page.panel)
    end
    return true
end

function NAV.current()
    return NAV.active
end

--============================================================--
--  REFRESH (micro interaction: spin then reload)
--============================================================--
function NAV.refresh()
    if NAV.refreshButton then
        N.animate(NAV.refreshButton, { rotation = 360, duration = 650, easing = "outCubic" })
    end
    ReferralClient.state.refresh()
end
