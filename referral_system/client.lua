--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client entry
--========================================================--
--  Thin entry point: every client module is loaded by
--  meta.xml and registers itself, this file only starts the
--  main window controller once the resource is fully started.
--========================================================--

if not ReferralConfig then
    outputDebugString("[REFERRAL] config.lua was not loaded", 1)
    return
end

if not ReferralClient then
    ReferralClient = {}
end

local function start()
    if ReferralClient.initialized then return end
    ReferralClient.initialized = true
    if ReferralClient.main and ReferralClient.main.init then
        ReferralClient.main.init()
    else
        outputDebugString("[REFERRAL] client/main.lua is missing", 1)
    end
end

--  fires after every script of this resource has been loaded
addEventHandler("onClientResourceStart", resourceRoot, start)

--  safety net for late loading / hot restarts
setTimer(function()
    if getResourceState(resource) == "running" then
        start()
    end
end, 1000, 1)
