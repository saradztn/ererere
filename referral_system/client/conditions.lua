--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Conditions page
--========================================================--
--  Explains exactly how a reward is earned using NovaUI
--  stepper, timeline, cards and accordion.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state

local PAGE = { key = "conditions", label = "الشروط", icon = "info" }
ReferralClient.pages = ReferralClient.pages or {}
ReferralClient.pages.conditions = PAGE

local W = UI.layout.contentWidth
local H = UI.layout.pageHeight

local refs = {}

--============================================================--
--  STEPS (stepper + timeline share the same source)
--============================================================--
local function steps()
    local req = ReferralConfig.requirements
    return {
        {
            title = "يستخدم اللاعب كود الاحالة الخاص بك",
            description = "يسجل اللاعب الجديد في السيرفر ويدخل كودك مرة واحدة فقط",
            icon = "key",
        },
        {
            title = "يصل الى المستوى المطلوب",
            description = "المستوى المطلوب هو " .. tostring(req.level or 1),
            icon = "chart",
        },
        {
            title = "يكمل مدة اللعب المطلوبة",
            description = "مدة اللعب المطلوبة " .. Referral.formatDuration(req.playtimeMinutes or 0),
            icon = "clock",
        },
        {
            title = "يتم اعتماد الاحالة",
            description = "يراجع النظام الشروط تلقائيا ويعتمد الاحالة",
            icon = "shield",
        },
        {
            title = "تحصل على المكافأة",
            description = Referral.formatMoney(ReferralConfig.rewards.perReferral or 0)
                .. " لكل احالة مكتملة",
            icon = "gift",
        },
    }
end

--============================================================--
--  BUILD
--============================================================--
function PAGE.build(parent)
    local panel = UI.panel(parent, 0, 0, W, H, { name = "pageConditions" })
    if not panel then return nil end

    --  main explanation card with the stepper
    local main = UI.card(panel, 0, 0, 546, 300, "كيف تحصل على المكافأة", "info",
        { name = "conditionsMain" })
    if main then
        refs.stepper = UI.create(main, "stepper", {
            x = 18, y = 56, width = 510, height = 226,
            name = "conditionsStepper",
            steps = steps(),
            current = 1,
            orientation = "vertical",
        })
    end

    --  reward summary card
    local summary = UI.card(panel, 560, 0, 302, 300, "ملخص المكافآت", "gift",
        { name = "conditionsSummary" })
    if summary then
        UI.create(summary, "icon", {
            x = 254, y = 16, width = 30, height = 30,
            name = "summaryIcon", path = "assets/icons/achievement.png", alpha = 200,
        })
        local req = ReferralConfig.requirements
        local rows = {
            { label = "مكافاة كل احالة", value = Referral.formatMoney(ReferralConfig.rewards.perReferral or 0) },
            { label = "المستوى المطلوب", value = tostring(req.level or 1) },
            { label = "مدة اللعب المطلوبة", value = Referral.formatDuration(req.playtimeMinutes or 0) },
            { label = "الحد الاقصى للاحالات",
              value = (ReferralConfig.maxReferrals > 0) and tostring(ReferralConfig.maxReferrals) or "غير محدود" },
        }
        for index, row in ipairs(rows) do
            local y = 60 + (index - 1) * 46
            UI.label(summary, 18, y, 160, 22, row.label, { name = "condLabel" .. index, size = 12, alpha = 180 })
            UI.label(summary, 18, y + 20, 266, 24, row.value, { name = "condValue" .. index, size = 15 })
            UI.divider(summary, 18, y + 44, 266)
        end
    end

    --  milestone timeline
    local milestones = UI.card(panel, 0, 310, 546, H - 310, "اهداف المكافآت", "milestone",
        { name = "conditionsMilestones" })
    if milestones then
        local items = {}
        for _, tier in ipairs(ReferralConfig.rewards.milestones or {}) do
            items[#items + 1] = {
                title = tostring(tier.label or (tostring(tier.count) .. " احالات")),
                description = Referral.formatMoney(tier.reward or 0),
                icon = "star",
            }
        end
        refs.timeline = UI.create(milestones, "timeline", {
            x = 18, y = 56, width = 510, height = H - 310 - 68,
            name = "conditionsTimeline",
            items = items,
            orientation = "vertical",
        })
    end

    --  faq accordion
    local faq = UI.card(panel, 560, 310, 302, H - 310, "اسئلة شائعة", "info",
        { name = "conditionsFaq" })
    if faq then
        refs.accordion = UI.create(faq, "accordion", {
            x = 14, y = 54, width = 274, height = H - 310 - 68,
            name = "conditionsAccordion",
            items = {
                {
                    title = "متى تصلني المكافأة؟",
                    content = "تصل المكافأة تلقائيا لما اللاعب المدعو يكمل المستوى ومدة اللعب المطلوبة",
                },
                {
                    title = "اقدر استخدم كودي الخاص؟",
                    content = "لا - النظام يرفض استخدام نفس الكود او نفس اللاعب",
                },
                {
                    title = "كم مرة اقدر استخدم كود؟",
                    content = "مرة واحدة فقط لكل لاعب - لا يمكن تغيير الاحالة بعد اعتمادها",
                },
                {
                    title = "وش يصير لو اللاعب ترك السيرفر؟",
                    content = "تبقى الاحالة محفوظة وتكمل متى ما رجع اللاعب ولعب الوقت المطلوب",
                },
            },
        })
    end

    return panel
end

function PAGE.onData(panel, data)
    if not panel or not N.isElement(panel) then return end
    --  the conditions page is static configuration, it only needs
    --  the current progress of the player to highlight the step
    if not refs.stepper or type(data) ~= "table" or not data.stats then return end
    local completed = data.stats.completed or 0
    local current = 1
    if completed > 0 then current = 5 end
    N.patch(refs.stepper, { current = current })
end

ReferralClient.navigation.register(PAGE)
