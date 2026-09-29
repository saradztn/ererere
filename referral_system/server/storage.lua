--========================================================--
--  REFERRAL SYSTEM
--  Author: AI Agent
--  Module: Server / Storage
--========================================================--
--  The ONLY file that talks to a database.
--  Nothing else in the resource writes SQL.
--  Backends: sqlite (default) | mysql | memory (fallback)
--  Switching backend = one value in config.lua.
--========================================================--

ReferralServer = ReferralServer or {}
local S = {}
ReferralServer.storage = S

S.handle      = nil     -- db connection element
S.backend     = "sqlite"
S.ready       = false
S.usingMemory = false

local memory = {
    players   = {},
    referrals = {},
    rewards   = {},
    abuse     = {},
    nextId    = { players = 1, referrals = 1, rewards = 1, abuse = 1 },
}

--============================================================--
--  SCHEMA
--============================================================--
local function sqliteSchema()
    return {
        [[CREATE TABLE IF NOT EXISTS referral_players (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account TEXT NOT NULL,
            serial TEXT NOT NULL UNIQUE,
            code TEXT NOT NULL UNIQUE,
            used_code TEXT,
            referred_by INTEGER DEFAULT 0,
            level INTEGER DEFAULT 1,
            playtime_minutes INTEGER DEFAULT 0,
            login_days INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0
        )]],
        [[CREATE TABLE IF NOT EXISTS referral_referrals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_id INTEGER NOT NULL,
            invitee_id INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            reward_amount INTEGER DEFAULT 0,
            reward_claimed INTEGER DEFAULT 0,
            code_used_at INTEGER DEFAULT 0,
            registered_at INTEGER DEFAULT 0,
            level_reached_at INTEGER DEFAULT 0,
            playtime_reached_at INTEGER DEFAULT 0,
            completed_at INTEGER DEFAULT 0,
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0
        )]],
        [[CREATE TABLE IF NOT EXISTS referral_rewards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_id INTEGER NOT NULL,
            referral_id INTEGER DEFAULT 0,
            type TEXT NOT NULL DEFAULT 'referral',
            amount INTEGER DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at INTEGER DEFAULT 0,
            paid_at INTEGER DEFAULT 0
        )]],
        [[CREATE TABLE IF NOT EXISTS referral_abuse (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            serial TEXT,
            account TEXT,
            action TEXT,
            detail TEXT,
            created_at INTEGER DEFAULT 0
        )]],
        [[CREATE INDEX IF NOT EXISTS idx_referrals_owner ON referral_referrals (owner_id)]],
        [[CREATE INDEX IF NOT EXISTS idx_referrals_invitee ON referral_referrals (invitee_id)]],
        [[CREATE INDEX IF NOT EXISTS idx_rewards_owner ON referral_rewards (owner_id)]],
        [[CREATE INDEX IF NOT EXISTS idx_players_code ON referral_players (code)]],
    }
end

local function mysqlSchema()
    return {
        [[CREATE TABLE IF NOT EXISTS `referral_players` (
            `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `account` VARCHAR(64) NOT NULL,
            `serial` VARCHAR(64) NOT NULL UNIQUE,
            `code` VARCHAR(32) NOT NULL UNIQUE,
            `used_code` VARCHAR(32) NULL,
            `referred_by` INT NOT NULL DEFAULT 0,
            `level` INT NOT NULL DEFAULT 1,
            `playtime_minutes` INT NOT NULL DEFAULT 0,
            `login_days` INT NOT NULL DEFAULT 1,
            `created_at` INT NOT NULL DEFAULT 0,
            `updated_at` INT NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
        [[CREATE TABLE IF NOT EXISTS `referral_referrals` (
            `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `owner_id` INT NOT NULL,
            `invitee_id` INT NOT NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
            `reward_amount` INT NOT NULL DEFAULT 0,
            `reward_claimed` TINYINT NOT NULL DEFAULT 0,
            `code_used_at` INT NOT NULL DEFAULT 0,
            `registered_at` INT NOT NULL DEFAULT 0,
            `level_reached_at` INT NOT NULL DEFAULT 0,
            `playtime_reached_at` INT NOT NULL DEFAULT 0,
            `completed_at` INT NOT NULL DEFAULT 0,
            `created_at` INT NOT NULL DEFAULT 0,
            `updated_at` INT NOT NULL DEFAULT 0,
            INDEX (`owner_id`), INDEX (`invitee_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
        [[CREATE TABLE IF NOT EXISTS `referral_rewards` (
            `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `owner_id` INT NOT NULL,
            `referral_id` INT NOT NULL DEFAULT 0,
            `type` VARCHAR(32) NOT NULL DEFAULT 'referral',
            `amount` INT NOT NULL DEFAULT 0,
            `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
            `created_at` INT NOT NULL DEFAULT 0,
            `paid_at` INT NOT NULL DEFAULT 0,
            INDEX (`owner_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
        [[CREATE TABLE IF NOT EXISTS `referral_abuse` (
            `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `serial` VARCHAR(64) NULL,
            `account` VARCHAR(64) NULL,
            `action` VARCHAR(48) NULL,
            `detail` VARCHAR(255) NULL,
            `created_at` INT NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
    }
end

--============================================================--
--  INIT
--============================================================--
function S.init()
    local cfg = ReferralConfig and ReferralConfig.storage or {}
    S.backend = cfg.backend or "sqlite"

    if S.backend == "memory" then
        S.usingMemory = true
        S.ready = true
        Referral.log("storage: memory backend active (no database)")
        return true
    end

    local connection, err
    if S.backend == "mysql" then
        local my = cfg.mysql or {}
        connection, err = dbConnect("mysql",
            "dbname=" .. tostring(my.database) .. ";host=" .. tostring(my.host) ..
            ";port=" .. tostring(my.port), tostring(my.user), tostring(my.password),
            "unicode=true")
    else
        S.backend = "sqlite"
        connection, err = dbConnect("sqlite", tostring((cfg.sqlite or {}).file or "referrals.db"))
    end

    if not connection then
        Referral.warn("storage: dbConnect failed (" .. tostring(err) .. ") - falling back to memory")
        S.usingMemory = true
        S.ready = true
        return false
    end

    S.handle = connection

    local statements = (S.backend == "mysql") and mysqlSchema() or sqliteSchema()
    for _, statement in ipairs(statements) do
        local ok, result = pcall(dbExec, S.handle, statement)
        if not ok or result == false or result == nil then
            Referral.warn("storage: schema statement failed:", statement:sub(1, 60))
        end
    end

    S.ready = true
    Referral.log("storage: connected using", S.backend)
    return true
end

function S.isReady()   return S.ready end
function S.isMemory()  return S.usingMemory end
function S.backendName() return S.usingMemory and "memory" or S.backend end

--============================================================--
--  LOW LEVEL QUERY (sql backends only)
--============================================================--
---Execute a statement that returns no rows.
local function exec(sql, ...)
    if not S.handle then return false end
    local args = { ... }
    local ok, result = pcall(dbExec, S.handle, sql, unpack(args))
    if not ok then
        Referral.warn("storage: exec error:", tostring(result), sql:sub(1, 80))
        return false
    end
    return result ~= false
end

---Execute a query and return an array of row tables (never throws).
local function query(sql, ...)
    if not S.handle then return {} end
    local args = { ... }
    local ok, handle = pcall(dbQuery, S.handle, sql, unpack(args))
    if not ok or not handle then
        Referral.warn("storage: query error:", tostring(handle), sql:sub(1, 80))
        return {}
    end
    local okPoll, result = pcall(dbPoll, handle, -1)
    if not okPoll or type(result) ~= "table" then
        if type(result) == "string" then
            Referral.warn("storage: dbPoll:", result)
        end
        return {}
    end
    return result
end

local function lastInsertId()
    if not S.handle then return 0 end
    local sql = (S.backend == "mysql") and "SELECT LAST_INSERT_ID() AS id"
                                            or  "SELECT last_insert_rowid() AS id"
    local rows = query(sql)
    if rows[1] and tonumber(rows[1].id) then return math.floor(tonumber(rows[1].id)) end
    return 0
end

--============================================================--
--  MEMORY BACKEND HELPERS
--============================================================--
local function memoryInsert(tableName, row)
    local id = memory.nextId[tableName] or 1
    memory.nextId[tableName] = id + 1
    row.id = id
    memory[tableName][id] = row
    return id
end

local function memoryAll(tableName)
    local out = {}
    for _, row in pairs(memory[tableName]) do out[#out + 1] = row end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

--============================================================--
--  PLAYERS
--============================================================--
function S.getPlayerBySerial(serial)
    if not serial or serial == "" then return nil end
    if S.usingMemory then
        for _, row in pairs(memory.players) do
            if row.serial == serial then return row end
        end
        return nil
    end
    local rows = query("SELECT * FROM referral_players WHERE serial=?", serial)
    return rows[1]
end

function S.getPlayerByAccount(account)
    if not account or account == "" then return nil end
    if S.usingMemory then
        for _, row in pairs(memory.players) do
            if row.account == account then return row end
        end
        return nil
    end
    local rows = query("SELECT * FROM referral_players WHERE account=?", account)
    return rows[1]
end

function S.getPlayerById(id)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    if S.usingMemory then return memory.players[id] end
    local rows = query("SELECT * FROM referral_players WHERE id=?", id)
    return rows[1]
end

function S.getPlayerByCode(code)
    if not code or code == "" then return nil end
    code = code:upper()
    if S.usingMemory then
        for _, row in pairs(memory.players) do
            if row.code and row.code:upper() == code then return row end
        end
        return nil
    end
    local rows = query("SELECT * FROM referral_players WHERE UPPER(code)=?", code)
    return rows[1]
end

function S.createPlayer(account, serial)
    local now = Referral.now()
    if S.usingMemory then
        return memoryInsert("players", {
            account = account, serial = serial, code = "",
            used_code = "", referred_by = 0, level = 1,
            playtime_minutes = 0, login_days = 1,
            created_at = now, updated_at = now,
        })
    end
    exec([[INSERT INTO referral_players (account, serial, code, used_code, referred_by,
        level, playtime_minutes, login_days, created_at, updated_at)
        VALUES (?, ?, '', '', 0, 1, 0, 1, ?, ?)]], account, serial, now, now)
    return lastInsertId()
end

function S.updatePlayer(id, fields)
    id = tonumber(id) or 0
    if id <= 0 or type(fields) ~= "table" then return false end
    fields.updated_at = Referral.now()

    if S.usingMemory then
        local row = memory.players[id]
        if not row then return false end
        for key, value in pairs(fields) do row[key] = value end
        return true
    end

    local sets, values = {}, {}
    for key, value in pairs(fields) do
        sets[#sets + 1] = key .. "=?"
        values[#values + 1] = value
    end
    values[#values + 1] = id
    return exec("UPDATE referral_players SET " .. table.concat(sets, ", ") .. " WHERE id=?",
        unpack(values))
end

---Return the stored player row for a live player element, creating it once.
function S.ensurePlayer(player)
    if not isElement(player) then return nil end
    local account = getAccountName and getPlayerAccount(player)
        and (getAccountName(getPlayerAccount(player)) or "") or ""
    local serial = getPlayerSerial(player) or ""
    if serial == "" then return nil end

    local row = S.getPlayerBySerial(serial)
    if row then
        if row.account ~= account and account ~= "" then
            S.updatePlayer(row.id, { account = account })
            row.account = account
        end
        return row
    end

    local id = S.createPlayer(account ~= "" and account or ("guest_" .. serial:sub(1, 8)), serial)
    return S.getPlayerById(id)
end

--============================================================--
--  REFERRALS
--============================================================--
function S.createReferral(ownerId, inviteeId, status, rewardAmount)
    local now = Referral.now()
    if S.usingMemory then
        return memoryInsert("referrals", {
            owner_id = ownerId, invitee_id = inviteeId,
            status = status or ReferralConfig.defaultStatus,
            reward_amount = rewardAmount or 0, reward_claimed = 0,
            code_used_at = now, registered_at = now, level_reached_at = 0,
            playtime_reached_at = 0, completed_at = 0,
            created_at = now, updated_at = now,
        })
    end
    exec([[INSERT INTO referral_referrals (owner_id, invitee_id, status, reward_amount,
        code_used_at, registered_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
        ownerId, inviteeId, status or ReferralConfig.defaultStatus, rewardAmount or 0,
        now, now, now, now)
    return lastInsertId()
end

function S.getReferralById(id)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    if S.usingMemory then return memory.referrals[id] end
    return query("SELECT * FROM referral_referrals WHERE id=?", id)[1]
end

function S.getReferralsByOwner(ownerId)
    ownerId = tonumber(ownerId) or 0
    if ownerId <= 0 then return {} end
    if S.usingMemory then
        local out = {}
        for _, row in pairs(memory.referrals) do
            if row.owner_id == ownerId then out[#out + 1] = row end
        end
        table.sort(out, function(a, b) return (a.id or 0) > (b.id or 0) end)
        return out
    end
    return query("SELECT * FROM referral_referrals WHERE owner_id=? ORDER BY id DESC", ownerId)
end

function S.getReferralByInvitee(inviteeId)
    inviteeId = tonumber(inviteeId) or 0
    if inviteeId <= 0 then return nil end
    if S.usingMemory then
        for _, row in pairs(memory.referrals) do
            if row.invitee_id == inviteeId then return row end
        end
        return nil
    end
    return query("SELECT * FROM referral_referrals WHERE invitee_id=? LIMIT 1", inviteeId)[1]
end

function S.updateReferral(id, fields)
    id = tonumber(id) or 0
    if id <= 0 or type(fields) ~= "table" then return false end
    fields.updated_at = Referral.now()

    if S.usingMemory then
        local row = memory.referrals[id]
        if not row then return false end
        for key, value in pairs(fields) do row[key] = value end
        return true
    end

    local sets, values = {}, {}
    for key, value in pairs(fields) do
        sets[#sets + 1] = key .. "=?"
        values[#values + 1] = value
    end
    values[#values + 1] = id
    return exec("UPDATE referral_referrals SET " .. table.concat(sets, ", ") .. " WHERE id=?",
        unpack(values))
end

function S.countReferrals(ownerId, status)
    local rows = S.getReferralsByOwner(ownerId)
    if not status then return #rows end
    local n = 0
    for _, row in ipairs(rows) do
        if row.status == status then n = n + 1 end
    end
    return n
end

--============================================================--
--  REWARDS
--============================================================--
function S.createReward(ownerId, referralId, rewardType, amount, status)
    local now = Referral.now()
    if S.usingMemory then
        return memoryInsert("rewards", {
            owner_id = ownerId, referral_id = referralId or 0,
            type = rewardType or "referral", amount = amount or 0,
            status = status or "pending", created_at = now, paid_at = 0,
        })
    end
    exec([[INSERT INTO referral_rewards (owner_id, referral_id, type, amount, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?)]],
        ownerId, referralId or 0, rewardType or "referral", amount or 0,
        status or "pending", now)
    return lastInsertId()
end

function S.getRewardsByOwner(ownerId)
    ownerId = tonumber(ownerId) or 0
    if ownerId <= 0 then return {} end
    if S.usingMemory then
        local out = {}
        for _, row in pairs(memory.rewards) do
            if row.owner_id == ownerId then out[#out + 1] = row end
        end
        table.sort(out, function(a, b) return (a.id or 0) > (b.id or 0) end)
        return out
    end
    return query("SELECT * FROM referral_rewards WHERE owner_id=? ORDER BY id DESC", ownerId)
end

function S.updateReward(id, fields)
    id = tonumber(id) or 0
    if id <= 0 or type(fields) ~= "table" then return false end
    if S.usingMemory then
        local row = memory.rewards[id]
        if not row then return false end
        for key, value in pairs(fields) do row[key] = value end
        return true
    end
    local sets, values = {}, {}
    for key, value in pairs(fields) do
        sets[#sets + 1] = key .. "=?"
        values[#values + 1] = value
    end
    values[#values + 1] = id
    return exec("UPDATE referral_rewards SET " .. table.concat(sets, ", ") .. " WHERE id=?",
        unpack(values))
end

---Paid / pending totals for the reward KPI cards.
function S.getRewardSummary(ownerId)
    local paid, pending = 0, 0
    for _, row in ipairs(S.getRewardsByOwner(ownerId)) do
        if row.status == "paid" then
            paid = paid + (tonumber(row.amount) or 0)
        else
            pending = pending + (tonumber(row.amount) or 0)
        end
    end
    return { paid = paid, pending = pending }
end

--============================================================--
--  ABUSE LOG
--============================================================--
function S.logAbuse(serial, account, action, detail)
    local now = Referral.now()
    if S.usingMemory then
        memoryInsert("abuse", {
            serial = serial, account = account, action = action,
            detail = detail, created_at = now,
        })
        return true
    end
    return exec([[INSERT INTO referral_abuse (serial, account, action, detail, created_at)
        VALUES (?, ?, ?, ?, ?)]], serial, account, action, detail, now)
end

function S.countAbuse(serial, action, since)
    if not serial or serial == "" then return 0 end
    since = tonumber(since) or 0
    if S.usingMemory then
        local n = 0
        for _, row in pairs(memory.abuse) do
            if row.serial == serial and row.action == action and (row.created_at or 0) >= since then
                n = n + 1
            end
        end
        return n
    end
    local rows = query([[SELECT COUNT(*) AS total FROM referral_abuse
        WHERE serial=? AND action=? AND created_at>=?]], serial, action, since)
    if rows[1] and tonumber(rows[1].total) then return math.floor(tonumber(rows[1].total)) end
    return 0
end

--============================================================--
--  ANALYTICS (feeds the charts with real data)
--============================================================--
---Daily registration counts for the last `days` days.
function S.getDailySeries(ownerId, days)
    days = tonumber(days) or 7
    local rows = S.getReferralsByOwner(ownerId)
    local buckets = {}
    local now = Referral.now()
    local dayStart = now - (now % 86400)

    for i = days - 1, 0, -1 do
        buckets[#buckets + 1] = {
            label  = Referral.formatDate(dayStart - i * 86400):sub(6):gsub("/", "/"),
            offset = dayStart - i * 86400,
            value  = 0,
        }
    end

    for _, row in ipairs(rows) do
        local ts = tonumber(row.registered_at) or 0
        for _, bucket in ipairs(buckets) do
            if ts >= bucket.offset and ts < bucket.offset + 86400 then
                bucket.value = bucket.value + 1
                break
            end
        end
    end
    return buckets
end

---Daily reward totals for the last `days` days.
function S.getRewardSeries(ownerId, days)
    days = tonumber(days) or 7
    local rows = S.getRewardsByOwner(ownerId)
    local buckets = {}
    local now = Referral.now()
    local dayStart = now - (now % 86400)

    for i = days - 1, 0, -1 do
        buckets[#buckets + 1] = { label = Referral.formatDate(dayStart - i * 86400):sub(6), offset = dayStart - i * 86400, value = 0 }
    end

    for _, row in ipairs(rows) do
        --  paid_at is 0 until the reward is handed over, fall back to created_at
        local ts = tonumber(row.paid_at) or 0
        if ts == 0 then ts = tonumber(row.created_at) or 0 end
        if ts > 0 then
            for _, bucket in ipairs(buckets) do
                if ts >= bucket.offset and ts < bucket.offset + 86400 then
                    bucket.value = bucket.value + (tonumber(row.amount) or 0)
                    break
                end
            end
        end
    end
    return buckets
end

--============================================================--
--  MAINTENANCE
--============================================================--
function S.destroy()
    if S.handle and isElement(S.handle) then
        destroyElement(S.handle)
    end
    S.handle = nil
    S.ready = false
end
