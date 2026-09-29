--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Referrals page
--========================================================--
--  Toolbar (search + status filter + refresh), a sortable
--  NovaUI table of every referred player, empty state and
--  row selection that opens the detail dialog.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state

local PAGE = { key = "referrals", label = "الاحالات", icon = "users" }
ReferralClient.pages = ReferralClient.pages or {}
ReferralClient.pages.referrals = PAGE

local W = UI.layout.contentWidth
local H = UI.layout.pageHeight

local refs = {}

--============================================================--
--  FILTER OPTIONS (built from config so new statuses appear)
--============================================================--
local function filterOptions()
    local options = {
        { value = "all", text = "الكل" },
    }
    for _, status in ipairs(Referral.getStatuses()) do
        options[#options + 1] = { value = status.key, text = status.label }
    end
    return options
end

--============================================================--
--  TOOLBAR
--============================================================--
local function buildToolbar(parent)
    local bar = UI.panel(parent, 0, 0, W, 48, { name = "referralsToolbar" })
    if not bar then return end

    refs.search = UI.create(bar, "searchbox", {
        x = 0, y = 8, width = 280, height = 32,
        name = "referralsSearch",
        placeholder = "ابحث عن لاعب...",
        icon = "search",
        clearable = true,
    })
    if refs.search then
        N.on(refs.search, "change", function(_, value)
            ST.setQuery(value)
        end)
        N.on(refs.search, "submit", function(_, value)
            ST.setQuery(value)
        end)
    end

    refs.filter = UI.create(bar, "dropdown", {
        x = 292, y = 8, width = 180, height = 32,
        name = "referralsFilter",
        options = filterOptions(),
        value = "all",
        placeholder = "الحالة",
    })
    if refs.filter then
        N.on(refs.filter, "change", function(_, value)
            ST.setStatusFilter(value)
        end)
        N.on(refs.filter, "select", function(_, value)
            ST.setStatusFilter(value)
        end)
    end

    refs.refresh = UI.button(bar, 484, 8, 128, 32, "تحديث القائمة", {
        name = "referralsRefresh", icon = "refresh", variant = "ghost",
    })
    if refs.refresh then
        N.on(refs.refresh, "click", function()
            ReferralClient.navigation.refresh()
        end)
    end

    refs.count = UI.label(bar, W - 200, 14, 200, 22, "0 نتيجة",
        { name = "referralsCount", size = 12, alpha = 170 })
end

--============================================================--
--  TABLE + STATES
--============================================================--
local function buildTable(parent)
    refs.empty = UI.emptyBlock(parent, 0, 56, W, H - 56,
        "لا توجد نتائج مطابقة",
        "جرب تغيير كلمة البحث او الفلتر",
        "search")
    UI.create(refs.empty, "icon", {
        x = W - 56, y = 18, width = 30, height = 30,
        name = "emptyUserAdd", path = "assets/icons/user-add.png", alpha = 170,
    })

    refs.table = UI.create(parent, "table", {
        x = 0, y = 56, width = W, height = H - 56,
        name = "referralsTable",
        columns = UI.referralColumns(),
        rows = {},
        sortable = true,
        rowHeight = 40,
        selectable = true,
        pageSize = ReferralConfig.ui.rowsPerPage or 12,
        virtualized = true,
        emptyText = "لا توجد احالات حتى الان",
    })

    if refs.table then
        N.on(refs.table, "select", function(_, row)
            if type(row) == "table" and row.id then
                ST.select(row.id)
                ReferralClient.dialogs.openDetail(ST.selectedReferral())
            elseif type(row) == "number" then
                ST.select(row)
                ReferralClient.dialogs.openDetail(ST.selectedReferral())
            end
        end)
        N.on(refs.table, "doubleClick", function(_, row)
            if type(row) == "table" and row.id then
                ST.select(row.id)
                ReferralClient.dialogs.openDetail(ST.selectedReferral())
            end
        end)
        N.on(refs.table, "sort", function(_, key, descending)
            ST.setSort(key, descending)
        end)
    end
end

--============================================================--
--  BUILD
--============================================================--
function PAGE.build(parent)
    local panel = UI.panel(parent, 0, 0, W, H, { name = "pageReferrals" })
    if not panel then return nil end

    buildToolbar(panel)
    buildTable(panel)
    return panel
end

--============================================================--
--  DATA BINDING
--============================================================--
function PAGE.onData(panel, data)
    if not panel or not N.isElement(panel) then return end
    if type(data) ~= "table" then return end

    local rows = ST.filteredReferrals()

    if refs.count then
        local total = #ST.referrals()
        if ST.filters.query ~= "" or (ST.filters.status and ST.filters.status ~= "all") then
            N.patch(refs.count, { text = string.format("%d من %d نتيجة", #rows, total) })
        else
            N.patch(refs.count, { text = string.format("%d نتيجة", total) })
        end
    end

    --  empty vs filled
    if #rows == 0 then
        N.call(refs.table, "setVisible", false)
        N.call(refs.empty, "setVisible", true)
        if refs.empty then
            local total = #ST.referrals()
            if total == 0 then
                N.patch(refs.empty, {
                    title = "لا توجد احالات حتى الان",
                    message = "شارك كود الاحالة الخاص بك وابدأ بدعوة لاعبين جدد",
                })
            else
                N.patch(refs.empty, {
                    title = "لا توجد نتائج مطابقة",
                    message = "جرب تغيير كلمة البحث او الفلتر",
                })
            end
        end
        return
    end

    N.call(refs.empty, "setVisible", false)
    N.call(refs.table, "setVisible", true)

    UI.setRows(refs.table, rows)
    UI.setTableSort(refs.table, ST.filters.sortKey, ST.filters.sortDesc)
end

function PAGE.onShow(panel)
    --  keep the search box in sync when the player returns to the page
    if refs.search then
        N.patch(refs.search, { value = ST.filters.query })
    end
    if refs.filter then
        N.patch(refs.filter, { value = ST.filters.status or "all" })
    end
end

ReferralClient.navigation.register(PAGE)
