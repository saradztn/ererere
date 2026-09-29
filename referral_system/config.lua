--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Configuration (shared)
--========================================================--
--  Every tunable value of the Referral System lives here.
--  Nothing in the UI, network, logic or storage layers hardcodes
--  a reward amount, a requirement or a status label.
--========================================================--

ReferralConfig = {}

--============================================================--
--  GENERAL
--============================================================--
ReferralConfig.enabled            = true       -- master switch
ReferralConfig.resourceName       = "referral_system"
ReferralConfig.debug              = false      -- verbose outputDebugString

--============================================================--
--  NOVAUI DEPENDENCY
--============================================================--
--  NovaUI is an EXTERNAL dependency. This resource never ships
--  NovaUI and never re-implements it. If your NovaUI resource
--  folder is named differently, change BOTH the <include> tag in
--  meta.xml and the first entry of this list.
--============================================================--
--  Every resource has its own Lua VM, so NovaUI's global table is unreachable
--  from here: the bridge talks to it through the exports NovaUI declares in its
--  meta.xml (novaCreate, novaDestroy, novaSetVisible, novaUpdate, novaCall,
--  novaOn, novaNotify, ...). `resourceNames` is what the bridge looks for.
--  NovaUI v3.0.0 must be the PATCHED build shipped in NovaUI.zip, otherwise
--  novaOn/novaCall/novaUpdate/novaAnimate do not exist and the dashboard loses
--  row selection, table updates and animations.
ReferralConfig.novaui = {
    resourceNames = { "NovaUI", "novaui", "nova_ui", "nova-ui", "NovaUIv3", "nova" },
    font          = "assets/fonts/arabic.ttf",
}

--============================================================--
--  USER INTERFACE
--============================================================--
ReferralConfig.ui = {
    openKey          = "F6",           -- key that toggles the dashboard
    closeKey         = "escape",       -- NovaUI window close key
    command          = "referral",     -- /referral  ->  /referral open | close
    windowTitle      = "نظام الاحالة",
    windowSubtitle   = "ادع لاعبين جدد واحصل على المكافآت",
    windowIcon       = "users",
    width            = 1100,
    height           = 660,
    minWidth         = 900,
    minHeight        = 560,
    sidebarWidth     = 238,
    sidebarCollapsed = false,
    recentCount      = 6,              -- rows shown in "اخر الاحالات"
    rowsPerPage      = 12,             -- referrals table page size
    autoOpenOnStart = false,           -- open the UI when the player joins
    sounds = {
        enabled = true,
        copy    = "assets/sounds/copy.wav",
        reward  = "assets/sounds/reward.wav",
        error   = "assets/sounds/error.wav",
        open    = "assets/sounds/open.wav",
    },
}

--============================================================--
--  REFERRAL CODE
--============================================================--
ReferralConfig.code = {
    length           = 8,             -- random part length
    alphabet         = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", -- no look-alike chars
    useAccountPrefix = true,          -- RAOUF-X72K  (account name + random part)
    prefixLength     = 5,
    maxAttempts      = 5,             -- anti brute force
    attemptWindow    = 60,            -- seconds
    cooldownSeconds  = 5,             -- delay between two code submissions
}

--============================================================--
--  REQUIREMENTS
--  A referral only pays out once the invited player satisfies
--  every enabled requirement.
--============================================================--
ReferralConfig.requirements = {
    requireLevel     = true,
    level            = 3,
    requirePlaytime  = true,
    playtimeMinutes  = 60,
    requireLoginDays = false,         -- optional extra requirement
    loginDays        = 1,
}

--============================================================--
--  REWARDS
--============================================================--
ReferralConfig.rewards = {
    perReferral   = 5000,             -- base reward for one completed referral
    currency      = "$",
    autoPay       = true,             -- pay the moment the referral completes
    giveMoney     = true,             -- use the built in player money
    handler       = nil,              -- function(player, amount, referral) custom payout
    notifyOwner   = true,             -- toast the owner when a reward lands
    --  Milestone tiers: extra bonus when N completed referrals are reached
    milestones = {
        { count = 5,  reward = 25000,  label = "5 احالات مكتملة"  },
        { count = 10, reward = 60000,  label = "10 احالات مكتملة" },
        { count = 25, reward = 150000, label = "25 احالة مكتملة"  },
        { count = 50, reward = 400000, label = "50 احالة مكتملة"  },
    },
}

--============================================================--
--  LIMITS
--============================================================--
ReferralConfig.maxReferrals = 0      -- 0 = unlimited
ReferralConfig.maxOpenReferralsPerOwner = 0   -- 0 = unlimited

--============================================================--
--  STATUSES
--  Add a new status type here and it appears in the filters,
--  the table badges and the statistics donut automatically.
--  key = stored value, label = Arabic label shown in the UI
--============================================================--
ReferralConfig.statuses = {
    pending   = { label = "قيد التحقق", color = "#FBBF24", badge = "warning", order = 1 },
    active    = { label = "نشط",        color = "#4ADE80", badge = "success", order = 2 },
    completed = { label = "مكتمل",      color = "#60A5FA", badge = "info",    order = 3 },
    rejected  = { label = "مرفوض",      color = "#F87171", badge = "error",   order = 4 },
}
ReferralConfig.defaultStatus = "pending"
ReferralConfig.statusOrder  = { "pending", "active", "completed", "rejected" }

--============================================================--
--  STORAGE
--  backend = "sqlite" | "mysql" | "memory"
--  Everything goes through server/storage.lua, no query is ever
--  written inside a UI file.
--============================================================--
ReferralConfig.storage = {
    backend    = "sqlite",
    sqlite = {
        file = "referrals.db",
    },
    mysql = {
        host     = "127.0.0.1",
        port     = 3306,
        user     = "root",
        password = "",
        database = "mta",
        options  = "unicode=true",
    },
    playtimeFlushSeconds = 30,   -- how often accumulated playtime is written
}

--============================================================--
--  TRACKING / GAMEMODE INTEGRATION
--  Playtime is measured by this resource. Level is read from your
--  gamemode through the export below (or element data).
--============================================================--
ReferralConfig.tracking = {
    playtime = true,
    level = {
        source      = "export",     -- "export" | "elementData" | "manual"
        resource    = "",           -- resource that owns getPlayerLevel
        functionName = "getPlayerLevel",
        elementData = "level",
        default     = 1,
    },
}

--============================================================--
--  NETWORK
--============================================================--
ReferralConfig.network = {
    requestTimeout = 8000,      -- ms before the UI shows the error state
    retryOnFail    = true,
}

--============================================================--
--  ADMIN PANEL OVERRIDES
--  Values configured from the MTA server admin panel
--  (see <settings> in meta.xml). Restart the resource after
--  changing them.
--============================================================--
do
    local function boolSetting(name, default)
        local value = get(name)
        if value == nil then return default end
        value = tostring(value):lower()
        if value == "true" or value == "1" or value == "yes" then return true end
        if value == "false" or value == "0" or value == "no" then return false end
        return default
    end

    local function numberSetting(name, default)
        local value = tonumber(get(name))
        if value == nil then return default end
        return value
    end

    local function textSetting(name, default)
        local value = get(name)
        if value == nil or value == "" then return default end
        return value
    end

    ReferralConfig.enabled               = boolSetting("enabled", ReferralConfig.enabled)
    ReferralConfig.rewards.perReferral   = numberSetting("rewardPerReferral", ReferralConfig.rewards.perReferral)
    ReferralConfig.code.length           = numberSetting("codeLength", ReferralConfig.code.length)
    ReferralConfig.maxReferrals          = numberSetting("maxReferrals", ReferralConfig.maxReferrals)
    ReferralConfig.ui.openKey            = textSetting("openKey", ReferralConfig.ui.openKey)
    ReferralConfig.ui.sidebarSide        = textSetting("sidebarSide", ReferralConfig.ui.sidebarSide)
end
