--[[
    TECH
    MRPD tech room spots that hand out equipment:
      techbodycshelf_1  → body cam
      techbodycshelf_2  → dash cam
      footdronewall_1   → drone
    Runs on the locker engine, so it follows Config.Lockers.Mode: in 'mrpd'
    mode MRPD's own "Body Cam Shelf" / "Drone Wall" targets + animations
    trigger it. The item is given when the delay ends, then the animation stops.
]]

if not Config.Modules.tech then return end

Config.Tech = {}

-- {} = Config.Lockers.DefaultJobs
Config.Tech.Jobs = {}

-- Server-side: max distance from the spot.
Config.Tech.MaxDistance = 3.0

-- Per spot: which item, how many per use, and the most a player may carry
-- (no new one is given at `max`). Item names must exist in YOUR inventory.
-- openDelay (ms) = time the animation plays before the item is given.
Config.Tech.Spots = {
    {
        id = 'techbodycshelf_1', label = 'Body Cam Shelf',
        item = 'bodycam', count = 1, max = 1, minGrade = 0, openDelay = 4000,
        coords = vec4(467.9397, -990.2418, 28.9482, 0.0),
        type = 'bodycam_shelf',
    },
    {
        id = 'techbodycshelf_2', label = 'Dash Cam Shelf',
        item = 'dash_cam', count = 1, max = 1, minGrade = 0, openDelay = 4000,   -- tgiann's stock item name
        coords = vec4(466.3947, -990.2418, 28.9482, 0.0),
        type = 'bodycam_shelf',
    },
    {
        id = 'footdronewall_1', label = 'Drone Wall',
        item = 'drone', count = 1, max = 1, minGrade = 0, openDelay = 4000,
        coords = vec4(467.8611, -985.8266, 29.6612, 0.0),
        type = 'drone_wall',
    },
}

Config.Tech.Text = {
    received    = 'You took: %s',
    alreadyHave = 'You already carry a %s.',
    cantCarry   = 'You can\'t carry a %s.',
}

-- ─── MRPD anim data (1:1 from prompt_mrpd_scripts config/anims.lua) ──────────
local TYPES = {
    bodycam_shelf = {
        model = 'prompt_mrpd_techbodycshelf',
        anim  = {
            animModel  = 'prompt_mrpd_techbodycshelf_anim',
            animOffset = vec3(0.0, 0.0, -0.8441),
            loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_techbodycshelf_animation' },
                     ped  = { dict = 'prompt@mrpd@ped',  name = 'techbodyshelf_ped' } },
        },
        offset = vec3(0.0, 0.72, 1.0), rotation = vec3(0.0, 0.0, 180.0),
    },
    drone_wall = {
        model = 'promtp_mrpd_footdronewall',   -- "promtp" typo matches the MLO
        anim  = {
            animModel  = 'prompt_mrpd_footdronewall_anim',
            animOffset = vec3(0.0, 0.0846, -1.5784),
            loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_footdronewall_animation' },
                     ped  = { dict = 'prompt@mrpd@ped',  name = 'footdronewall_ped' } },
        },
        offset = vec3(0.0, -0.7, 1.0), rotation = vec3(0.0, 0.0, 0.0),
    },
}

-- ─── Register with the locker engine ─────────────────────────────────────────
Config.Tech.ById = {}

for _, spot in ipairs(Config.Tech.Spots) do
    local t = TYPES[spot.type]
    if spot.enabled ~= false and t then
        Config.Tech.ById[spot.id] = spot

        local loc = {
            id         = spot.id,
            menu       = 'tech',          -- handled by modules/tech/client.lua (gives the item)
            label      = spot.label,
            coords     = spot.coords,
            model      = t.model,
            anim       = t.anim,
            offset     = t.offset,
            rotation   = t.rotation,
            zoneOffset = vec3(0.0, 0.0, 0.0),
            jobs       = Config.Tech.Jobs,
            minGrade   = spot.minGrade,
            openDelay  = spot.openDelay,
        }
        Config.Lockers.Locations[#Config.Lockers.Locations + 1] = loc
        Config.Lockers.ById[loc.id] = loc
    end
end
