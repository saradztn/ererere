--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Client / Dialogs
--========================================================--
--  Referral detail (dialog + timeline), share sheet and the
--  "use a referral code" flow. All dialogs are NovaUI
--  components, created on demand and destroyed on close.
--========================================================--

ReferralClient = ReferralClient or {}
local N = ReferralClient.novaui
local UI = ReferralClient.ui
local ST = ReferralClient.state

local D = {}
ReferralClient.dialogs = D

--  open dialogs (one at a time per kind, no duplicates)
local open = {}

--============================================================--
--  SHARE
--============================================================--
local function inviteMessage(code)
    return "انضم الى السيرفر واستخدم كود الاحالة الخاص بي:\n" .. tostring(code)
end

function D.openShare()
    if open.share then
        N.call(open.share, "bringToFront")
        return open.share
    end

    local code = ST.code()
    local dialog = N.create("dialog", {
        title = "مشاركة كود الاحالة",
        subtitle = "شارك الكود مع اصدقائك",
        icon = "share",
        width = 460,
        height = 300,
        modal = true,
        name = "shareDialog",
    })
    if not dialog then return nil end
    open.share = dialog

    UI.create(dialog, "icon", {
        x = 380, y = 18, width = 34, height = 34,
        name = "shareInviteIcon", path = "assets/icons/invite.png", alpha = 200,
    })
    UI.label(dialog, 24, 20, 412, 20, "كودك", { name = "shareCodeLabel", size = 12, alpha = 180 })
    UI.label(dialog, 24, 42, 260, 40, (code ~= "" and code) or "--------",
        { name = "shareCode", size = 28, mono = true })

    local copyCode = UI.button(dialog, 300, 44, 136, 34, "نسخ الكود", {
        name = "shareCopyCode", icon = "copy", variant = "primary",
    })
    if copyCode then
        N.on(copyCode, "click", function(self)
            if UI.copyToClipboard(code) then
                UI.sound("copy")
                UI.flashIcon(self, "copy", "check", 1800)
                UI.notify({
                    type = "success", title = "تم النسخ",
                    message = "تم نسخ كود الاحالة بنجاح", duration = 2800,
                })
            else
                UI.toastError("تعذر النسخ", "النظام منع النسخ")
            end
        end)
    end

    UI.divider(dialog, 24, 100, 412)

    UI.label(dialog, 24, 112, 412, 20, "رسالة الدعوة", { name = "shareMsgLabel", size = 12, alpha = 180 })
    UI.create(dialog, "textarea", {
        x = 24, y = 134, width = 412, height = 76,
        name = "shareMessage",
        text = inviteMessage(code),
        readOnly = true,
        rtl = true,
    })

    local copyMessage = UI.button(dialog, 24, 220, 200, 34, "نسخ رسالة الدعوة", {
        name = "shareCopyMessage", icon = "copy",
    })
    if copyMessage then
        N.on(copyMessage, "click", function(self)
            if UI.copyToClipboard(inviteMessage(code)) then
                UI.sound("copy")
                UI.flashIcon(self, "copy", "check", 1800)
                UI.notify({
                    type = "success", title = "تم النسخ",
                    message = "تم نسخ رسالة الدعوة", duration = 2600,
                })
            else
                UI.toastError("تعذر النسخ", "النظام منع النسخ")
            end
        end)
    end

    local close = UI.button(dialog, 236, 220, 200, 34, "اغلاق", {
        name = "shareClose", icon = "close", variant = "ghost",
    })
    if close then
        N.on(close, "click", function() D.close("share") end)
    end

    N.on(dialog, "close", function() D.close("share") end)
    UI.fadeIn(dialog, 0)
    --  the dialog and everything inside it only reach NovaUI here, so the
    --  listeners registered above are already part of the props
    N.flush()
    return dialog
end

--============================================================--
--  USE A REFERRAL CODE
--============================================================--
function D.openApplyCode()
    if open.apply then
        N.call(open.apply, "bringToFront")
        return open.apply
    end

    local canUse = ST.data and ST.data.canUseCode
    if canUse == false then
        local message = (ST.data and ST.data.eligibleError == "already_used")
            and "لقد استخدمت كود احالة مسبقا" or "لا يمكنك استخدام كود احالة الان"
        UI.toastError("غير متاح", message)
        return nil
    end

    local dialog = N.create("dialog", {
        title = "استخدم كود احالة",
        subtitle = "ادخل كود اللاعب الذي دعاك",
        icon = "key",
        width = 440,
        height = 250,
        modal = true,
        name = "applyDialog",
    })
    if not dialog then return nil end
    open.apply = dialog

    UI.label(dialog, 24, 20, 392, 44,
        "ادخل كود الاحالة مرة واحدة فقط - لا تقدر تغيره بعد التطبيق",
        { name = "applyHint", size = 12, alpha = 180 })

    local edit = UI.create(dialog, "edit", {
        x = 24, y = 72, width = 392, height = 40,
        name = "applyEdit",
        placeholder = "اكتب الكود هنا",
        maxLength = 24,
        masked = false,
    })
    open.applyEdit = edit

    local submit = function()
        local value = ""
        if edit then
            if type(edit.getValue) == "function" then
                value = edit:getValue() or ""
            elseif type(edit.getText) == "function" then
                value = edit:getText() or ""
            end
        end
        value = Referral.trim(tostring(value)):upper()
        if value == "" then
            UI.toastError("كود فارغ", "اكتب كود الاحالة اولا")
            return
        end
        ST.applyCode(value)
    end

    local apply = UI.button(dialog, 24, 130, 190, 38, "تطبيق الكود", {
        name = "applySubmit", icon = "check", variant = "primary",
    })
    if apply then
        N.on(apply, "click", function() submit() end)
    end
    if edit then
        N.on(edit, "submit", function() submit() end)
    end

    local cancel = UI.button(dialog, 226, 130, 190, 38, "الغاء", {
        name = "applyCancel", icon = "close", variant = "ghost",
    })
    if cancel then
        N.on(cancel, "click", function() D.close("apply") end)
    end

    UI.label(dialog, 24, 182, 392, 40,
        "يتم التحقق من الكود على السيرفر - الكود غير الصالح يرفض تلقائيا",
        { name = "applyNote", size = 11, alpha = 150 })

    N.on(dialog, "close", function() D.close("apply") end)
    if edit then N.call(edit, "focus") end
    UI.fadeIn(dialog, 0)
    --  the dialog and everything inside it only reach NovaUI here, so the
    --  listeners registered above are already part of the props
    N.flush()
    return dialog
end

--============================================================--
--  REFERRAL DETAIL
--============================================================--
function D.openDetail(referral)
    if type(referral) ~= "table" then return nil end

    if open.detail then
        D.close("detail")
    end

    local dialog = N.create("dialog", {
        title = referral.player or "تفاصيل الاحالة",
        subtitle = "كود الاحالة رقم " .. tostring(referral.id or 0),
        icon = "user",
        width = 520,
        height = 470,
        modal = true,
        name = "detailDialog",
    })
    if not dialog then return nil end
    open.detail = dialog

    --  status badge
    UI.create(dialog, "badge", {
        x = 380, y = 22, width = 116, height = 26,
        name = "detailStatus",
        text = referral.statusLabel or "",
        color = referral.statusColor,
    })

    --  info grid
    local rows = {
        { label = "اسم اللاعب",    value = referral.player or "-" },
        { label = "مستوى اللاعب",  value = tostring(referral.level or 0) },
        { label = "وقت اللعب",     value = referral.playtimeText or "-" },
        { label = "تاريخ التسجيل", value = referral.registeredText or "-" },
        { label = "المكافأة",      value = referral.rewardText or "-" },
    }
    for index, row in ipairs(rows) do
        local y = 60 + (index - 1) * 34
        UI.label(dialog, 24, y, 150, 22, row.label, { name = "detailL" .. index, size = 12, alpha = 170 })
        UI.label(dialog, 180, y, 300, 22, row.value, { name = "detailV" .. index, size = 13 })
    end

    --  progress
    local progress = referral.progress or { done = 0, total = 2, percent = 0 }
    UI.label(dialog, 24, 236, 200, 20, "تقدم الاحالة", { name = "detailProgressLabel", size = 12, alpha = 180 })
    UI.create(dialog, "progressbar", {
        x = 24, y = 258, width = 472, height = 12,
        name = "detailProgress", value = progress.percent or 0, max = 100,
        color = referral.statusColor or "#60A5FA",
    })
    UI.label(dialog, 24, 274, 472, 20,
        string.format("%d من %d شروط مكتملة (%d%%)",
            progress.done or 0, progress.total or 0, progress.percent or 0),
        { name = "detailProgressText", size = 11, alpha = 160 })

    --  timeline
    UI.label(dialog, 24, 300, 200, 20, "مراحل الاحالة", { name = "detailTimelineLabel", size = 12, alpha = 180 })
    UI.create(dialog, "timeline", {
        x = 24, y = 322, width = 472, height = 108,
        name = "detailTimeline",
        items = referral.timeline or {},
        orientation = "vertical",
        compact = true,
    })

    local close = UI.button(dialog, 24, 436, 120, 30, "اغلاق", {
        name = "detailClose", icon = "close", variant = "ghost",
    })
    if close then
        N.on(close, "click", function() D.close("detail") end)
    end

    N.on(dialog, "close", function() D.close("detail") end)
    UI.fadeIn(dialog, 0)
    --  the dialog and everything inside it only reach NovaUI here, so the
    --  listeners registered above are already part of the props
    N.flush()
    return dialog
end

--============================================================--
--  CLOSE / CLEANUP
--============================================================--
function D.close(kind)
    local dialog = open[kind]
    if not dialog then return end
    open[kind] = nil
    if kind == "apply" then open.applyEdit = nil end
    N.call(dialog, "destroy")
end

function D.closeAll()
    for kind in pairs(open) do
        D.close(kind)
    end
end

function D.isOpen(kind)
    return open[kind] ~= nil
end
