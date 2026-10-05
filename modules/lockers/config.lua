--[[
    PERSONAL LOCKERS
    Every player gets their OWN stash per locker `group` — all 10 MRPD change
    lockers open the same personal locker. Framework / notify / target go
    through rps_lib.

    Spot data (models, twins, clips, offsets) is taken 1:1 from
    prompt_mrpd_scripts config/anims.lua so the animation matches the MLO.
]]

Config.Lockers = {}

-- 'mrpd'       = use prompt_mrpd_scripts' OWN "Change Locker" target. When MRPD starts the locker animation on a spot whose id
--                is in Locations below, the personal locker opens; closing the
--                inventory plays MRPD's close-door phase. No hook edits needed
--                (watches exports.prompt_mrpd_scripts:IsPlayerAnimated()).
--                Falls back to 'standalone' if prompt_mrpd_scripts isn't running.
-- 'standalone' = this resource places its own target zones AND plays the MRPD
--                locker animation itself (works with only the prompt_mrpd map).
--                If prompt_mrpd_scripts runs too, set `enabled = false` on the
--                matching spots in ITS config/anims.lua.
Config.Lockers.Mode = 'mrpd'

-- 'mrpd' mode: how often (ms) to poll IsPlayerAnimated() while inside MRPD.
Config.Lockers.Mrpd = {
    resource     = 'prompt_mrpd_scripts',
    pollInterval = 200,
    center       = vec3(455.91, -999.01, 27.47),   -- MRPD interior, from Prompt's docs
    radius       = 60.0,                           -- only poll when this close
}

-- 'target' = rps_lib target (ox_target / qb-target / tgiann-target, auto-detected)
-- '3dtext' = rps_lib DrawText3D + [E] key
Config.Lockers.Interaction = 'target'

-- 'auto' uses rps_lib's detected inventory (plus qs-inventory, which rps_lib does not detect).
-- Force one of: 'ox_inventory' | 'tgiann-inventory' | 'qb-inventory' | 'ps-inventory' | 'lj-inventory' | 'qs-inventory'
Config.Lockers.Inventory = 'tgiann-inventory'

-- Jobs allowed when a location has `jobs = {}` (same idea as MRPD's DefaultJobs).
-- `jobs = 'all'` on a location opens it to every player.
Config.Lockers.DefaultJobs = { 'police', 'lspd', 'bcso', 'sasp' }

-- Delay (ms) from using the locker until the stash opens (the animation keeps
-- playing meanwhile). nil / 0 = open as soon as the open-door clip finishes.
Config.Lockers.OpenDelay = 7000

-- Server-side: max distance (m) between the player and the locker coords.
Config.Lockers.MaxDistance = 3.0

-- Admin: /lockerinspect <serverId> [group] opens another player's locker.
Config.Lockers.AdminCommand = 'lockerinspect'
Config.Lockers.AdminPermission = 'admin'

-- One stash per player per group. weight is in grams (ox/qb/tgiann convention).
Config.Lockers.Groups = {
    mrpd_change = { label = 'Personal Locker', slots = 30, weight = 60000 },
}

Config.Lockers.Animation = {
    BlendSpeed       = 2.5,   -- same as MRPD's Config.Anims.BlendSpeed
    PropSearchRadius = 0.3,   -- finds the static MLO prop near the configured coords
    WalkTimeout      = 3000,  -- ms the ped gets to walk onto the stand point
    -- Used when the MRPD twin model / anim dicts are not streamed (or for custom
    -- locations without MRPD anim data). Base-game.
    Fallback = { dict = 'amb@prop_human_bum_bin@base', clip = 'base' },
}

Config.Lockers.Target = {
    icon     = 'fas fa-lock',
    label    = 'Open Personal Locker',
    distance = 1.5,
    size     = vec3(0.4, 0.4, 2.0),   -- change lockers are only ~0.42 m apart
}

Config.Lockers.Text3D = {
    drawDistance     = 4.0,
    interactDistance = 1.2,
    key              = 38,   -- E
    text             = 'Press ~g~E~w~ to open',
}

Config.Lockers.Text = {
    noAccess    = 'This locker is not assigned to you.',
    tooFar      = 'You are too far from the locker.',
    busy        = 'You are already using a locker.',
    noInventory = 'No supported inventory found.',
    failed      = 'Could not open the locker.',
    noTarget    = 'Player not found.',
    noPerm      = 'You do not have permission to do that.',
}

-- ═══════════════════════════════════════════════════════════════════════════
-- LOCATIONS
-- Per-location fields:
--   id            unique id. For MRPD spots, keep the MRPD spot id (mrpd_hooks mode maps by it)
--   group         key into Config.Lockers.Groups (which stash it opens)
--   label         target / 3D text label
--   coords        vec4 of the static prop origin (fallback if the prop isn't found)
--   model         static MLO prop (hidden while the twin animates), optional
--   anim          MRPD-style anim data (optional — omitted = Fallback anim)
--   offset        ped stand point relative to the anim twin (MRPD `offset`)
--   rotation      ped facing relative to the twin (MRPD `rotation`)
--   zoneOffset    target / 3D text point relative to coords (world axes)
--   jobs          {} = DefaultJobs, 'all' = everyone, or a job list
--   minGrade      optional minimum job grade
--   enabled       false hides the location
-- ═══════════════════════════════════════════════════════════════════════════

-- Shared anim data for the 10 change lockers (phased: open → loop → close)
local CHANGE_LOCKER_ANIM = {
    animModel = 'prompt_mrpd_changelocker1_anim',
    open  = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_changelocker1_animation' },
              ped  = { dict = 'prompt@mrpd@ped',  name = 'changelocker1_ped' } },
    loop  = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_changelocker2_animation' },
              ped  = { dict = 'prompt@mrpd@ped',  name = 'changelocker2_ped' } },
    close = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_changelocker3_animation' },
              ped  = { dict = 'prompt@mrpd@ped',  name = 'changelocker3_ped' } },
}

local function changeLocker(index, coords)
    return {
        id         = 'changelocker_door_' .. index,
        group      = 'mrpd_change',
        label      = 'Personal Locker',
        coords     = coords,
        model      = 'prompt_mrpd_changelocker1_door',
        anim       = CHANGE_LOCKER_ANIM,
        offset     = vec3(0.0, 0.7, 1.0),
        rotation   = vec3(0.0, 0.0, 180.0),
        zoneOffset = vec3(0.0, 0.0, 1.0),   -- prop origin sits on the floor
        jobs       = {},
    }
end

Config.Lockers.Locations = {
    -- MRPD change room (10)
    changeLocker(1,  vec4(457.5114, -1012.6920, 28.1035,  0.0)),
    changeLocker(2,  vec4(455.8355, -1012.6920, 28.1035,  0.0)),
    changeLocker(3,  vec4(456.6720, -1012.6920, 28.1035,  0.0)),
    changeLocker(4,  vec4(461.0692, -1010.1732, 28.1036, 90.0)),
    changeLocker(5,  vec4(456.2521, -1012.6920, 28.1035,  0.0)),
    changeLocker(6,  vec4(461.0692, -1009.7560, 28.1036, 90.0)),
    changeLocker(7,  vec4(457.0907, -1012.6920, 28.1035,  0.0)),
    changeLocker(8,  vec4(461.0692, -1011.4285, 28.1036, 90.0)),
    changeLocker(9,  vec4(461.0692, -1011.0130, 28.1036, 90.0)),
    changeLocker(10, vec4(461.0692, -1010.5925, 28.1036, 90.0)),

    -- Custom example (any map, no MRPD anim → Fallback anim):
    -- {
    --     id = 'sandy_locker_1', group = 'mrpd_change', label = 'Personal Locker',
    --     coords = vec4(1853.2, 3689.5, 34.27, 210.0),
    --     offset = vec3(0.0, -0.8, 1.0), rotation = vec3(0.0, 0.0, 0.0),
    --     jobs = { 'police', 'bcso' },
    -- },
}

-- Personal lockers off → keep the engine (for the armory) but no change lockers
if not Config.Modules.lockers then
    Config.Lockers.Locations = {}
end

-- Lookup by id (modules/armory/config.lua appends its storages to both)
Config.Lockers.ById = {}
for _, loc in ipairs(Config.Lockers.Locations) do
    Config.Lockers.ById[loc.id] = loc
end
