--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / NovaUI bridge
--========================================================--
--  This is NOT a UI framework. It only:
--    * locates the external NovaUI v3.0.0 resource
--    * exposes its API through guarded calls
--    * degrades gracefully (chat message) when NovaUI is absent
--  Every pixel is still drawn by NovaUI.
--========================================================--

ReferralClient = ReferralClient or {}
local N = {}
ReferralClient.novaui = N

local api          = nil      -- resolved NovaUI api table
local resolvedName = nil      -- resource name that provided it
local reported     = false    -- only warn once

--============================================================--
--  RESOLUTION
--============================================================--
local function resourceRunning(name)
    local res = getResourceFromName and getResourceFromName(name)
    if not res then return false end
    local state = getResourceState and getResourceState(res)
    return state == "running" or state == "running??"
end

local function fromExports(name)
    if type(exports) ~= "table" then return nil end
    local ok, exp = pcall(function() return exports[name] end)
    if not ok or type(exp) ~= "table" then return nil end
    if type(exp.create) ~= "function" then return nil end
    return exp
end

local function fromGlobal()
    if type(NovaUI) == "table" and type(NovaUI.create) == "function" then
        return NovaUI
    end
    return nil
end

---Locate NovaUI. Safe to call repeatedly (cheap after the first success).
function N.resolve(force)
    if api and not force then return api end

    local candidates = (ReferralConfig and ReferralConfig.novaui
        and ReferralConfig.novaui.resourceNames) or { "NovaUI" }

    -- 1. a global table (some NovaUI builds publish one)
    local found = fromGlobal()
    if found then
        api, resolvedName = found, "global:NovaUI"
        Referral.log("NovaUI resolved via global table")
        return api
    end

    -- 2. exports of a running resource
    for _, name in ipairs(candidates) do
        if resourceRunning(name) then
            found = fromExports(name)
            if found then
                api, resolvedName = found, name
                Referral.log("NovaUI resolved via exports of", name)
                return api
            end
        end
    end

    -- 3. last chance: exports of a resource that exists but is not running yet
    for _, name in ipairs(candidates) do
        found = fromExports(name)
        if found then
            api, resolvedName = found, name
            Referral.log("NovaUI resolved via exports (not running) of", name)
            return api
        end
    end

    api = nil
    return nil
end

function N.get()
    return N.resolve()
end

function N.name()
    if not api then N.resolve() end
    return resolvedName
end

function N.isReady()
    return N.resolve() ~= nil
end

---Tell the player (once) that the UI layer is missing.
function N.reportMissing()
    if reported then return end
    reported = true
    Referral.warn("NovaUI v3.0.0 was not found - the referral dashboard cannot open")
    if outputChatBox then
        outputChatBox("#F87171[نظام الاحالة] #FFFFFFتعذر العثور على واجهة NovaUI - تاكد من تشغيل مورد NovaUI", 255, 255, 255, true)
    end
end

--============================================================--
--  GUARDED CALLS
--============================================================--
---Call a method on a NovaUI element without ever crashing the resource.
---@return boolean ok, any result
function N.call(element, method, ...)
    if not element then return false, nil end
    local fn = element[method]
    if type(fn) ~= "function" then
        Referral.log("element has no method:", method)
        return false, nil
    end
    local ok, err = pcall(fn, element, ...)
    if not ok then
        Referral.warn("NovaUI call failed:", method, tostring(err))
        return false, nil
    end
    return true, err
end

---Call a NovaUI global helper (notify, animate, ...).
function N.invoke(helper, ...)
    local ui = N.resolve()
    if not ui then N.reportMissing() return false, nil end
    local fn = ui[helper]
    if type(fn) ~= "function" then
        Referral.log("NovaUI has no helper:", helper)
        return false, nil
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        Referral.warn("NovaUI helper failed:", helper, tostring(err))
        return false, nil
    end
    return true, err
end

---Create a NovaUI component. Returns nil (never throws) on failure.
function N.create(kind, props)
    local ui = N.resolve()
    if not ui then N.reportMissing() return nil end
    if type(ui.create) ~= "function" then N.reportMissing() return nil end
    local ok, element = pcall(ui.create, kind, props or {})
    if not ok or not element then
        Referral.warn("NovaUI could not create", kind, ok and "nil element" or tostring(element))
        return nil
    end
    return element
end

---Create a child component on a parent element.
function N.child(parent, kind, props)
    if not parent then return nil end
    if type(parent.create) ~= "function" then
        Referral.warn("parent cannot create", kind)
        return nil
    end
    local ok, element = pcall(parent.create, parent, kind, props or {})
    if not ok or not element then
        Referral.warn("parent could not create", kind, ok and "nil element" or tostring(element))
        return nil
    end
    return element
end

---Notification with a chat fallback when NovaUI is unavailable.
function N.notify(props)
    props = props or {}
    local ok = N.invoke("notify", props)
    if ok then return true end
    local color = "#60A5FA"
    if props.type == "success" then color = "#4ADE80"
    elseif props.type == "error" then color = "#F87171"
    elseif props.type == "warning" then color = "#FBBF24" end
    if outputChatBox then
        outputChatBox(color .. "[" .. tostring(props.title or "نظام الاحالة") .. "] #FFFFFF"
            .. tostring(props.message or ""), 255, 255, 255, true)
    end
    return false
end

---Animation helper, silently ignored when unsupported.
function N.animate(element, props)
    if not element then return false end
    if type(element.animate) == "function" then
        return N.call(element, "animate", props)
    end
    return N.invoke("animate", element, props)
end

---Register an event listener without ever double binding.
function N.on(element, eventName, handler)
    if not element or type(element.on) ~= "function" then return false end
    return N.call(element, "on", eventName, handler)
end

function N.once(element, eventName, handler)
    if not element or type(element.once) ~= "function" then return false end
    return N.call(element, "once", eventName, handler)
end

function N.off(element, eventName, handler)
    if not element or type(element.off) ~= "function" then return false end
    return N.call(element, "off", eventName, handler)
end

---Push new properties into an existing element (update or setters).
function N.patch(element, props)
    if not element or type(props) ~= "table" then return false end
    if type(element.update) == "function" then
        local ok = N.call(element, "update", props)
        if ok then return true end
    end
    for key, value in pairs(props) do
        local setter = "set" .. key:sub(1, 1):upper() .. key:sub(2)
        if type(element[setter]) == "function" then
            N.call(element, setter, value)
        end
    end
    return true
end
