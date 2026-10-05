# rps_prompt_exstras

Extras for Prompt Studio maps, built on `rps_lib` (ESX / QBCore / Qbox / standalone).

## Module: Personal Lockers (MRPD)

Each player gets their **own** stash per locker group:

| Group | Where | Default |
|---|---|---|
| `mrpd_change` | the 10 MRPD change-room lockers (`prompt_mrpd_changelocker1_door`) | 30 slots / 60 kg |

All 10 change lockers open the same personal locker, so it doesn't matter which door a player uses.

- **Framework / notify / target**: handled by `rps_lib` (ox_target, qb-target, tgiann-target, or 3D text + E).
- **Inventory**: ox_inventory, tgiann-inventory, qb-inventory (legacy and v2), ps-inventory, lj-inventory, qs-inventory.
- **Animation**: uses MRPD's own locker clips and twins (`prompt@mrpd@prop` / `prompt@mrpd@ped`). The door opens, loops while the inventory is open, and closes when the inventory closes. If those assets aren't streamed, a base-game animation plays instead.
- **Access**: `Config.Lockers.DefaultJobs` (police/lspd/bcso/sasp). You can override `jobs`, `minGrade` or `'all'` per location. The server re-checks job and distance on every open.

### Install

```
ensure ox_lib
ensure rps_lib
ensure prompt_mrpd
ensure prompt_mrpd_scripts   # needed for Mode = 'mrpd'
ensure rps_prompt_exstras
```

### Mode: `mrpd` (default) — use MRPD's own "Change Locker" target

Keep `prompt_mrpd_scripts` exactly as it is. Players use its normal **Change Locker** target option, and MRPD plays its door-open animation. This resource then:

1. sees the locker animation start through MRPD's public export `IsPlayerAnimated()` (spot id `changelocker_door_1..10`),
2. waits `Config.Lockers.OpenDelay` (7 s by default), checks access on the server, and opens the player's personal stash,
3. calls `exports.prompt_mrpd_scripts:StopPlayerAnim(false)` once the inventory closes, so MRPD plays its door-close animation.

You don't need to edit any hooks. Start `rps_prompt_exstras` **after** `prompt_mrpd_scripts`. To stop a spot from opening a stash, set `enabled = false` on it in `Config.Lockers.Locations`. If `prompt_mrpd_scripts` isn't running, the resource falls back to `standalone`.

### Mode: `standalone`

This resource adds the target zones and plays the locker animation itself. It only needs the `prompt_mrpd` map.

**If you also run `prompt_mrpd_scripts`**, disable its own change-locker spots in `prompt_mrpd_scripts/config/anims.lua`. Otherwise each locker gets two target options and two animation twins:

```lua
{ id = 'changelocker_door_1', ..., enabled = false },
-- ...same for changelocker_door_2..10
```

### Mode B: `mrpd_hooks`

`prompt_mrpd_scripts` keeps its own target option and animation. Its `onStart` hook opens the personal locker, and when the inventory closes this resource calls `exports.prompt_mrpd_scripts:StopPlayerAnim(false)` to play MRPD's close phase.

A ready-made file is at `setup/prompt_mrpd_scripts/hooks/hooks_shared.lua`. Copy it over `prompt_mrpd_scripts/hooks/hooks_shared.lua`, then restart. It works in both `mrpd` and `mrpd_hooks` mode: when the hook and the `IsPlayerAnimated()` watcher both fire, the busy guard makes sure the stash only opens once. The core of it:

```lua
local lockerEntries = {}
local lockerSpots = {}
for i = 1, 10 do lockerSpots[#lockerSpots + 1] = 'changelocker_door_' .. i end

for _, spotId in ipairs(lockerSpots) do
    lockerEntries[spotId] = {
        onStart = function(ctx)
            if IsDuplicityVersion() then return end   -- client side only
            exports.rps_prompt_exstras:OpenFromMrpd(ctx.spotId or spotId)
        end,
    }
end

return {
    anims = { entries = lockerEntries },
}
```

> MRPD's public docs list `onStart` / `onEnd` for the `anims` feature but don't show its exact `ctx`. That's why the snippet falls back to the loop's `spotId`. Check `hooks/hooks_shared.example.lua` in your copy if it doesn't fire.

### Adding lockers elsewhere

Add an entry to `Config.Lockers.Locations`. Without `anim` data it uses the fallback animation. Set `coords` to the floor or prop origin, not the player's coords.

```lua
{ id = 'sandy_locker_1', group = 'mrpd_change', label = 'Personal Locker',
  coords = vec4(1853.2, 3689.5, 33.27, 210.0),
  offset = vec3(0.0, -0.8, 1.0), rotation = vec3(0.0, 0.0, 0.0),
  zoneOffset = vec3(0.0, 0.0, 1.0), jobs = { 'police', 'bcso' } },
```

You can add new groups (for example an EMS locker) in `Config.Lockers.Groups`.

## Module: Armory (MRPD)

Config: `modules/armory/config.lua`. Turn it on or off with `Config.Modules.armory`.

- **2 storages**: MRPD gun locker `armory_gunlocker_1` opens **Armory - Weapons** and `armory_gunlocker_2` opens **Armory - Equipment**. These are **shared** job stashes, so everyone with access sees the same items. They run on the locker engine, so in `mrpd` mode MRPD's own Gun Locker target and animation trigger them, with the same `OpenDelay`.
- **Quartermaster ped**: target **Collect Loadout**. The ped compares `Config.Armory.Loadout` with your inventory and gives you only what you're missing. Those items are **taken out of the armory storages**, never created, and weapon serials and other metadata are kept. Anything the storages don't have is listed back to you as out of stock.
- Items can be grade-locked with `minGrade`. Each player has a 30 s cooldown, and job and distance are checked on the server.
- Loadout transfers need **ox_inventory** or **tgiann-inventory** (both accept stash names in `GetSlotsWithItem` / `RemoveItem` / `AddItem`).
- **Place the ped:** stand where it should be, run `/armorypos`, and paste the printed `coords = vec4(...)` into `Config.Armory.Quartermaster.coords`.
- Item names in `Config.Armory.Loadout` are examples. Change them to match your inventory's item list.

## Module: Evidence (MRPD)

Config: `modules/evidence/config.lua`. Turn it on or off with `Config.Modules.evidence`.

- **Every evidence shelf is its own stash**: all 26 MRPD shelves (`evdshelf2_1..10`, `evdshelf4_1..12`, `evdshelf5_1..4`). Each shelf has a category: Drugs, Weapons, Tech & Electronics, Money & Valuables, Documents & IDs, Miscellaneous or Cold Cases. To move a shelf to another category, change its `category`. Labels are generated, e.g. `Evidence - Drugs #2`.
- **Evidence locker (`evdlocker_1`)** opens an **ox_lib menu**: categories → shelves → that shelf's inventory. After you close the inventory you're back in the menu. It's limited to `Config.Evidence.MasterMinGrade` (default 3), and the server re-checks rank and that you're standing at the locker.
- The evidence plan table (`evdplantable_1`) is not used.
- In `mrpd` mode, MRPD's own Evidence Shelf / Evidence Locker targets and animations trigger everything, with the same `OpenDelay`.
- Requires `ox_lib`, which this resource now loads via `@ox_lib/init.lua`.

## Module: Tech (MRPD)

Config: `modules/tech/config.lua`. Turn it on or off with `Config.Modules.tech`.

| MRPD spot | Gives |
|---|---|
| `techbodycshelf_1` (Body Cam Shelf) | `bodycam` |
| `techbodycshelf_2` (Body Cam Shelf) | `dashcam` |
| `footdronewall_1` (Drone Wall) | `drone` |

- The animation plays for the spot's `openDelay` (4 s by default), then the item is given and the animation stops.
- `max` limits how many a player can carry (default 1). If you already have one, you get "You already carry a …". The server checks job, grade and distance, and whether the player can carry the item.
- Item names are placeholders. Change them to items that exist in your inventory.

## Module: Mugshot (MRPD + screencapture)

Config: `modules/mugshot/config.lua`. Turn it on or off with `Config.Modules.mugshot`. Requires [screencapture](https://github.com/itschip/screencapture), `oxmysql` and `ox_lib`.

1. The **suspect** uses MRPD's own mug cart (`mugcart_1`). MRPD plays the mugshot animation, puts their name on the plate and moves their camera to the mugshot shot.
2. An **officer** uses the **Take Mugshot** target behind the camera.
3. The server captures the **suspect's screen** with `screencapture:remoteUpload`, with the HUD hidden, and uploads it. The token never reaches clients.
4. The image URL is saved to `rps_mugshots` (created automatically) and posted to an optional Discord log, and the officer sees a preview.

If the suspect isn't using MRPD's cart, a suspect standing at the cart gets this resource's own camera at MRPD's camera position. Set `RequireMugCart = true` to make MRPD's cart mandatory.

`server.cfg`:

```
ensure screencapture
set rps_mugshot_token   "your-fivemanage-api-key"
set rps_mugshot_webhook "https://discord.com/api/webhooks/..."   # optional log
```

`/mugcam` (officers, at the camera) takes the mugshot, the same as the target option. `/mugshots [serverId]` (officers) lists the latest mugshots of one player, or of everyone, with an image preview.

## Module: MRI (Prompt Pillbox Hill Medical Center)

Config: `modules/mri/config.lua`. Turn it on or off with `Config.Modules.mri`. Requires `prompt_pillbox_hospital`, `oxmysql` and `ox_lib`.

Pillbox runs the MRI itself: the bed, the slide, the scan light and the progress circle. When a scan **finishes**, this module:

1. reads the patient's state from their game: health, armour, the last body part that took damage, and what caused it (gunshot, melee, fall, vehicle, explosion or fire),
2. builds an **MRI report** from the editable texts: findings per body part, the overall condition (Normal, Mild, Moderate, Severe or Critical) and an impression,
3. shows the **operator** a full **MRI report sheet** (`web/mri.*`):
   - **Header:** hospital, patient name, date of birth and age (from the framework), patient ID, study type, indication, operator and accession number.
   - **Three image panels:** whole body (coronal) with the injury circled; a close-up of the injured region with an arrow and a note; and an axial slice through that region. The injury is drawn as a projectile fragment, contusion, fracture line, blast fragments or thermal oedema, depending on the cause.
   - **Text and signature:** Findings, Additional Observations and Conclusion, plus a signature block for the operator.

   All header and section texts are set in `Config.MRI.Report`, `Config.MRI.Indications`, `Config.MRI.ExtraFindings` and `Config.MRI.Severity`. It then tells the patient the scan is complete, saves it to `rps_mri_scans` (created automatically), and optionally posts it to Discord (`set rps_mri_webhook "..."` in server.cfg) and gives the operator a film item.

`/mriscans [serverId]` (medical staff, using Pillbox's own `IsMedic()` by default) lists past reports.

**Hook (recommended):** copy `setup/prompt_pillbox_hospital/hooks/hooks_server.lua` into `prompt_pillbox_hospital/hooks/`, or merge it into that file. Pillbox's `controls.onScanComplete` then passes the exact operator and patient. Without the hook, the module watches `GetMriState()` and takes the nearest medic as the operator.

**Discord:** when `rps_mri_webhook` is set, the **full report sheet is posted as an image** inside the embed. The operator's screen renders it and sends it to the server with a one-time token, and the server uploads it, so the webhook never reaches clients. If the image doesn't arrive within `Config.MRI.Discord.imageTimeout`, or Discord rejects it, a text-only embed is sent instead.

**Film item:** the operator receives an `mri_scan` film. Using it reopens that report sheet.

## Items

Item definitions for tgiann-inventory, ox_inventory, QBCore and ESX SQL, plus icons, are in [`setup/items/`](setup/items/README.md).

### Exports (client)

```lua
exports.rps_prompt_exstras:OpenLocker(locationId)   -- full flow incl. animation
exports.rps_prompt_exstras:OpenFromMrpd(spotId)     -- no animation (MRPD animates)
exports.rps_prompt_exstras:IsUsingLocker()          -- bool
```

### Admin

`/lockerinspect <serverId> [group]` opens another player's locker. It's gated by `rps_lib:HasPermission` (on ESX: the admin or superadmin group).
