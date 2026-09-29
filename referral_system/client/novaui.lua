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
--
--  NovaUI exposes its factory in one of two shapes depending on the
--  build:
--      NovaUI:create("window", {...})   -- method style (self first)
--      NovaUI.create("window", {...})   -- function style
--  Both are tried automatically, and the convention that works is
--  remembered so the resource never pays for the probe twice.
--========================================================--

ReferralClient = ReferralClient or {}
local N = {}
ReferralClient.novaui = N

local api           = nil     -- resolved NovaUI api table
local resolvedName  = nil     -- where the api came from
local reported      = false   -- only warn once
local factoryStyle  = nil     -- "method" | "function" | nil (auto detect)
local probing       = false   -- guards against re-entrancy while probing
local dumped        = false   -- diagnostic printed once

--============================================================--
--  RESOLUTION
--============================================================--
local function resourceRunning(name)
    local res = getResourceFromName and getResourceFromName(name)
    if not res then return false end
    local state = getResourceState and getResourceState(res)
    return state == "running"
end

local function fromExports(name)
    if type(exports) ~= "table" then return nil end
    local ok, exp = pcall(function() return exports[name] end)
    if not ok or type(exp) ~= "table" then return nil end
    --  an unknown resource also returns an (empty) table, so the
    --  presence of a factory is what proves we found the library
    if type(exp.create) ~= "function" then return nil end
    return exp
end

local function fromGlobal()
    if type(NovaUI) == "table" and type(NovaUI.create) == "function" then
        return NovaUI
    end
    return nil
end

---Locate NovaUI. Safe to call repeatedly (cached after the first hit).
---Order: exports of a RUNNING resource -> global table -> exports of
---any resource. The official MTA mechanism (exports of a running
---resource) wins over a possibly stale global table.
function N.resolve(force)
    if api and not force then return api end

    local candidates = (ReferralConfig and ReferralConfig.novaui
        and ReferralConfig.novaui.resourceNames) or { "NovaUI" }

    for _, name in ipairs(candidates) do
        if resourceRunning(name) then
            local found = fromExports(name)
            if found then
                api, resolvedName = found, name .. " (exports)"
                Referral.log("NovaUI resolved via exports of the running resource", name)
                return api
            end
        end
    end

    local found = fromGlobal()
    if found then
        api, resolvedName = found, "global NovaUI table"
        Referral.log("NovaUI resolved via a global table")
        return api
    end

    for _, name in ipairs(candidates) do
        found = fromExports(name)
        if found then
            api, resolvedName = found, name .. " (exports)"
            Referral.log("NovaUI resolved via exports of", name)
            return api
        end
    end

    api, resolvedName = nil, nil
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

---Forget the cached api (used when NovaUI restarts).
function N.reset()
    api, resolvedName, factoryStyle = nil, nil, nil
    reported, dumped = false, false
end

--============================================================--
--  DIAGNOSTICS
--============================================================--
function N.reportMissing()
    if reported then return end
    reported = true
    Referral.warn("NovaUI v3.0.0 was not found - the referral dashboard cannot open")
    if outputChatBox then
        outputChatBox("#F87171[نظام الاحالة] #FFFFFFتعذر العثور على واجهة NovaUI - تاكد من تشغيل مورد NovaUI", 255, 255, 255, true)
    end
end

---Everything needed to debug a broken NovaUI wiring, as a string.
function N.diagnose()
    local lines = {}
    lines[#lines + 1] = "novaUI resolved: " .. tostring(N.resolve() ~= nil)
    lines[#lines + 1] = "novaUI source: " .. tostring(resolvedName or "none")
    lines[#lines + 1] = "factory style: " .. tostring(factoryStyle or "auto")
    lines[#lines + 1] = "candidates:"
    for _, name in ipairs(ReferralConfig.novaui.resourceNames) do
        local res = getResourceFromName and getResourceFromName(name)
        lines[#lines + 1] = string.format("   %-12s resource=%s state=%s exports=%s",
            name, tostring(res ~= nil),
            tostring(res and getResourceState(res) or "-"),
            tostring(type(exports) == "table" and type(exports[name]) == "table"
                and type(exports[name].create) == "function" or false))
    end
    lines[#lines + 1] = "global NovaUI: " .. tostring(type(NovaUI))
    if type(NovaUI) == "table" then
        lines[#lines + 1] = "global NovaUI.create: " .. tostring(type(NovaUI.create))
    end

    --  try a real creation and report the exact error
    local ui = N.resolve()
    if ui and type(ui.create) == "function" and not probing then
        probing = true
        local okMethod, errMethod = pcall(ui.create, ui, "label", { text = "probe", x = 0, y = 0 })
        local okFunc, errFunc = pcall(ui.create, "label", { text = "probe", x = 0, y = 0 })
        probing = false
        lines[#lines + 1] = "method style NovaUI:create(ui, kind, props) -> "
            .. tostring(okMethod) .. (okMethod and "" or (" / " .. tostring(errMethod)))
        lines[#lines + 1] = "function style NovaUI.create(kind, props) -> "
            .. tostring(okFunc) .. (okFunc and "" or (" / " .. tostring(errFunc)))
    end
    return table.concat(lines, "\n")
end

--============================================================--
--  FACTORY CALLS (both calling conventions)
--============================================================--
---Call a factory, trying method style first then function style.
---@return any element or nil, string error
local function callFactory(fn, self, kind, props, label)
    if factoryStyle == "method" then
        local ok, result = pcall(fn, self, kind, props)
        if ok and result ~= nil then return result end
        if ok then return nil, "nil element" end
        return nil, tostring(result)
    end

    if factoryStyle == "function" then
        local ok, result = pcall(fn, kind, props)
        if ok and result ~= nil then return result end
        if ok then return nil, "nil element" end
        return nil, tostring(result)
    end

    --  auto detect: method style (self first) is what NovaUI v3 uses
    local okMethod, resultMethod, errMethod = pcall(fn, self, kind, props)
    if okMethod and resultMethod ~= nil then
        factoryStyle = "method"
        Referral.log(label, "uses method style (NovaUI:create)")
        return resultMethod
    end
    if okMethod and resultMethod == nil then
        errMethod = "nil element"
    end

    local okFunc, resultFunc, errFunc = pcall(fn, kind, props)
    if okFunc and resultFunc ~= nil then
        factoryStyle = "function"
        Referral.log(label, "uses function style (NovaUI.create)")
        return resultFunc
    end
    if okFunc and resultFunc == nil then
        errFunc = "nil element"
    end

    return nil, tostring(errFunc or errMethod)
end

--============================================================--
--  GUARDED CALLS
--============================================================--
---Call a method on a NovaUI element without ever crashing the resource.
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

---Call a NovaUI helper (notify, animate, setFont, ...).
---Helpers are tried method style first, then as plain functions.
function N.invoke(helper, ...)
    local ui = N.resolve()
    if not ui then N.reportMissing() return false, nil end
    local fn = ui[helper]
    if type(fn) ~= "function" then
        Referral.log("NovaUI has no helper:", helper)
        return false, nil
    end
    local args = { ... }
    local ok, err = pcall(fn, ui, unpack(args))
    if not ok then
        ok, err = pcall(fn, unpack(args))
        if not ok then
            Referral.log("NovaUI helper failed:", helper, tostring(err))
            return false, nil
        end
    end
    return true, err
end

---Create a top level NovaUI component. Returns nil (never throws).
function N.create(kind, props)
    props = props or {}
    local ui = N.resolve()
    if not ui then N.reportMissing() return nil end
    if type(ui.create) ~= "function" then
        Referral.warn("NovaUI has no create() factory - wrong resource?")
        N.reportMissing()
        return nil
    end

    local element, err = callFactory(ui.create, ui, kind, props, "NovaUI")
    if not element then
        Referral.warn("NovaUI could not create", kind, "->", tostring(err))
        --  dump the wiring once so the exact reason is visible in the console
        if not dumped then
            dumped = true
            outputDebugString("[REFERRAL] NovaUI diagnostic:\n" .. N.diagnose(), 2)
        end
        return nil
    end
    return element
end

---Create a child component on a parent element.
function N.child(parent, kind, props)
    if not parent then return nil end
    props = props or {}
    if type(parent.create) ~= "function" then
        Referral.log("parent cannot create", kind)
        return nil
    end
    local element, err = callFactory(parent.create, parent, kind, props, "element")
    if not element then
        Referral.log("parent could not create", kind, "->", tostring(err))
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
