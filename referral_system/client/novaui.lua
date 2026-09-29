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
--  HOW NOVAUI IS REACHED
--  ---------------------
--  MTA gives every resource its own Lua VM, so a global `NovaUI` table created
--  inside the NovaUI resource is NOT visible here - that is why the diagnostic
--  used to print "global NovaUI: nil". The only supported way in is the export
--  list NovaUI declares in its meta.xml:
--
--      novaCreate(typeName, props, parentId) -> component id (number) | false
--      novaDestroy(id) | novaSetVisible(id, bool) | novaUpdate(id, props)
--      novaCall(id, method, ...) | novaOn(id, event, handler)
--      novaOnce / novaOff / novaAnimate / novaGetValue / novaSetText
--      novaNotify(options) | novaConfirm(options)
--      novaSetTheme(name) | novaCreateTheme(...) | novaScale(v)
--
--  novaCreate returns an ID, not a component, so this bridge wraps every id in a
--  handle. The handle keeps the props it was built from, which is what makes
--  updates possible: there is no comp:update() across the VM boundary for every
--  property, so a patch is applied by rebuilding the component in place. The
--  handle object itself is stable, so code holding a reference keeps working
--  after a rebuild - only handle.id changes.
--
--  Because a handle is only turned into a real component when it is flushed,
--  event listeners registered with N.on() right after creation are collected
--  first and then handed to NovaUI as onClick/onChange/... props (NovaUI binds
--  those itself) or attached with novaOn for events it does not auto-bind.
--
--  Run `/referral debug` to see exactly what was found and what every probe
--  returned.
--========================================================--

ReferralClient = ReferralClient or {}
local N = {}
ReferralClient.novaui = N

--  every export NovaUI v3.0.0 declares, in the order we prefer to probe them
local EXPORT_KEYS = {
    "novaCreate", "novaDestroy", "novaSetVisible", "novaUpdate", "novaCall",
    "novaOn", "novaOnce", "novaOff", "novaAnimate", "novaGetValue", "novaSetText",
    "novaNotify", "novaConfirm", "novaSetTheme", "novaCreateTheme", "novaScale",
}

--  factory names a NovaUI-like build might publish instead of novaCreate
local FACTORY_KEYS = { "create", "Create", "new", "New", "component", "element",
                       "make", "build", "add", "createComponent", "createElement" }

--  events NovaUI binds itself when they arrive as props
local PROP_EVENTS = {
    click = "onClick", change = "onChange", hover = "onHover",
    focus = "onFocus", blur = "onBlur", close = "onClose", submit = "onSubmit",
}

local api          = nil      -- resolved NovaUI export table
local resolvedName = nil      -- where the api came from
local exportNames  = nil      -- name -> true, for exports that really exist
local reported     = false    -- "not found" warning already shown
local dumped       = false    -- diagnostic already dumped
local initialised  = false    -- optional NovaUI setup hook already called
local probing      = false    -- re-entrancy guard while probing
local pending      = {}       -- handles waiting to be created
local flushing     = false

--============================================================--
--  RESOLUTION
--============================================================--
local function resourceRunning(name)
    local res = getResourceFromName and getResourceFromName(name)
    if not res then return false end
    local state = getResourceState and getResourceState(res)
    return state == "running"
end

---Names a resource really exports (nil when the function is unavailable).
---Needed because `exports[name].anything` returns a *function* for ANY key in
---MTA - even one the resource never declared - so `type(...) == "function"`
---proves nothing. This is the check that tells a real export from a stub.
local function exportedNames(name)
    if type(getResourceExportedFunctions) ~= "function" then return nil end
    local res = getResourceFromName and getResourceFromName(name)
    if not res then return nil end
    local ok, list = pcall(getResourceExportedFunctions, res)
    if not ok or type(list) ~= "table" then return nil end
    return list
end

---The names NovaUI really exports.
---`exports[name].anything` is a function for ANY key in MTA - even one the
---resource never declared - so this is the only way to tell a real export from
---the stub that raises "call: failed to call ..." when it is used.
local function knownExports(force)
    if exportNames and not force then return exportNames end
    exportNames = {}
    if type(getResourceExportedFunctions) == "function" then
        local candidates = (ReferralConfig and ReferralConfig.novaui
            and ReferralConfig.novaui.resourceNames) or { "NovaUI" }
        for _, name in ipairs(candidates) do
            local res = getResourceFromName and getResourceFromName(name)
            if res then
                local ok, list = pcall(getResourceExportedFunctions, res)
                if ok and type(list) == "table" then
                    for _, exported in ipairs(list) do
                        if type(exported) == "string" then exportNames[exported] = true end
                    end
                end
            end
        end
        --  a resource may also be found outside the configured candidates
        if type(getResources) == "function" then
            for _, res in ipairs(getResources()) do
                local ok, list = pcall(getResourceExportedFunctions, res)
                if ok and type(list) == "table" then
                    for _, exported in ipairs(list) do
                        if type(exported) == "string" then exportNames[exported] = true end
                    end
                end
            end
        end
    end
    return exportNames
end

---Is this export really there (and not just a stub on the exports table)?
local function hasExport(name)
    if type(api) ~= "table" then return false end
    if type(api[name]) ~= "function" then return false end
    --  without getResourceExportedFunctions we cannot tell, so try it: a stub
    --  raises and the caller's pcall turns that into a graceful failure
    if type(getResourceExportedFunctions) ~= "function" then return true end
    return knownExports()[name] == true
end

---Does this resource export anything NovaUI shaped?
local function looksLikeNovaUI(name)
    local names = exportedNames(name)
    if not names then return false end
    for _, wanted in ipairs(EXPORT_KEYS) do
        for _, have in ipairs(names) do
            if have == wanted then return true end
        end
    end
    return false
end

---The exports table of a running resource that declares NovaUI's exports.
local function fromExports(name)
    if type(exports) ~= "table" then return nil end
    local ok, exp = pcall(function() return exports[name] end)
    if not ok or type(exp) ~= "table" then return nil end
    if looksLikeNovaUI(name) then return exp end
    --  no getResourceExportedFunctions: fall back to a live probe, because
    --  indexing the exports table would succeed for any name at all
    if type(getResourceExportedFunctions) ~= "function" and resourceRunning(name) then
        local okCall, result = pcall(function() return exp.novaCreate end)
        if okCall and type(result) == "function" then return exp end
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
---Order: exports of a RUNNING resource that declares NovaUI's exports ->
---global table -> exports of any such resource -> any running resource whose
---name contains "nova".
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

    --  last resort: a running resource whose name contains "nova"
    if type(getResources) == "function" then
        for _, res in ipairs(getResources()) do
            local name = getResourceName(res)
            if resourceRunning(name) and name:lower():find("nova", 1, true) then
                found = fromExports(name)
                if found then
                    api, resolvedName = found, name .. " (auto discovered)"
                    Referral.log("NovaUI auto discovered:", name)
                    return api
                end
            end
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

---Forget everything (used when NovaUI restarts).
function N.reset()
    api, resolvedName, exportNames = nil, nil, nil
    reported, dumped, initialised = false, false, false
    pending = {}
end

--============================================================--
--  HANDLES
--  A handle is a stable wrapper around a NovaUI component id. Code keeps the
--  handle; the id inside it may change when the component is rebuilt.
--============================================================--
local Handle = {}
Handle.__index = Handle

function Handle.new(kind, props, parent)
    return setmetatable({
        kind     = kind,
        props    = props or {},
        parent   = parent,
        id       = nil,      -- nil until flushed
        handlers = {},       -- event -> function, replayed on every rebuild
        children = {},       -- child handles, so a rebuild knows what it costs
        alive    = true,
        rebuilt  = 0,
    }, Handle)
end

---Does this handle have live children? Rebuilding would destroy them.
function Handle:hasChildren()
    if self.id == nil then return #self.children > 0 end
    for _, child in ipairs(self.children) do
        if child.alive then return true end
    end
    return false
end

function Handle:flush()
    if not self.alive or self.id ~= nil then return self end

    local ui = N.resolve()
    if not ui then return self end

    --  replay the registered listeners as props, NovaUI binds these itself
    local props = {}
    for key, value in pairs(self.props) do props[key] = value end
    for event, handler in pairs(self.handlers) do
        local propName = PROP_EVENTS[event]
        if propName and type(handler) == "function" then
            props[propName] = handler
        end
    end

    local parentId = self.parent and self.parent.id or nil
    local ok, id = N.rawCreate(ui, self.kind, props, parentId)
    if ok and id then
        self.id = id
        self.props = props
        --  events NovaUI does not bind from props need an explicit subscription
        for event, handler in pairs(self.handlers) do
            if not PROP_EVENTS[event] then
                N.rawOn(ui, id, event, handler)
            end
        end
    else
        self.alive = false
        Referral.warn("NovaUI could not create", self.kind, "->", tostring(id))
    end
    return self
end

function Handle:destroy()
    if not self.alive then return end
    self.alive = false
    if self.parent then
        for index, sibling in ipairs(self.parent.children) do
            if sibling == self then table.remove(self.parent.children, index) break end
        end
    end
    if self.id == nil then return end
    local ui = N.resolve()
    if ui then N.rawDestroy(ui, self.id) end
    --  the id is deliberately kept: a destroyed handle should still be able to
    --  say which NovaUI component it used to be
end

---Rebuild the component from merged props. The handle object is kept, so every
---reference to it stays valid.
function Handle:rebuild(newProps)
    for key, value in pairs(newProps or {}) do self.props[key] = value end
    if self.id == nil then return self end
    local oldId = self.id
    self.id = nil
    self:flush()
    if self.id and self.id ~= oldId then
        local ui = N.resolve()
        if ui then N.rawDestroy(ui, oldId) end
    end
    self.rebuilt = self.rebuilt + 1
    return self
end

function Handle:on(event, handler)
    self.handlers[event] = handler
    if self.id ~= nil then
        local ui = N.resolve()
        if ui then N.rawOn(ui, self.id, event, handler) end
    end
    return self
end

function Handle:once(event, handler)
    self.handlers[event] = handler
    if self.id ~= nil then
        local ui = N.resolve()
        if ui then N.rawOnce(ui, self.id, event, handler) end
    end
    return self
end

function Handle:off(event, handler)
    self.handlers[event] = nil
    if self.id ~= nil then
        local ui = N.resolve()
        if ui then N.rawOff(ui, self.id, event, handler) end
    end
    return self
end

function Handle:setVisible(visible)
    if self.id == nil then
        --  not created yet: remember the intent in the props
        self.props.visible = visible ~= false
        return self
    end
    local ui = N.resolve()
    if ui then N.rawSetVisible(ui, self.id, visible) end
    return self
end

function Handle:animate(spec)
    if self.id == nil then return self end
    local ui = N.resolve()
    if ui then N.rawAnimate(ui, self.id, spec) end
    return self
end

function Handle:update(newProps)
    return self:rebuild(newProps)
end

function Handle:getValue()
    if self.id == nil then return self.props.value end
    local ui = N.resolve()
    if ui then return N.rawGetValue(ui, self.id) end
    return self.props.value
end

function Handle:setText(text)
    self.props.text = text
    if self.id == nil then return self end
    local ui = N.resolve()
    if ui then N.rawSetText(ui, self.id, text) end
    return self
end

--  is this one of our handles?
local function isHandle(value)
    return type(value) == "table" and getmetatable(value) == Handle
end

--============================================================--
--  RAW EXPORT CALLS
--  Every one of these is guarded and never throws.
--============================================================--
function N.rawCreate(ui, kind, props, parentId)
    if hasExport("novaCreate") then
        local ok, result = pcall(ui.novaCreate, ui, kind, props, parentId)
        if ok then
            if type(result) == "number" or type(result) == "string" then return true, result end
            if type(result) == "table" and result.id ~= nil then return true, result.id end
            return false, "novaCreate returned " .. tostring(result)
        end
        return false, tostring(result)
    end
    --  a build that publishes a factory instead of the documented exports
    for _, key in ipairs(FACTORY_KEYS) do
        local fn = ui[key]
        if type(fn) == "function" then
            local ok, result = pcall(fn, ui, kind, props)
            if ok and type(result) == "table" then return true, result end
            if ok and type(result) == "table" and result.id ~= nil then return true, result.id end
        end
    end
    return false, "no factory available"
end

function N.rawDestroy(ui, id)
    if not hasExport("novaDestroy") then return false end
    local ok = pcall(ui.novaDestroy, ui, id)
    return ok
end

function N.rawSetVisible(ui, id, visible)
    if hasExport("novaSetVisible") then
        local ok, result = pcall(ui.novaSetVisible, ui, id, visible ~= false)
        if ok then return result == true end
    end
    return N.rawCall(ui, id, "setVisible", visible ~= false)
end

function N.rawOn(ui, id, event, handler)
    if hasExport("novaOn") then
        local ok, result = pcall(ui.novaOn, ui, id, event, handler)
        if ok then return result == true end
    end
    return N.rawCall(ui, id, "on", event, handler)
end

function N.rawOnce(ui, id, event, handler)
    if hasExport("novaOnce") then
        local ok, result = pcall(ui.novaOnce, ui, id, event, handler)
        if ok then return result == true end
    end
    return N.rawCall(ui, id, "once", event, handler)
end

function N.rawOff(ui, id, event, handler)
    if hasExport("novaOff") then
        local ok, result = pcall(ui.novaOff, ui, id, event, handler)
        if ok then return result == true end
    end
    return N.rawCall(ui, id, "off", event, handler)
end

function N.rawAnimate(ui, id, spec)
    if hasExport("novaAnimate") then
        local ok, result = pcall(ui.novaAnimate, ui, id, spec)
        if ok then return result == true end
    end
    return false
end

function N.rawGetValue(ui, id)
    if hasExport("novaGetValue") then
        local ok, value = pcall(ui.novaGetValue, ui, id)
        if ok then return value end
    end
    return nil
end

function N.rawSetText(ui, id, text)
    if hasExport("novaSetText") then
        local ok, result = pcall(ui.novaSetText, ui, id, text)
        if ok then return result == true end
    end
    return N.rawCall(ui, id, "setText", text)
end

---Generic "call a method on a component" - used for setRows/setData/setFilter/
---setSort/setType/bringToFront/focus/... which have no dedicated export.
function N.rawCall(ui, id, method, ...)
    if hasExport("novaCall") then
        --  novaCall answers false when the component has no such method, which
        --  is not the same as the call failing - report NovaUI's answer so the
        --  caller can fall back to rebuilding the component
        local ok, result = pcall(ui.novaCall, ui, id, method, ...)
        if ok then return result == true end
    end
    --  no novaCall: fall back to rebuilding with the property the method sets
    return false
end

---How many handles are still waiting to become real components.
function N.pending()
    return pending
end

---Turn a create into a handle, flushing everything that is still pending.
function N.flush()
    if flushing or #pending == 0 then return end
    flushing = true
    local queue = pending
    pending = {}
    for _, handle in ipairs(queue) do
        if handle.alive then handle:flush() end
    end
    flushing = false
end

--============================================================--
--  PUBLIC API
--============================================================--
---Create a top level NovaUI component. Returns a handle (never throws).
function N.create(kind, props)
    props = props or {}
    local ui = N.resolve()
    if not ui then N.reportMissing() return nil end

    local handle = Handle.new(kind, props, nil)
    pending[#pending + 1] = handle
    return handle
end

---Create a child component on a parent handle.
function N.child(parent, kind, props)
    if not parent then return nil end
    props = props or {}

    if isHandle(parent) then
        parent:flush()
        if not parent.alive then return nil end
        local handle = Handle.new(kind, props, parent)
        parent.children[#parent.children + 1] = handle
        pending[#pending + 1] = handle
        return handle
    end

    --  a raw NovaUI component table (only reachable through the global path)
    local ui = N.resolve()
    if not ui then N.reportMissing() return nil end
    local ok, id = N.rawCreate(ui, kind, props, parent)
    if not ok then
        Referral.log("parent could not create", kind, "->", tostring(id))
        return nil
    end
    return Handle.new(kind, props, nil)
end

---Truth test that works for both a handle and a raw NovaUI component.
---isElement() cannot be used on a handle: a handle is a plain Lua table, not an
---MTA element userdata, so MTA would answer false for a perfectly good window.
function N.isElement(element)
    if not element then return false end
    if isHandle(element) then return element.alive == true end
    if type(element) ~= "table" and type(element) ~= "userdata" then return false end
    return isElement(element)
end

---Call a method on an element without ever crashing the resource.
function N.call(element, method, ...)
    if not element then return false, nil end

    if isHandle(element) then
        if method == "setVisible" then
            element:setVisible((...) == true or (...) == nil)
            return true, nil
        end
        if method == "destroy" then
            element:destroy()
            return true, nil
        end
        if method == "on" or method == "once" or method == "off" then
            local event, handler = ...
            element[method](element, event, handler)
            return true, nil
        end
        if method == "animate" then
            element:animate((...))
            return true, nil
        end
        if method == "update" then
            element:update((...))
            return true, nil
        end
        if method == "getValue" then
            return true, element:getValue()
        end
        if method == "setText" then
            element:setText((...))
            return true, nil
        end

        --  setRows/setData/setItems/setFilter/setSort/setType/bringToFront/...
        --  map the method onto the property NovaUI reads at creation time
        local mapped = N.mapMethod(method, ...)
        if mapped then
            if element.id == nil then
                --  not created yet: just fold the properties into the props
                for key, value in pairs(mapped) do element.props[key] = value end
                return true, nil
            end
            local ui = N.resolve()
            if ui and N.rawCall(ui, element.id, method, ...) then
                return true, nil
            end
            element:rebuild(mapped)
            return true, nil
        end
        return false, nil
    end

    --  raw component object (global path): call it directly
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

---Map a NovaUI setter onto the props table the component is built from, so a
---component can be rebuilt when the direct call is unavailable.
function N.mapMethod(method, ...)
    local args = { ... }
    if method == "setRows" or method == "setData" or method == "setItems" then
        return { data = args[1], rows = args[1] }
    elseif method == "setFilter" then
        return { filter = args[1], query = args[1] }
    elseif method == "setSort" or method == "sortBy" then
        return { sortColumn = args[1], sortKey = args[1],
                 sortAscending = args[2] ~= false, sortAsc = args[2] ~= false }
    elseif method == "setType" then
        return { chartType = args[1] }
    elseif method == "setText" then
        return { text = args[1] }
    elseif method == "setValue" then
        return { value = args[1] }
    elseif method == "setPosition" then
        return { x = args[1], y = args[2] }
    elseif method == "setSize" then
        return { width = args[1], height = args[2] }
    elseif method == "setVisible" then
        return { visible = args[1] ~= false }
    end
    return nil
end

---Register an event listener. With the handle based bridge this is recorded and
---replayed on every rebuild, so it must be called before the first flush for the
---listener to reach NovaUI as a prop - which is how every call site uses it.
function N.on(element, eventName, handler)
    if not element then return false end
    if isHandle(element) then
        element:on(eventName, handler)
        return true
    end
    if type(element.on) ~= "function" then return false end
    return N.call(element, "on", eventName, handler)
end

function N.once(element, eventName, handler)
    if not element then return false end
    if isHandle(element) then
        element:once(eventName, handler)
        return true
    end
    if type(element.once) ~= "function" then return false end
    return N.call(element, "once", eventName, handler)
end

function N.off(element, eventName, handler)
    if not element then return false end
    if isHandle(element) then
        element:off(eventName, handler)
        return true
    end
    if type(element.off) ~= "function" then return false end
    return N.call(element, "off", eventName, handler)
end

---The properties Component:update() actually applies. Everything else
---(rows, data, columns, filter, chartType, icon, ...) is only read when a
---component is created, so those need a rebuild rather than an update.
local UPDATABLE_PROPS = {
    x = true, y = true, width = true, height = true, w = true, h = true,
    visible = true, disabled = true, enabled = true, alpha = true,
    value = true, text = true,
}

---Push new properties into an existing element.
function N.patch(element, props)
    if not element or type(props) ~= "table" then return false end
    if isHandle(element) then
        if element.id == nil then
            for key, value in pairs(props) do element.props[key] = value end
            return true
        end

        --  split: what an in-place update can do, and what needs a rebuild
        local updatable, rest = {}, {}
        for key, value in pairs(props) do
            if UPDATABLE_PROPS[key] then updatable[key] = value else rest[key] = value end
        end
        for key, value in pairs(updatable) do element.props[key] = value end

        if next(rest) == nil then
            N.resolve()
            if hasExport("novaUpdate") then
                local ok, result = pcall(api.novaUpdate, api, element.id, props)
                if ok and result ~= false then return true end
            end
            return true
        end

        --  rebuilding throws the component's children away, so it is only safe
        --  for a leaf - which is what every patched element here is
        if element:hasChildren() then
            Referral.warn("cannot patch", table.concat((function()
                local keys = {}
                for key in pairs(rest) do keys[#keys + 1] = key end
                table.sort(keys)
                return keys
            end)(), ","), "on a", element.kind, "that already has children")
            N.resolve()
            if hasExport("novaUpdate") then
                pcall(api.novaUpdate, api, element.id, updatable)
            end
            return false
        end

        element:rebuild(props)
        return true
    end
    if type(element.update) ~= "function" then return false end
    return N.call(element, "update", props)
end

---Animation helper, silently ignored when unsupported.
function N.animate(element, props)
    if not element then return false end
    if isHandle(element) then
        element:animate(props)
        return true
    end
    if type(element.animate) == "function" then
        return N.call(element, "animate", props)
    end
    return false
end

---Notification with a chat fallback when NovaUI is unavailable.
function N.notify(props)
    props = props or {}
    N.resolve()
    if hasExport("novaNotify") then
        local ok = pcall(api.novaNotify, api, props)
        if ok then return true end
    end
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

---Confirm dialog. Returns true when NovaUI handled it.
function N.confirm(props)
    props = props or {}
    N.resolve()
    if hasExport("novaConfirm") then
        local ok = pcall(api.novaConfirm, api, props)
        if ok then return true end
    end
    if type(props.onCancel) == "function" then pcall(props.onCancel) end
    return false
end

---Theme switch, ignored when NovaUI has no theme export.
function N.setTheme(name)
    N.resolve()
    if hasExport("novaSetTheme") then
        return pcall(api.novaSetTheme, api, name)
    end
    return false
end

---Scale a design pixel value the way NovaUI would.
function N.scale(value)
    N.resolve()
    if hasExport("novaScale") then
        local ok, scaled = pcall(api.novaScale, api, value)
        if ok and type(scaled) == "number" then return scaled end
    end
    return value
end

---Call any helper by name (kept for backwards compatibility).
function N.invoke(helper, ...)
    local ui = N.resolve()
    if not ui then N.reportMissing() return false, nil end
    if not hasExport(helper) and type(ui[helper]) ~= "function" then
        Referral.log("NovaUI has no helper:", helper)
        return false, nil
    end
    local args = { ... }
    local ok, err = pcall(ui[helper], ui, unpack(args))
    if not ok then
        ok, err = pcall(ui[helper], unpack(args))
        if not ok then
            Referral.log("NovaUI helper failed:", helper, tostring(err))
            return false, nil
        end
    end
    return true, err
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
    lines[#lines + 1] = "pending handles : " .. tostring(#pending)

    lines[#lines + 1] = "candidates:"
    local candidates = (ReferralConfig and ReferralConfig.novaui
        and ReferralConfig.novaui.resourceNames) or { "NovaUI" }
    for _, name in ipairs(candidates) do
        local res = getResourceFromName and getResourceFromName(name)
        local state = res and getResourceState(res) or "-"
        local names = exportedNames(name)
        lines[#lines + 1] = string.format("   %-12s exists=%-5s state=%-9s exports=%s",
            name, tostring(res ~= nil), tostring(state),
            names and ("[" .. table.concat(names, " "):sub(1, 160) .. "]") or "n/a")
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

    --  live probe: what does novaCreate actually hand back?
    if ui and not probing then
        probing = true
        lines[#lines + 1] = "probe results (what novaCreate returns):"
        for _, kind in ipairs({ "window", "panel", "label" }) do
            local ok, result = pcall(function()
                return ui.novaCreate(ui, kind, { x = 0, y = 0, width = 10, height = 10, text = "probe" })
            end)
            lines[#lines + 1] = string.format("   novaCreate(%-8s) -> %s%s",
                "\"" .. kind .. "\"", ok and "ok " or "ERROR ",
                ok and describe(result) or tostring(result):sub(1, 90))
            if ok and type(result) == "number" then
                pcall(ui.novaDestroy, ui, result)
            end
        end
        for _, helper in ipairs({ "novaOn", "novaUpdate", "novaCall", "novaAnimate", "novaGetValue" }) do
            lines[#lines + 1] = string.format("   %-12s present=%s",
                helper, tostring(type(ui[helper]) == "function"))
        end
        probing = false
    end
    return table.concat(lines, "\n")
end
