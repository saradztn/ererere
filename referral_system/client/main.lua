--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Main window
--========================================================--
--  One single NovaUI window for the whole resource:
--  created lazily, reused forever, never duplicated.
--  Owns the keybind, the command, the cursor and the
--  loading / error overlay.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state
local NAV = ReferralClient.navigation

local M = {}
ReferralClient.main = M

M.window   = nil
M.sidebar  = nil
M.body     = nil
M.overlay  = nil
M.built    = false
M.visible  = false
M.statusKind = nil

--============================================================--
--  WINDOW
--============================================================--
function M.build()
    if M.built and M.window then return true end

    if not N.resolve() then
        N.reportMissing()
        return false
    end

    local cfg = ReferralConfig.ui

    local window = N.create("window", {
        name        = "referralWindow",
        title       = cfg.windowTitle,
        subtitle    = cfg.windowSubtitle,
        icon        = cfg.windowIcon,
        font        = ReferralConfig.novaui.font,
        width       = cfg.width,
        height      = cfg.height,
        minWidth    = cfg.minWidth,
        minHeight   = cfg.minHeight,
        showFooter  = true,
        footerText  = "F6 لفتح واغلاق النافذة",
        resizable   = true,
        closable    = true,
        centered    = true,
        rtl         = true,
    })

    if not window then
        N.reportMissing()
        return false
    end
    M.window = window

    --  NovaUI font manager (used only when the build exposes it)
    N.invoke("setFont", ReferralConfig.novaui.font)
    N.invoke("useFont", ReferralConfig.novaui.font)

    --  sidebar navigation
    M.sidebar = N.child(window, "sidebar", {
        name = "referralSidebar",
        width = UI.layout.sidebarWidth,
        side = ReferralConfig.ui.sidebarSide or "right",
        items = NAV.sidebarItems(),
        active = "dashboard",
        collapsible = true,
    })
    NAV.setSidebar(M.sidebar)

    --  content area next to the sidebar
    local bodyX = (ReferralConfig.ui.sidebarSide or "right") == "left"
        and UI.layout.sidebarWidth or 0
    M.body = N.child(window, "container", {
        name = "referralBody",
        x = bodyX, y = 0,
        width = UI.layout.contentWidth,
        height = UI.layout.contentHeight,
    })

    NAV.build(M.body)
    M.buildOverlay()

    --  window lifecycle
    N.on(window, "close", function()
        M.close()
    end)
    N.on(window, "minimize", function()
        M.visible = false
        showCursor(false)
    end)

    M.built = true
    N.flush()

    --  first page
    NAV.show("dashboard")
    return true
end

--============================================================--
--  STATUS OVERLAY (loading / error)
--============================================================--
function M.buildOverlay()
    if M.overlay or not NAV.pageContainer then return end

    M.overlay = UI.panel(NAV.pageContainer, 0, 0, UI.layout.contentWidth, UI.layout.pageHeight,
        { name = "referralOverlay", visible = false })

    if M.overlay then
        M.overlayLoading = UI.loadingBlock(M.overlay, 0, 0,
            UI.layout.contentWidth, UI.layout.pageHeight, "جاري تحميل بيانات الاحالة")
        M.overlayError = UI.errorBlock(M.overlay, 0, 0,
            UI.layout.contentWidth, UI.layout.pageHeight,
            "تعذر تحميل بيانات الاحالة", function()
                ST.refresh()
            end)
        N.call(M.overlayLoading, "setVisible", false)
        N.call(M.overlayError, "setVisible", false)
    end
    N.flush()
end

function M.setStatus(kind)
    if not M.overlay then return end
    M.statusKind = kind

    N.call(M.overlay, "setVisible", kind ~= nil)
    N.call(M.overlayLoading, "setVisible", kind == "loading")
    N.call(M.overlayError, "setVisible", kind == "error")
    if kind then
        N.call(M.overlay, "bringToFront")
    end
end

--============================================================--
--  OPEN / CLOSE / TOGGLE
--============================================================--
function M.open()
    if not ReferralConfig.enabled then
        UI.toastError("النظام متوقف", "نظام الاحالة متوقف حاليا")
        return false
    end
    if not M.build() then return false end

    M.visible = true
    N.call(M.window, "setVisible", true)
    N.call(M.window, "bringToFront")
    showCursor(true)

    NAV.show(NAV.active or "dashboard")
    UI.sound("open")

    --  always show fresh data
    if ST.data then
        M.setStatus(nil)
    else
        M.setStatus("loading")
    end
    ST.refresh()
    return true
end

function M.close()
    M.visible = false
    ReferralClient.dialogs.closeAll()
    if M.window then
        N.call(M.window, "setVisible", false)
    end
    showCursor(false)
    return true
end

function M.toggle()
    if M.visible then
        M.close()
    else
        M.open()
    end
end

function M.isVisible()
    return M.visible
end

--============================================================--
--  STATE WATCHING
--============================================================--
local function watchState()
    if not M.built then return end

    if ST.loading and not ST.data then
        M.setStatus("loading")
        return
    end
    if ST.error then
        M.setStatus("error")
        return
    end
    M.setStatus(nil)
end

--============================================================--
--  INIT
--============================================================--
function M.init()
    ST.init()

    --  Safety net: handles are created as soon as they are needed (N.child,
    --  setVisible, ...) and every build path flushes explicitly, but a block
    --  assembled outside those paths still has to reach NovaUI. One frame of
    --  latency is invisible and keeps NovaUI's "never create in onClientRender"
    --  rule intact - this runs once per pending handle, not every frame.
    addEventHandler("onClientRender", root, function()
        if #ReferralClient.novaui.pending() > 0 then
            N.flush()
        end
    end)

    --  keybind
    if ReferralConfig.ui.openKey and ReferralConfig.ui.openKey ~= "" then
        bindKey(ReferralConfig.ui.openKey, "down", function()
            if ReferralConfig.enabled then
                M.toggle()
            end
        end)
    end

    --  command
    addCommandHandler(ReferralConfig.ui.command, function(_, argument)
        argument = Referral.trim((argument or "")):lower()
        if argument == "close" then
            M.close()
        elseif argument == "toggle" then
            M.toggle()
        elseif argument == "debug" or argument == "diag" then
            --  print the NovaUI wiring so a broken install is obvious
            local report = N.diagnose()
            outputDebugString("[REFERRAL] diagnostic:\n" .. report, 2)
            outputChatBox("#60A5FA[نظام الاحالة] #FFFFFFتم طباعة تشخيص NovaUI في كونسول السيرفر (F8)", 255, 255, 255, true)
        else
            M.open()
        end
    end)

    --  NovaUI may start after this resource: resolve again when it does
    addEventHandler("onClientResourceStart", root, function(resource)
        local name = getResourceName(resource)
        for _, candidate in ipairs(ReferralConfig.novaui.resourceNames) do
            if name == candidate then
                N.resolve(true)
                if M.built and not N.isReady() then
                    M.close()
                end
                break
            end
        end
    end)

    addEventHandler("onClientResourceStop", root, function(resource)
        local name = getResourceName(resource)
        for _, candidate in ipairs(ReferralConfig.novaui.resourceNames) do
            if name == candidate then
                M.close()
                N.resolve(true)
                break
            end
        end
    end)

    --  re-render when data changes
    ST.subscribe("main", watchState)

    Referral.log("client ready | novaUI:", tostring(N.name()))
end

--============================================================--
--  CLIENT EXPORTS
--============================================================--
function M.getReferralCode()
    return ST.code()
end

function M.getReferralStats()
    return ST.stats()
end
