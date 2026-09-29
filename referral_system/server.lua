--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Server entry
--========================================================--
--  Thin entry point: the server bootstrap lives in
--  server/main.lua and is started by the onResourceStart
--  handler registered there.
--========================================================--

if not ReferralConfig then
    outputDebugString("[REFERRAL] config.lua was not loaded", 1)
    return
end

if not ReferralServer then
    ReferralServer = {}
end
