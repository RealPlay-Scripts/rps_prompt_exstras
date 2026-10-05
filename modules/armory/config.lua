--[[
    ARMORY
    - The 2 MRPD armory gun lockers each open their OWN shared job storage
      (everyone with access sees the same items). They run on the locker
      engine, so they follow Config.Lockers.Mode: in 'mrpd' mode MRPD's own
      "Gun Locker" target + animation triggers them.
    - A quartermaster ped checks Config.Armory.Loadout against your inventory
      and hands you whatever you're missing, TAKEN FROM the armory storages
      (no items are created). Out-of-stock items are listed back to you.

    Loadout transfers need ox_inventory or tgiann-inventory.
]]

if not Config.Modules.armory then return end

Config.Armory = {}

-- {} = Config.Lockers.DefaultJobs. Used by the storages AND the quartermaster.
Config.Armory.Jobs = {}

-- ─── Storages (one per MRPD gun locker) ──────────────────────────────────────
-- key = stash group. spot = MRPD spot id + coords (from prompt_mrpd_scripts config/anims.lua).
Config.Armory.Storages = {
    armory_weapons = {
        label    = 'Armory - Weapons',
        slots    = 80,
        weight   = 1000000,   -- grams
        minGrade = 0,
        spot     = { id = 'armory_gunlocker_1', coords = vec4(462.0558, -1011.4459, 29.2722, 0.0) },
    },
    armory_equipment = {
        label    = 'Armory - Equipment',
        slots    = 80,
        weight   = 1000000,
        minGrade = 0,
        spot     = { id = 'armory_gunlocker_2', coords = vec4(462.0558, -1009.8518, 29.2722, 0.0) },
    },
}

-- ─── Quartermaster ped ───────────────────────────────────────────────────────
Config.Armory.Quartermaster = {
    model    = 's_m_y_cop_01',
    -- Player coords where the ped should stand (stand there and run /armorypos,
    -- it prints a ready-to-paste vec4). The value below is a starting guess
    -- inside the MRPD armory, TUNE it in-game.
    coords   = vec4(467.6, -1009.45, 29.13, 358.44),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    spawnDistance = 40.0,

    target   = { icon = 'fas fa-person-military-rifle', label = 'Collect Loadout', distance = 2.0 },
    maxDistance = 4.0,   -- server-side check
    cooldown = 0,       -- seconds between loadout requests per player
    handover = true,     -- play a give/take animation between ped and player
}

-- Storages searched (in this order) when filling a loadout.
Config.Armory.LoadoutFrom = { 'armory_weapons', 'armory_equipment' }

-- What every officer should carry. `count` = how many you should HAVE; the ped
-- only gives the difference. `minGrade` (optional) limits an entry to ranks.
-- Item names must match YOUR inventory's item list (tgiann / ox use lowercase
-- weapon names like 'weapon_pistol'; ammo item names differ per server).
Config.Armory.Loadout = {
    { name = 'weapon_combatpistol', count = 1 },
    { name = 'pistol_ammo',         count = 120 },
    { name = 'weapon_stungun',      count = 1 },
    { name = 'weapon_nightstick',   count = 1 },
    { name = 'weapon_flashlight',   count = 1 },
    { name = 'handcuffs',           count = 1 },
    { name = 'radio',               count = 1 },
    { name = 'bandage',             count = 5 },
    { name = 'weapon_carbinerifle', count = 1,   minGrade = 2 },
    { name = 'rifle_ammo',          count = 120, minGrade = 2 },
}

Config.Armory.Text = {
    received   = 'Received: %s',
    outOfStock = 'Out of stock in the armory: %s',
    complete   = 'You already have your full loadout.',
    cooldown   = 'Come back in %d seconds.',
    noAccess   = 'The quartermaster won\'t serve you.',
    tooFar     = 'You are too far from the quartermaster.',
}

-- ─── Register the storages with the locker engine ────────────────────────────
local GUN_LOCKER_ANIM = {
    animModel  = 'prompt_mrpd_armorygunlocker_anim',
    animOffset = vec3(-0.1657, 0.0050, -1.1506),
    loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_armorygunlocker_animation' },
             ped  = { dict = 'prompt@mrpd@ped',  name = 'armorygunlocker_ped' } },
}

for group, storage in pairs(Config.Armory.Storages) do
    Config.Lockers.Groups[group] = {
        label  = storage.label,
        slots  = storage.slots,
        weight = storage.weight,
        shared = true,
    }

    local loc = {
        id         = storage.spot.id,
        group      = group,
        label      = storage.label,
        coords     = storage.spot.coords,
        model      = 'prompt_mrpd_armorygunlocker',
        anim       = GUN_LOCKER_ANIM,
        offset     = vec3(1.1, -0.05, 1.0),
        rotation   = vec3(0.0, 0.0, 90.0),
        zoneOffset = vec3(0.0, 0.0, 0.0),   -- prop origin is already ~chest height
        jobs       = Config.Armory.Jobs,
        minGrade   = storage.minGrade,
    }
    Config.Lockers.Locations[#Config.Lockers.Locations + 1] = loc
    Config.Lockers.ById[loc.id] = loc
end
