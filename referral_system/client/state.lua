--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / State + network
--========================================================--
--  Holds the last server snapshot and every network exchange.
--  Pages read from here and re-render through subscriptions,
--  so navigation never destroys or rebuilds the interface.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local ST = {}
ReferralClient.state = ST

ST.data      = nil      -- last good server payload
ST.loading   = false
ST.error     = nil      -- errorKey when the last request failed
ST.selected  = nil      -- selected referral id
ST.filters   = { query = "", status = "all", sortKey = "registeredAt", sortDesc = true }
ST.subs      = {}       -- change subscribers
ST.requestTimer = nil
ST.lastRequest  = 0

local EV = Referral.events

--============================================================--
--  OBSERVER
--============================================================--
function ST.subscribe(key, callback)
    ST.subs[key] = callback
end

function ST.unsubscribe(key)
    ST.subs[key] = nil
end

---Notify a single page (or every page when key is nil).
function ST.emit(key)
    for name, callback in pairs(ST.subs) do
        if (not key) or name == key then
            local ok, err = pcall(callback, ST.data)
            if not ok then
                Referral.warn("subscriber failed:", name, tostring(err))
            end
        end
    end
end

--============================================================--
--  ACCESSORS
--============================================================--
function ST.get()
    return ST.data
end

function ST.stats()
    return (ST.data and ST.data.stats) or nil
end

function ST.referrals()
    return (ST.data and ST.data.referrals) or {}
end

function ST.rewards()
    return (ST.data and ST.data.rewards) or {}
end

function ST.series()
    return (ST.data and ST.data.series) or {}
end

function ST.code()
    return (ST.data and ST.data.code) or ""
end

function ST.referralById(id)
    for _, referral in ipairs(ST.referrals()) do
        if referral.id == id then return referral end
    end
    return nil
end

function ST.selectedReferral()
    return ST.selected and ST.referralById(ST.selected) or nil
end

function ST.select(id)
    ST.selected = id
    ST.emit("referrals")
end

--============================================================--
--  FILTERING / SORTING (view only, never authoritative)
--============================================================--
function ST.setQuery(query)
    ST.filters.query = Referral.trim(query or "")
    ST.emit("referrals")
end

function ST.setStatusFilter(status)
    ST.filters.status = status or "all"
    ST.emit("referrals")
end

function ST.setSort(key, descending)
    ST.filters.sortKey = key or "registeredAt"
    ST.filters.sortDesc = descending and true or false
    ST.emit("referrals")
end

function ST.filteredReferrals()
    local rows = {}
    local query = ST.filters.query:lower()
    local status = ST.filters.status

    for _, row in ipairs(ST.referrals()) do
        local matchesQuery = true
        if query ~= "" then
            matchesQuery = (row.player or ""):lower():find(query, 1, true) ~= nil
                or tostring(row.id):find(query, 1, true) ~= nil
                or (row.account or ""):lower():find(query, 1, true) ~= nil
        end
        local matchesStatus = (status == "all" or status == nil or row.status == status)
        if matchesQuery and matchesStatus then
            rows[#rows + 1] = row
        end
    end

    local key = ST.filters.sortKey
    local descending = ST.filters.sortDesc
    table.sort(rows, function(a, b)
        local valueA = a[key]
        local valueB = b[key]
        if type(valueA) == "string" then
            valueA = valueA:lower()
            valueB = tostring(valueB or ""):lower()
        end
        valueA = valueA or 0
        valueB = valueB or 0
        if valueA == valueB then
            return (a.id or 0) < (b.id or 0)
        end
        if descending then
            return valueA > valueB
        end
        return valueA < valueB
    end)
    return rows
end

function ST.filteredRewards()
    return ST.rewards()
end

--============================================================--
--  NETWORK
--============================================================--
function ST.request()
    if ST.requestTimer and isTimer(ST.requestTimer) then
        killTimer(ST.requestTimer)
        ST.requestTimer = nil
    end

    ST.loading = true
    ST.lastRequest = Referral.now()
    ST.emit()

    local timeout = (ReferralConfig.network and ReferralConfig.network.requestTimeout) or 8000
    ST.requestTimer = setTimer(function()
        ST.requestTimer = nil
        if ST.loading then
            ST.loading = false
            ST.error = "no_data"
            ST.emit()
            N.notify({
                type = "error",
                title = "تعذر تحميل البيانات",
                message = "لم يستجب السيرفر - اضغط اعادة المحاولة",
                duration = 3400,
            })
        end
    end, timeout, 1)

    triggerServerEvent(EV.requestProfile, resourceRoot)
end

function ST.refresh()
    ST.request()
end

function ST.applyCode(code)
    triggerServerEvent(EV.applyCode, resourceRoot, code)
end

function ST.claimReward(rewardId)
    triggerServerEvent(EV.claimReward, resourceRoot, rewardId)
end

--============================================================--
--  SERVER MESSAGES
--============================================================--
local function onProfileData(payload)
    if ST.requestTimer and isTimer(ST.requestTimer) then
        killTimer(ST.requestTimer)
        ST.requestTimer = nil
    end
    ST.loading = false

    if type(payload) ~= "table" or payload.ok == false then
        ST.error = (payload and payload.errorKey) or "no_data"
        ST.data = nil
        ST.emit()
        return
    end

    ST.error = nil
    ST.data = payload

    --  keep the selection alive when the list changes
    if ST.selected and not ST.referralById(ST.selected) then
        ST.selected = nil
    end
    ST.emit()
end

local function onApplyResult(result)
    if type(result) ~= "table" then return end
    if result.claim then
        if result.ok then
            ReferralClient.ui.toastSuccess("تم الاستلام", result.message or "تم استلام المكافاة")
        else
            ReferralClient.ui.toastError("تعذر الاستلام", result.message or "لا توجد مكافاة متاحة")
        end
        return
    end

    if result.ok then
        ReferralClient.ui.toastSuccess("تم تطبيق الكود", result.message or "تم تطبيق كود الاحالة بنجاح")
        ReferralClient.ui.sound("reward")
        ST.request()
    else
        ReferralClient.ui.toastError("تعذر تطبيق الكود", result.message or "الكود غير صالح")
    end
end

local function onNotify(props)
    if type(props) ~= "table" then return end
    if props.sound and ReferralConfig.ui.sounds.enabled then
        pcall(playSound, props.sound)
        return
    end
    N.notify(props)
end

local function onRewardPaid(payload)
    ReferralClient.ui.sound("reward")
    local text = (type(payload) == "table" and payload.text) or Referral.formatMoney(0)
    N.notify({
        type = "success",
        title = "مكافاة جديدة",
        message = "تم اضافة " .. text .. " الى رصيدك",
        duration = 3600,
    })
    ST.request()
end

local function onStateChanged()
    ST.request()
end

local function onOpenUI()
    ReferralClient.main.open()
end

--============================================================--
--  INIT
--============================================================--
function ST.init()
    addEvent(EV.profileData, true)
    addEvent(EV.applyResult, true)
    addEvent(EV.notify, true)
    addEvent(EV.rewardPaid, true)
    addEvent(EV.stateChanged, true)
    addEvent(EV.openUI, true)

    addEventHandler(EV.profileData, localPlayer, onProfileData)
    addEventHandler(EV.applyResult, localPlayer, onApplyResult)
    addEventHandler(EV.notify, localPlayer, onNotify)
    addEventHandler(EV.rewardPaid, localPlayer, onRewardPaid)
    addEventHandler(EV.stateChanged, localPlayer, onStateChanged)
    addEventHandler(EV.openUI, localPlayer, onOpenUI)
end
