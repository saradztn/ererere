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
--  NovaUI builds differ in how the factory is published, so this bridge
--  probes (once) every plausible shape and remembers the winner:
--
--      NovaUI:create("window", {...})    method style
--      NovaUI.create("window", {...})    function style
--      NovaUI:create({ type = "window", ... })
--      exports.SomeName:create(...)
--
--  Run `/referral debug` to see exactly what was found and what every
--  probe returned.
--========================================================--

ReferralClient = ReferralClient or {}
local N = {}
ReferralClient.novaui = N

--  factory names NovaUI might publish, most likely first
local FACTORY_KEYS = { "create", "Create", "new", "New", "component", "element",
                       "make", "build", "add", "createComponent", "createElement" }

local api          = nil      -- resolved NovaUI api table
local resolvedName = nil      -- where the api came from
local reported     = false    -- "not found" warning already shown
local dumped       = false    -- diagnostic already dumped
local probing      = false    -- re-entrancy guard while probing
local initialised  = false    -- optional NovaUI setup hook already called
local factory      = nil      -- { name = "create", shape = "method" }

--============================================================--
--  RESOLUTION
--============================================================--
local function resourceRunning(name)
    local res = getResourceFromName and getResourceFromName(name)
    if not res then return false end
    local state = getResourceState and getResourceState(res)
    return state == "running"
end

---Names a resource exports (nil when the server build has no such function).
local function exportedNames(name)
    local res = getResourceFromName and getResourceFromName(name)
    if not res or type(getResourceExportedFunctions) ~= "function" then return nil end
    local ok, list = pcall(getResourceExportedFunctions, res)
    if not ok or type(list) ~= "table" then return nil end
    return list
end

local function fromExports(name)
    if type(exports) ~= "table" then return nil end
    local ok, exp = pcall(function() return exports[name] end)
    if not ok or type(exp) ~= "table" then return nil end
    --  an unknown resource also yields an (empty) table, so the presence
    --  of a factory is what proves we found a UI library
    for _, key in ipairs(FACTORY_KEYS) do
        if type(exp[key]) == "function" then return exp end
    end
    return nil
end

local function fromGlobal()
    if type(NovaUI) ~= "table" then return nil end
    for _, key in ipairs(FACTORY_KEYS) do
        if type(NovaUI[key]) == "function" then return NovaUI end
    end
    return nil
end

---Locate NovaUI. Cached after the first hit.
---Order: exports of a RUNNING resource -> global table -> exports of any
---resource -> any running resource whose name looks like NovaUI.
function N.resolve(force)
    if api and not force then return api end

    local candidates = (ReferralConfig and ReferralConfig.novaui
        and ReferralConfig.novaui.resourceNames) or { "NovaUI" }

    for _, name in ipairs(candidates) do
        if resourceRunning(name) then
            local found = fromExports(name)
            if found then
                api, resolvedName, factory = found, name .. " (exports)", nil
                Referral.log("NovaUI resolved via exports of the running resource", name)
                return api
            end
        end
    end

    local found = fromGlobal()
    if found then
        api, resolvedName, factory = found, "global NovaUI table", nil
        Referral.log("NovaUI resolved via a global table")
        return api
    end

    for _, name in ipairs(candidates) do
        found = fromExports(name)
        if found then
            api, resolvedName, factory = found, name .. " (exports)", nil
            Referral.log("NovaUI resolved via exports of", name)
            return api
        end
    end

    --  last resort: a running resource whose name contains "nova" and that
    --  exports something we can build components with
    if type(getResources) == "function" then
        for _, res in ipairs(getResources()) do
            local name = getResourceName(res)
            if resourceRunning(name) and name:lower():find("nova", 1, true) then
                found = fromExports(name)
                if found then
                    api, resolvedName, factory = found, name .. " (auto discovered)", nil
                    Referral.log("NovaUI auto discovered:", name)
                    return api
                end
            end
        end
    end

    api, resolvedName, factory = nil, nil, nil
    return nil
end

---Optional one-shot setup hook.
---Some NovaUI builds expose an init/setup function that must run before any
---component can be created (an uninitialised build is exactly what produces
---"attempt to perform arithmetic on field 'level'" inside the library).
---Set ReferralConfig.novaui.initFunction = "init" to enable it - it is never
---called automatically because the name differs between builds.
function N.ensureInitialised()
    if initialised then return true end
    local ui = N.resolve()
    if not ui then return false end

    local config = ReferralConfig and ReferralConfig.novaui or {}
    local name = config.initFunction
    if not name or name == "" then
        initialised = true
        return true
    end

    local fn = ui[name]
    if type(fn) ~= "function" then
        Referral.warn("NovaUI has no", name, "- check ReferralConfig.novaui.initFunction")
        initialised = true
        return false
    end

    local ok = pcall(fn, ui)
    if not ok then ok = pcall(fn) end
    initialised = true
    Referral.log("NovaUI setup hook called:", name, tostring(ok))
    return ok
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

---Forget everything (used when NovaUI restarts).
function N.reset()
    api, resolvedName, factory = nil, nil, nil
    reported, dumped, initialised = false, false, false
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

local function describe(value)
    if value == nil then return "nil" end
    local kind = type(value)
    if kind == "table" then
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        return "table {" .. table.concat(keys, ","):sub(1, 90) .. "}"
    end
    return kind .. " " .. tostring(value):sub(1, 60)
end

---Everything needed to debug a broken NovaUI wiring, as one string.
function N.diagnose()
    local lines = {}
    local ui = N.resolve()

    lines[#lines + 1] = "novaUI resolved : " .. tostring(ui ~= nil)
    lines[#lines + 1] = "novaUI source   : " .. tostring(resolvedName or "none")
    lines[#lines + 1] = "factory in use  : "
        .. (factory and (tostring(factory.name) .. " / " .. tostring(factory.shape)) or "not resolved yet")
    lines[#lines + 1] = "initFunction    : "
        .. tostring(ReferralConfig.novaui.initFunction or "not set (no setup hook called)")

    lines[#lines + 1] = "candidates:"
    local candidates = (ReferralConfig and ReferralConfig.novaui
        and ReferralConfig.novaui.resourceNames) or { "NovaUI" }
    for _, name in ipairs(candidates) do
        local res = getResourceFromName and getResourceFromName(name)
        local state = res and getResourceState(res) or "-"
        local names = exportedNames(name)
        lines[#lines + 1] = string.format("   %-12s exists=%-5s state=%-9s exports=%s",
            name, tostring(res ~= nil), tostring(state),
            names and ("[" .. table.concat(names, " "):sub(1, 120) .. "]") or "n/a")
    end

    lines[#lines + 1] = "global NovaUI   : " .. type(NovaUI)
    if type(NovaUI) == "table" then
        local keys = {}
        for key, value in pairs(NovaUI) do
            keys[#keys + 1] = tostring(key) .. "=" .. type(value)
        end
        table.sort(keys)
        lines[#lines + 1] = "global keys     : {" .. table.concat(keys, ", "):sub(1, 160) .. "}"
    end

    --  live probe: show what every shape actually RETURNS for the component
    --  kinds this resource needs, not just whether it raised an error
    if ui and not probing then
        probing = true
        lines[#lines + 1] = "probe results (what create returns):"
        for _, key in ipairs(FACTORY_KEYS) do
            local fn = ui[key]
            if type(fn) == "function" then
                for _, kind in ipairs({ "window", "panel", "label" }) do
                    local attempts = {
                        { label = string.format("%s:create(%q, props)", key, kind), run = function()
                            return fn(ui, kind, { x = 0, y = 0, width = 10, height = 10, text = "probe" })
                        end },
                        { label = string.format("%s.create(%q, props)", key, kind), run = function()
                            return fn(kind, { x = 0, y = 0, width = 10, height = 10, text = "probe" })
                        end },
                        { label = string.format("%s:create(props type=%q)", key, kind), run = function()
                            return fn(ui, { type = kind, x = 0, y = 0, width = 10, height = 10, text = "probe" })
                        end },
                    }
                    for _, attempt in ipairs(attempts) do
                        local ok, result = pcall(attempt.run)
                        lines[#lines + 1] = string.format("   %-34s -> %s%s",
                            attempt.label, ok and "ok " or "ERROR ",
                            ok and describe(result) or tostring(result):sub(1, 90))
                        if ok and type(result) == "table" and type(result.destroy) == "function" then
                            pcall(result.destroy, result)
                        end
                    end
                end
            end
        end
        probing = false
    end
    return table.concat(lines, "\n")
end

--============================================================--
--  FACTORY DISCOVERY
--============================================================--
local function isUsable(value)
    if value == nil or value == false then return false end
    local kind = type(value)
    return kind == "table" or kind == "userdata"
end

---Try every plausible calling shape until one returns a component.
---@return any element, string error
local function callFactory(owner, kind, props)
    local keys = {}
    if factory and factory.name then
        keys[1] = factory.name
    else
        for _, key in ipairs(FACTORY_KEYS) do keys[#keys + 1] = key end
    end

    local shapes = {
        { name = "method(kind, props)", run = function(fn)
            return fn(owner, kind, props)
        end },
        { name = "function(kind, props)", run = function(fn)
            return fn(kind, props)
        end },
        { name = "method(props)", run = function(fn)
            local merged = {}
            for key, value in pairs(props) do merged[key] = value end
            merged.type, merged.component = kind, kind
            return fn(owner, merged)
        end },
        { name = "function(props)", run = function(fn)
            local merged = {}
            for key, value in pairs(props) do merged[key] = value end
            merged.type, merged.component = kind, kind
            return fn(merged)
        end },
        { name = "method(kind)", run = function(fn)
            return fn(owner, kind)
        end },
        { name = "function(kind)", run = function(fn)
            return fn(kind)
        end },
    }

    local firstError

    --  fast path: a working convention is already known
    if factory and factory.name and factory.shape then
        local fn = owner[factory.name]
        if type(fn) == "function" then
            for _, shape in ipairs(shapes) do
                if shape.name == factory.shape then
                    local ok, result = pcall(shape.run, fn)
                    if ok and isUsable(result) then return result end
                    if not ok and not firstError then
                        firstError = tostring(result):sub(1, 120)
                    end
                    break
                end
            end
        end
        --  the known convention stopped working: fall through and re-probe
        factory = nil
    end

    --  probe every key/shape pair until one hands back a component
    for _, key in ipairs(keys) do
        local fn = owner[key]
        if type(fn) == "function" then
            for _, shape in ipairs(shapes) do
                local ok, result = pcall(shape.run, fn)
                if ok and isUsable(result) then
                    factory = { name = key, shape = shape.name }
                    Referral.log("NovaUI factory resolved:", key, shape.name)
                    return result
                end
                if not ok and not firstError then
                    firstError = tostring(result):sub(1, 120)
                end
            end
        end
    end
    return nil, firstError or "every calling convention returned nil"
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
    N.ensureInitialised()

    local element, err = callFactory(ui, kind, props)
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
    if type(parent) ~= "table" and type(parent) ~= "userdata" then return nil end

    local element, err = callFactory(parent, kind, props)
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
