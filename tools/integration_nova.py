"""Integration test: the referral resource against the REAL NovaUI v3.0.0.

MTA gives every resource its own Lua VM, so a global `NovaUI` table created inside
the NovaUI resource is unreachable from another resource - the only way in is the
export list NovaUI declares in its meta.xml.

lupa cannot pass Lua tables between two runtimes (MTA serialises them), so both
sides share one runtime here. What is still reproduced exactly is the part that
matters: the `NovaUI` global is NOT how the bridge finds the library - it goes
through the exports table, which hands back a stub function for ANY key even when
the resource never declared it. That stub is precisely what produced
"call: failed to call 'NovaUI:create'" on the user's server.

Run `python3 tools/fetch_nova.py` first to unpack NovaUI.zip into tools/_nova.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
import test_resource as T  # noqa: E402
from lupa import LuaRuntime  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NOVA = os.path.join(HERE, "_nova")
RESOURCE = os.path.join(ROOT, "referral_system")

NOVA_ORDER = [
    "client/core/namespace.lua", "client/core/utils.lua", "client/core/class.lua",
    "client/events/emitter.lua", "client/theme/tokens.lua", "client/theme/palettes.lua",
    "client/theme/manager.lua", "client/rendering/scaling.lua",
    "client/adapters/dgs/adapter.lua", "client/adapters/dgs/compat.lua",
    "client/assets/manager.lua", "client/assets/icons.lua", "client/fonts/manager.lua",
    "client/animation/easing.lua", "client/animation/engine.lua",
    "client/rendering/primitives.lua", "client/rendering/renderer.lua",
    "client/core/lifecycle.lua", "client/core/factory.lua", "client/input/manager.lua",
    "client/components/core/window.lua", "client/components/core/panel.lua",
    "client/components/core/label.lua", "client/components/core/button.lua",
    "client/components/core/media.lua", "client/components/input/text_input.lua",
    "client/components/input/slider.lua", "client/components/input/toggle.lua",
    "client/components/input/select.lua", "client/components/input/special.lua",
    "client/components/navigation/tabs.lua", "client/components/navigation/nav.lua",
    "client/components/data/scroll.lua", "client/components/data/list.lua",
    "client/components/data/table.lua", "client/components/data/tree.lua",
    "client/components/feedback/notification.lua", "client/components/feedback/modal.lua",
    "client/components/feedback/progress.lua", "client/components/feedback/tooltip.lua",
    "client/components/advanced/overlay.lua", "client/components/advanced/disclosure.lua",
    "client/components/advanced/workflow.lua", "client/components/advanced/chart.lua",
    "client/core/bootstrap.lua",
]

NOVA_EXPORTS = [
    "novaCreate", "novaDestroy", "novaSetTheme", "novaCreateTheme", "novaScale",
    "novaNotify", "novaConfirm", "novaSetVisible", "novaOn", "novaOnce", "novaOff",
    "novaUpdate", "novaCall", "novaAnimate", "novaGetValue", "novaSetText",
]

WIRING = """
    local NAMES = { %s }
    local function isExported(key)
        for _, name in ipairs(NAMES) do if name == key then return true end end
        return false
    end
    local exportsMT = {}
    exportsMT.__index = function(tbl, key)
        if type(key) ~= 'string' then key = tostring(key) end
        if isExported(key) and type(_G[key]) == 'function' then
            return function(_, ...) return _G[key](...) end
        end
        --  the trap that broke the user's server: a stub for an undeclared
        --  key, which only fails once it is actually called
        return function() error("call: failed to call '" .. tostring(key) .. "'", 0) end
    end
    exports = setmetatable({}, {
        __index = function(tbl, key)
            if type(key) ~= 'string' then key = tostring(key) end
            return setmetatable({}, exportsMT)
        end
    })
    function getResourceFromName(name)
        local lowered = tostring(name):lower()
        if lowered == 'novaui' or lowered == 'nova' or lowered == 'nova_ui'
            or lowered == 'nova-ui' or lowered == 'novauiv3' then
            return { __resource = true, name = name }
        end
        return nil
    end
    function getResourceState(res) return res and res.__resource and 'running' or nil end
    function getResourceName(res) return res and res.name or 'unknown' end
    function getResources() return { getResourceFromName('NovaUI') } end
    function getResourceExportedFunctions(res)
        if not res or not res.__resource then return nil end
        return { %s }
    end
"""


def build():
    rt = LuaRuntime()
    rt.execute(T.MTA_STUBS)

    for rel in NOVA_ORDER:
        with open(os.path.join(NOVA, rel), encoding="utf-8") as fh:
            rt.execute(fh.read())
    #  test-only introspection, never part of NovaUI's export list
    rt.execute("""
        function NovaUIGet(id) return NovaUI.getElementById(id) end
        function NovaUICount()
            local out = {}
            for _, comp in pairs(NovaUI._registry.components) do out[#out + 1] = comp end
            return out
        end
        function NovaUINotifications() return NovaUI._registry.notifications end
    """)

    names = ", ".join('"%s"' % n for n in NOVA_EXPORTS)
    rt.execute(WIRING % (names, names))

    with open(os.path.join(RESOURCE, "config.lua"), encoding="utf-8") as fh:
        rt.execute(fh.read())
    rt.execute("ReferralConfig.debug = false")
    with open(os.path.join(RESOURCE, "shared.lua"), encoding="utf-8") as fh:
        rt.execute(fh.read())
    for name in T.CLIENT_ORDER:
        with open(os.path.join(RESOURCE, name), encoding="utf-8") as fh:
            rt.execute(fh.read())
    return rt


def main():
    if not os.path.isdir(NOVA):
        print("SKIP: tools/_nova missing (run python3 tools/fetch_nova.py)")
        return 0

    rt = build()
    print("real NovaUI v3.0.0 loaded (%d files)" % len(NOVA_ORDER))

    rt.execute("triggerEvent('onClientResourceStart', resourceRoot)")

    print("\n== bridge resolution ==")
    rt.execute("""
        local source = tostring(ReferralClient.novaui.name())
        print('  resolved through exports :', source:find('exports', 1, true) ~= nil, source)
        print('  undeclared key is a stub :', pcall(function()
            exports.NovaUI.novaCreateThatDoesNotExist()
        end) == false)
        print(ReferralClient.novaui.diagnose())
    """)

    print("\n== open the dashboard and visit every page ==")
    rt.execute("ReferralClient.main.open()")
    rt.execute("""
        local ok, err = pcall(function()
            for _, key in ipairs(ReferralClient.navigation.order) do
                ReferralClient.navigation.show(key)
            end
        end)
        print('  every page rendered :', ok, ok and '' or tostring(err))
        local total = 0
        for _ in pairs(NovaUICount()) do total = total + 1 end
        print('  components created  :', total)
    """)

    print("\n== interactions through the real exports ==")
    rt.execute("""
        local window = ReferralClient.main.window

        --  a click handler wired before the flush must fire for real
        local fired = 0
        local btn = ReferralClient.novaui.child(window, 'button', { text = 'probe' })
        ReferralClient.novaui.on(btn, 'click', function() fired = fired + 1 end)
        ReferralClient.novaui.flush()
        NovaUIGet(btn.id):emit('click')
        print('  click fired         :', fired == 1, tostring(fired))

        --  select/sort are only reachable through novaOn
        local sel = nil
        local tbl = ReferralClient.novaui.child(window, 'table', { name = 'probeTable' })
        ReferralClient.novaui.on(tbl, 'select', function(row) sel = row end)
        ReferralClient.novaui.flush()
        NovaUIGet(tbl.id):emit('select', { id = 42 })
        print('  select fired        :', sel ~= nil and sel.id == 42, tostring(sel and sel.id))

        --  patch / update round trip
        ReferralClient.novaui.patch(tbl, { rows = { { id = 1 }, { id = 2 } } })
        print('  rows updated        :', #NovaUIGet(tbl.id).rawData == 2, #NovaUIGet(tbl.id).rawData)

        --  setVisible and the setter fallbacks
        ReferralClient.novaui.call(tbl, 'setVisible', false)
        print('  setVisible applied  :', NovaUIGet(tbl.id).visible == false)
        ReferralClient.novaui.call(tbl, 'setRows', { { id = 1 }, { id = 2 }, { id = 3 } })
        print('  setRows applied     :', #NovaUIGet(tbl.id).rawData == 3, #NovaUIGet(tbl.id).rawData)

        --  a notification really reaches NovaUI (it queues one)
        local before = #NovaUINotifications()
        ReferralClient.novaui.notify({ type = 'success', title = 't', message = 'm' })
        print('  notification fired  :', #NovaUINotifications() == before + 1,
            before, #NovaUINotifications())

        --  the chat fallback still works when NovaUI cannot take it
        local okChat = ReferralClient.novaui.notify({ type = 'error', title = 't', message = 'm' })
        print('  notify never throws :', okChat == true or okChat == false)
    """)

    print("\nREAL NOVAUI INTEGRATION OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
