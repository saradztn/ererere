# Referral System — نظام الاحالة

A production ready **MTA:SA referral management dashboard** built **on top of NovaUI v3.0.0**.

```
Referral System  →  NovaUI v3.0.0  →  MTA:SA
```

NovaUI is **not** included, re-implemented or replaced. Every pixel, button, table,
chart, dialog and notification is a NovaUI component. This resource is only the
application layer: referral logic, validation, storage and page composition.

---

## 1. Requirements

| Requirement | Notes |
|---|---|
| MTA:SA server | 1.5.9 or newer |
| **NovaUI v3.0.0** | must be installed and running next to this resource |
| `sqlite` db module | bundled with the MTA server (`mods/deathmatch`) |

---

## 2. Installation

1. Copy the `referral_system` folder into your server:

   ```
   resources/
   ├── [naui]/NovaUI/        ← your existing NovaUI resource
   └── [scripts]/referral_system/
   ```

2. **Check the NovaUI resource name.** `meta.xml` declares:

   ```xml
   <include resource="NovaUI" />
   ```

   If your NovaUI folder is called something else (`novaui`, `nova_ui`, `NovaUIv3`, …)
   change that tag **and** the first entry of the candidate list in `config.lua`:

   ```lua
   ReferralConfig.novaui = {
       resourceNames = { "NovaUI", "novaui", "nova_ui", "nova-ui", "NovaUIv3", "nova" },
       font          = "assets/fonts/arabic.ttf",
   }
   ```

   The client resolves NovaUI through the `exports` of a **running** resource first,
   then through a global `NovaUI` table, then through the exports of any candidate,
   so a differently named build still works without code changes. If NovaUI cannot
   be found the resource does **not** crash — it prints a chat message and refuses
   to open the dashboard.

   > **Calling convention.** NovaUI v3 declares its factory as a *method*
   > (`NovaUI:create("window", {...})`), which is why MTA reports a broken call as
   > `failed to call 'NovaUI:create'`. `client/novaui.lua` probes **both**
   > conventions (`NovaUI:create(...)` and `NovaUI.create(...)`) and remembers the
   > one that works, so either build is supported. The same applies to element
   > factories (`window:create("panel", {...})`).

   If the dashboard will not open, run `/referral debug` and read the server
   console: it prints the resolved source, the state of every candidate resource,
   whether `exports` expose a `create` function, whether a global `NovaUI` table
   exists, and the result of a live probe with both calling conventions.

3. Add it to the server config (or start it manually):

   ```
   start referral_system
   ```

4. In game: press **F6** or type `/referral`.

---

## 3. Controls

| Input | Action |
|---|---|
| `F6` | open / close the dashboard (`ReferralConfig.ui.openKey`) |
| `ESC` | close the window (handled by NovaUI) |
| `/referral` | open |
| `/referral close` | close |
| `/referral toggle` | toggle |
| `/referral debug` | print the NovaUI wiring + a live factory probe to the server console (F8) |

---

## 4. Interface

One single NovaUI window (`1100 × 660`, minimum `900 × 560`) with a NovaUI sidebar.
Pages are created once and switched with `setVisible()` — nothing is destroyed or
rebuilt while navigating.

| Page | Content |
|---|---|
| **الرئيسية** (dashboard) | hero referral code card (copy / share), next-reward progression with progressbar, 4 KPI stat cards, recent referrals list, quick actions |
| **الاحالات** (referrals) | searchbox + status dropdown + refresh, sortable NovaUI table (ID, player, registration date, level, playtime, status, reward), row selection → detail dialog with timeline |
| **المكافآت** (rewards) | received / pending / total KPI cards, reward history table, claim button for pending rewards |
| **الاحصائيات** (statistics) | area chart (7 days), donut chart (status breakdown), bar chart (weekly rewards), supporting stat cards |
| **الشروط** (conditions) | stepper, milestone timeline, reward summary, FAQ accordion |

Every section has real **empty**, **loading** and **error** states (never a blank
panel). Micro interactions: copy → `check` icon → success toast, refresh spin,
row highlight, smooth active indicator, soft entrance stagger.

---

## 5. Configuration — `config.lua`

Everything tunable lives in one file. Highlights:

```lua
ReferralConfig.enabled            = true
ReferralConfig.ui.openKey         = "F6"
ReferralConfig.ui.command         = "referral"
ReferralConfig.ui.width           = 1100      -- window size
ReferralConfig.ui.sidebarSide     = "right"   -- "right" | "left"

ReferralConfig.code.length        = 8         -- RAOUF-X72K
ReferralConfig.code.maxAttempts   = 5         -- brute force protection
ReferralConfig.code.cooldownSeconds = 5

ReferralConfig.requirements = {
    requireLevel    = true,  level           = 3,
    requirePlaytime = true,  playtimeMinutes = 60,
    requireLoginDays = false, loginDays      = 1,
}

ReferralConfig.rewards.perReferral = 5000      -- reward for one completed referral
ReferralConfig.rewards.autoPay     = true      -- false = manual claim
ReferralConfig.rewards.giveMoney   = true      -- uses givePlayerMoney
ReferralConfig.rewards.handler     = nil       -- function(player, amount, referral)
ReferralConfig.rewards.milestones  = { { count = 5, reward = 25000, ... }, ... }

ReferralConfig.maxReferrals = 0                -- 0 = unlimited
ReferralConfig.storage.backend = "sqlite"      -- "sqlite" | "mysql" | "memory"
```

### Reward values

Change `ReferralConfig.rewards.perReferral` (or the `reward` field of a milestone).
The amount is **never** taken from the client: `server/validation.lua:V.computeRewardAmount()`
recomputes it from the config at payout time.

### Adding a requirement

1. Add the rule to `ReferralConfig.requirements` (`requireX = true`, `x = value`).
2. Extend `V.requirementsMet()` and `V.requirementProgress()` in
   `server/validation.lua` — the progress bar, the dialog and the conditions page
   read from there automatically.

### Adding a new status type

Add one entry to `ReferralConfig.statuses` (and to `statusOrder`):

```lua
ReferralConfig.statuses.banned = { label = "محظور", color = "#F87171", badge = "error", order = 5 }
```

It immediately appears in the referrals filter dropdown, the table badges, the
statistics donut and the shared `Referral.getStatuses()` helper. Use the key
(`"banned"`) as the stored value in the database.

### Theme / colours

Statuses carry their own colour in `config.lua`. Charts and cards pass
`color = "#RRGGBB"` when the NovaUI component is created (see
`client/dashboard.lua`, `client/statistics.lua`). To re-theme, change those values
or the NovaUI theme itself — no NovaUI file is modified here.

### Font

The UI uses `assets/fonts/arabic.ttf` (Cairo, full Arabic + Latin coverage). It is
handed to NovaUI through the window `font` property and, when available, NovaUI's
font manager (`NovaUI.setFont` / `NovaUI.useFont`). There is **no** custom font
renderer in this resource.

---

## 6. Custom icons

`assets/icons/` contains 15 transparent 128×128 PNGs generated as one consistent
family (same grid, same stroke weight, same optical size, monochrome so NovaUI can
tint them):

```
referral  referral-link  invite  share  reward  gift  user-add  team
growth  coins  wallet  milestone  achievement  activity  analytics
```

NovaUI built-in icons are still used wherever they exist (`copy`, `refresh`,
`search`, `users`, `gift`, `chart`, `info`, `key`, `check`, `close`, `warning`,
`clock`, `shield`, `star`, `sliders`). To replace a custom icon, drop a PNG with
the same name into `assets/icons/` (keep it transparent and roughly 24×24 optically).

---

## 7. Architecture

```
referral_system/
├── meta.xml                 NovaUI dependency, scripts, assets, exports, settings
├── config.lua               every tunable value (+ admin panel overrides)
├── shared.lua               shared helpers, event names, formatters, statuses
├── client.lua               client entry (starts the window controller)
├── server.lua               server entry
├── client/
│   ├── novaui.lua           NovaUI bridge: resolve + guarded calls (no rendering)
│   ├── ui.lua               component wrappers, empty/loading/error blocks, animations
│   ├── state.lua            server snapshot + network layer + observers
│   ├── navigation.lua       sidebar, breadcrumb, lazy page container
│   ├── dashboard.lua        hero code card, KPIs, recent referrals, progression
│   ├── referrals.lua        toolbar, sortable table, empty state, selection
│   ├── rewards.lua          reward KPIs, history table, claiming
│   ├── statistics.lua       area / donut / bar charts from real data
│   ├── conditions.lua       stepper, timeline, summary, accordion
│   ├── dialogs.lua          detail dialog, share sheet, apply-code dialog
│   └── main.lua             single window, keybind, command, cursor, overlay
├── server/
│   ├── storage.lua          the ONLY file that talks to a database
│   ├── validation.lua       pure server side rules + error messages
│   ├── referrals.lua        codes, redemption, progress, read models
│   ├── rewards.lua          eligibility, payout, milestones, claims
│   └── main.lua             bootstrap, events, playtime/level tracking, exports
└── assets/
    ├── fonts/arabic.ttf
    ├── icons/*.png
    └── sounds/*.wav
```

Layer rules: **UI never queries a database**, **storage never builds UI**,
**the client never decides a reward**.

---

## 8. Storage & database schema

`server/storage.lua` is the isolated storage layer. `backend` selects the driver:

* `sqlite` (default) — `dbConnect("sqlite", "referrals.db")`
* `mysql` — `dbConnect("mysql", ...)` using `ReferralConfig.storage.mysql`
* `memory` — in-memory fallback, used automatically if `dbConnect` fails
  (the resource still runs, data is simply not persisted)

Tables (created automatically):

```sql
referral_players   (id, account, serial UNIQUE, code UNIQUE, used_code,
                    referred_by, level, playtime_minutes, login_days,
                    created_at, updated_at)

referral_referrals (id, owner_id, invitee_id, status, reward_amount,
                    reward_claimed, code_used_at, registered_at,
                    level_reached_at, playtime_reached_at, completed_at,
                    created_at, updated_at)

referral_rewards   (id, owner_id, referral_id, type, amount, status,
                    created_at, paid_at)

referral_abuse     (id, serial, account, action, detail, created_at)
```

To migrate to an existing database: point `ReferralConfig.storage.mysql` at it and
prefix the table names inside `mysqlSchema()` — no other file changes.

---

## 9. Network events

| Direction | Event | Purpose |
|---|---|---|
| C → S | `referral:requestProfile` | ask for the full snapshot |
| S → C | `referral:profileData` | snapshot `{ ok, code, stats, referrals, rewards, series }` |
| C → S | `referral:applyCode` | submit a referral code |
| S → C | `referral:applyResult` | `{ ok, errorKey, message }` |
| C → S | `referral:claimReward` | claim a pending reward |
| S → C | `referral:notify` | server initiated toast |
| S → C | `referral:rewardPaid` | celebrate a payout |
| S → C | `referral:stateChanged` | push a refresh |
| S → C | `referral:openUI` | server opens the dashboard |
| C → S | `referral:reportLevel` / `referral:reportPlaytime` | gamemode reporting |

Server side events fired for other resources:
`onReferralCodeApplied`, `onReferralCompleted`, `onReferralRewardPaid`,
`onReferralRejected`.

---

## 10. Server security

Everything sensitive is server side. The client may **never** define the reward
amount, the referral owner, the status or the completion state.

Blocked / validated server side:

| Attack / case | Guard |
|---|---|
| invalid or malformed code | `V.validateCodeFormat` |
| self referral (same serial / account / row) | `V.canApplyCode` |
| duplicate referral | `referred_by` + existing referral row check |
| code reuse by the owner | self referral check |
| owner limit (`maxReferrals`, `maxOpenReferralsPerOwner`) | `canApplyCode` |
| brute force | `maxAttempts` inside `attemptWindow` |
| spam | `cooldownSeconds` between submissions |
| fake reward amount | `V.computeRewardAmount()` recomputed at payout |
| double payout | reward row per referral + `status == "paid"` check |
| offline owner | reward stored as `pending`, paid on next join |
| abuse | every rejection is logged to `referral_abuse` |

Money is only ever moved with `givePlayerMoney` (or a custom server side handler),
never on a client request.

---

## 11. Gamemode integration

Playtime is measured by this resource. Level is read from your gamemode:

```lua
ReferralConfig.tracking.level = {
    source       = "export",   -- "export" | "elementData" | "manual"
    resource     = "my_level_system",
    functionName = "getPlayerLevel",
    elementData  = "level",
    default      = 1,
}
```

Or report progress yourself from any server resource:

```lua
exports.referral_system:setPlayerLevel(player, 5)
exports.referral_system:addPlaytime(player, 30)
triggerServerEvent("referral:reportLevel", resourceRoot, level)
```

---

## 12. Exports

> Export names are prefixed with the **actual resource folder name**. If you rename
> `referral_system` to `referral`, call `exports.referral:open()`.

Client:

```lua
exports.referral_system:open()             -- open the dashboard
exports.referral_system:close()
exports.referral_system:toggle()
exports.referral_system:getReferralCode()  -- "RAOUF-X72K"
exports.referral_system:getReferralStats() -- stats table of the cached snapshot
```

Server:

```lua
exports.referral_system:getReferralCode(player)
exports.referral_system:getReferralStats(player)
exports.referral_system:getReferrals(player)
exports.referral_system:isReferredBy(player, ownerSerial)
exports.referral_system:setPlayerLevel(player, level)
exports.referral_system:addPlaytime(player, minutes)
```

Admin panel settings (restart the resource after changing): `enabled`,
`rewardPerReferral`, `codeLength`, `maxReferrals`, `openKey`, `sidebarSide`.

---

## 13. Performance

* NovaUI is retained-mode: no `onClientRender` is added by this resource.
* The window, sidebar and pages are created once; navigation only toggles
  visibility. Tables and charts are updated through `setRows` / `setData`.
* Playtime is flushed to the database at most once per
  `ReferralConfig.storage.playtimeFlushSeconds`.
* Listeners are registered once per component; dialogs are destroyed on close.
* No component is recreated per frame, and no window is duplicated (guarded by
  `ReferralClient.main.built`).

---

## 14. Responsive scaling

All coordinates are NovaUI coordinates (already scaled) — `NovaUI.scale()` is never
called manually. The layout is defined once in `client/ui.lua` (`UI.layout`) and
targets 1280×720 up to 3840×2160:

```lua
UI.layout = {
    sidebarWidth = 238, contentWidth = 862, contentHeight = 564,
    topbarHeight = 52,  pageHeight = 512,  padding = 16, gap = 14,
}
```

---

## 14b. The NovaUI bridge — `client/novaui.lua`

NovaUI is a third party library whose exact calling convention is not fixed here, so
the resource never assumes one. `client/novaui.lua` is the only file that talks to
NovaUI; everything else goes through `ReferralClient.novaui`.

**How the library is found**

1. `getResourceState` / `exports[<name>]` for every name in
   `ReferralConfig.novaui.resourceNames` (also matched case-insensitively).
2. A global table (`NovaUI`) as a fallback.
3. A last resort scan of every running resource whose name contains `nova`.

**How components are created**

`create(kind, props)` tries every exported function name that looks like a factory
(`create`, `Create`, `new`, `New`, `component`, `element`, `make`, `build`, `add`,
`createComponent`, `createElement`) against every calling convention:

| Shape | Call |
|---|---|
| method + two args | `factory(self, kind, props)` |
| function + two args | `factory(kind, props)` |
| method + one table | `factory(self, { type = kind, ... })` |
| function + one table | `factory({ type = kind, ... })` |
| method + kind only | `factory(self, kind)` |
| function + kind only | `factory(kind)` |

Method style is always tried first, because MTA reports a failed pcall's name from
the debug info — a colon in `NovaUI:create` means the library defines a method, and
calling it dot-style shifts every argument by one.

The first convention that returns a table or userdata is remembered and reused, so
the probing cost is paid once. If the remembered convention stops working it is
dropped and the probing runs again.

**Optional setup hook**

Some NovaUI builds must be initialised before any component can be created — an
uninitialised build fails *inside* the library with
`attempt to perform arithmetic on field 'level'`. Set the real function name here and
it is called once, method style first then dot style:

```lua
ReferralConfig.novaui.initFunction = "init"   -- "setup", "start", "load", "boot" ...
```

Leave it empty and nothing extra is ever called.

**`/referral debug`**

Prints the resolved resource, every candidate with its state and exported function
names, the global keys, the configured `initFunction`, and then a live probe of
`create` for `window`, `panel` and `label` **showing what each call actually
returns** (or the exact error). That output is the fastest way to find out what the
installed NovaUI build really exposes.

---

## 15. Testing

Two dev tools (outside the resource) run the real Lua code against mocked MTA and
mocked NovaUI APIs:

```bash
python3 tools/check_lua.py      # syntax + unknown globals + asset paths + events + font coverage
python3 tools/verify.py         # static verification
python3 tools/test_resource.py  # executes the resource: 130 assertions
```

The execution suite covers: code generation, valid/invalid code, self referral,
duplicate referral, cooldown, rate limiting, requirement gating, reward payout,
milestones, claims, double claims, owner limits, chart data, SQLite statements,
window open/close, no duplicate windows, F6, command, navigation, breadcrumb,
search, filtering, sorting, empty/loading/error states, share/copy clipboard,
apply-code flow, all exports, and every NovaUI calling convention (method style, function style, single-props-table, a nil-returning factory and a
broken factory).

---

## 16. Troubleshooting

| Symptom | Fix |
|---|---|
| Resource will not start | NovaUI is missing or named differently → see step 2 |
| "تعذر العثور على واجهة NovaUI" | start NovaUI, or fix `resourceNames` / `<include>` |
| "تعذر انشاء النافذة" / `could not create window` | NovaUI was found but its `create` returned nil or raised an error. Run `/referral debug` and read the probe results — they show the real exported names and the exact error |
| `attempt to perform arithmetic on field 'level'` | This error is raised **inside** NovaUI, not in this resource. The library is either not initialised yet or its factory expects another signature → try `ReferralConfig.novaui.initFunction`, then re-run `/referral debug` |
| Dashboard opens but stays empty | the probe shows `create` returning a table, so the factory is fine — check the server console for the data fetch instead |
| "تعذر تحميل بيانات الاحالة" | server side error, check the server console; the UI offers a retry button |
| No data persists | `ReferralConfig.storage.backend` fell back to `memory` (sqlite module missing) |
| Icons look wrong | replace the PNG in `assets/icons/` keeping transparency |
