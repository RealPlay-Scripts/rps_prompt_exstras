--[[
    EVIDENCE
    - Every MRPD evidence shelf (evdshelf2 / evdshelf4 / evdshelf5, 26 spots)
      is its OWN shared stash, assigned to a category (drugs, weapons, tech, ...).
    - The MRPD evidence locker (evdlocker_1) opens an ox_lib menu that can
      open ANY shelf remotely — high ranks only (Config.Evidence.MasterMinGrade).
    - The evidence plan table (evdplantable_1) is NOT used.

    Runs on the locker engine, so it follows Config.Lockers.Mode: in 'mrpd'
    mode MRPD's own "Evidence Shelf" / "Evidence Locker" targets + animations
    trigger it.
]]

if not Config.Modules.evidence then return end

Config.Evidence = {}

-- {} = Config.Lockers.DefaultJobs
Config.Evidence.Jobs = {}

-- Minimum grade to open a shelf directly (any officer by default).
Config.Evidence.ShelfMinGrade = 0

-- Minimum grade for the evidence locker master menu ("high role only").
-- Use the grade number of YOUR ladder (ESX job_grades.grade).
Config.Evidence.MasterMinGrade = 3

-- Server-side: max distance from the evidence locker while using the menu.
Config.Evidence.MasterMaxDistance = 3.0

-- Per-shelf stash size (weight in grams)
Config.Evidence.Slots  = 50
Config.Evidence.Weight = 500000

-- Categories, in menu order. icon = Font Awesome name (ox_lib).
Config.Evidence.Categories = {
    { key = 'drugs',     label = 'Drugs',               icon = 'cannabis' },
    { key = 'weapons',   label = 'Weapons',             icon = 'gun' },
    { key = 'tech',      label = 'Tech & Electronics',  icon = 'laptop' },
    { key = 'money',     label = 'Money & Valuables',   icon = 'sack-dollar' },
    { key = 'documents', label = 'Documents & IDs',     icon = 'file-lines' },
    { key = 'misc',      label = 'Miscellaneous',       icon = 'box-archive' },
    { key = 'coldcase',  label = 'Cold Cases',          icon = 'snowflake' },
}

-- Every shelf → category. Coords are MRPD's (config/anims.lua). Move a shelf
-- to another category by changing its `category`; set `enabled = false` to drop it.
Config.Evidence.Shelves = {
    -- basement evidence room
    { id = 'evdshelf2_5',  category = 'drugs',     coords = vec4(441.4857, -1025.7148, 23.9352, 180.0) },
    { id = 'evdshelf2_8',  category = 'drugs',     coords = vec4(443.3087, -1025.0508, 23.9352,   0.0) },
    { id = 'evdshelf4_9',  category = 'drugs',     coords = vec4(438.6888, -1026.6509, 23.9328, 270.0) },
    { id = 'evdshelf5_4',  category = 'drugs',     coords = vec4(445.1397, -1025.7148, 23.9332, 180.0) },

    { id = 'evdshelf2_6',  category = 'weapons',   coords = vec4(438.6888, -1017.4749, 23.9352, 270.0) },
    { id = 'evdshelf2_9',  category = 'weapons',   coords = vec4(445.1298, -1022.1868, 23.9352,   0.0) },
    { id = 'evdshelf4_8',  category = 'weapons',   coords = vec4(438.6888, -1019.3148, 23.9328, 270.0) },
    { id = 'evdshelf5_2',  category = 'weapons',   coords = vec4(438.6877, -1022.9808, 23.9332, 270.0) },

    { id = 'evdshelf2_10', category = 'tech',      coords = vec4(448.0078, -1022.9869, 23.9352,  90.0) },
    { id = 'evdshelf4_11', category = 'tech',      coords = vec4(448.0067, -1024.8127, 23.9328,  90.0) },
    { id = 'evdshelf5_3',  category = 'tech',      coords = vec4(448.0097, -1017.5068, 23.9374,  90.0) },

    { id = 'evdshelf4_5',  category = 'money',     coords = vec4(443.3067, -1022.1859, 23.9308,   0.0) },
    { id = 'evdshelf5_1',  category = 'money',     coords = vec4(443.3077, -1022.8608, 23.9377, 180.0) },

    { id = 'evdshelf4_12', category = 'documents', coords = vec4(445.1307, -1022.8608, 23.9308, 180.0) },

    -- basement side room
    { id = 'evdshelf2_2',  category = 'misc',      coords = vec4(463.7298, -1019.9949, 23.4615,   0.0) },
    { id = 'evdshelf2_4',  category = 'misc',      coords = vec4(462.0188, -1013.9040, 23.4643, 270.0) },
    { id = 'evdshelf4_1',  category = 'misc',      coords = vec4(462.0278, -1011.8557, 23.4599, 270.0) },

    -- ground floor
    { id = 'evdshelf2_1',  category = 'tech',      coords = vec4(467.5202,  -985.2725, 29.1983,   0.0) },
    { id = 'evdshelf2_3',  category = 'documents', coords = vec4(451.1874,  -971.1882, 29.2015, 180.0) },
    { id = 'evdshelf4_2',  category = 'documents', coords = vec4(456.8935,  -971.2396, 29.2046, 270.0) },

    -- upper floors
    { id = 'evdshelf4_3',  category = 'coldcase',  coords = vec4(457.9385,  -968.7301, 36.9153, 180.0) },
    { id = 'evdshelf4_4',  category = 'coldcase',  coords = vec4(458.9040,  -974.3582, 36.9153,  90.0) },
    { id = 'evdshelf2_7',  category = 'coldcase',  coords = vec4(460.4079,  -982.7998, 40.0030,   0.0) },
    { id = 'evdshelf4_6',  category = 'coldcase',  coords = vec4(458.4954,  -978.4522, 39.9972, 180.0) },
    { id = 'evdshelf4_7',  category = 'coldcase',  coords = vec4(449.5887,  -979.3038, 39.9972, 270.0) },
    { id = 'evdshelf4_10', category = 'coldcase',  coords = vec4(462.3163,  -982.7929, 39.9972,   0.0) },
}

-- The master locker
Config.Evidence.MasterLocker = {
    id     = 'evdlocker_1',
    label  = 'Evidence Locker',
    coords = vec4(443.4107, -1029.3569, 23.7802, 0.0),
}

Config.Evidence.Text = {
    menuTitle   = 'Evidence Locker',
    categoryFmt = '%d shelves',
    shelfDesc   = 'Open this shelf',
    noAccess    = 'Only senior officers can use the evidence locker.',
}

-- ─── MRPD anim data per shelf model (1:1 from prompt_mrpd_scripts config/anims.lua)
local SHELF_TYPES = {
    evdshelf2 = {
        model = 'prompt_mrpd_evdshelf2',
        anim  = {
            animModel = 'prompt_mrpd_evdshelf2_anim',
            animOffset = vec3(0.0010, -0.0029, -1.0944), animHeadingOffset = 90.0,
            loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_evdshelf2_animation' },
                     ped  = { dict = 'prompt@mrpd@ped',  name = 'evdshelf2_ped' } },
        },
        offset = vec3(0.9, -0.6, 1.0), rotation = vec3(0.0, 0.0, 90.0),
    },
    evdshelf4 = {
        model = 'prompt_mrpd_evdshelf4',
        anim  = {
            animModel = 'prompt_mrpd_evdshelf4_anim',
            animOffset = vec3(-0.0006, 0.0006, -1.0957), animHeadingOffset = 90.0,
            loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_evdshelf4_animation' },
                     ped  = { dict = 'prompt@mrpd@ped',  name = 'evdshelf4_ped' } },
        },
        offset = vec3(0.9, -0.04, 0.98), rotation = vec3(0.0, 0.0, 90.0),
    },
    evdshelf5 = {
        model = 'prompt_mrpd_evdshelf5',
        anim  = {
            animModel = 'prompt_mrpd_evdshelf5_anim',
            animOffset = vec3(-0.0004, 0.0051, -1.1034), animHeadingOffset = 180.0,
            loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_evdshelf5_animation' },
                     ped  = { dict = 'prompt@mrpd@ped',  name = 'evdshelf5_ped' } },
        },
        offset = vec3(-0.02, -0.81, 1.0), rotation = vec3(0.0, 0.0, 0.0),
    },
}

local MASTER_ANIM = {
    animModel  = 'prompt_mrpd_evdlocker_anim',
    animOffset = vec3(0.0056, -0.0015, -0.9456),
    loop = { prop = { dict = 'prompt@mrpd@prop', name = 'prompt_mrpd_evdlocker_animation' },
             ped  = { dict = 'prompt@mrpd@ped',  name = 'evd_locker_ped' } },
}

-- ─── Build lookups + register everything with the locker engine ─────────────
Config.Evidence.CategoryByKey = {}
for _, cat in ipairs(Config.Evidence.Categories) do
    cat.shelves = {}
    Config.Evidence.CategoryByKey[cat.key] = cat
end

Config.Evidence.ShelfByGroup = {}

local function addLocation(loc)
    Config.Lockers.Locations[#Config.Lockers.Locations + 1] = loc
    Config.Lockers.ById[loc.id] = loc
end

for _, shelf in ipairs(Config.Evidence.Shelves) do
    local cat = Config.Evidence.CategoryByKey[shelf.category]
    local shelfType = SHELF_TYPES[shelf.id:match('^(evdshelf%d)_')]

    if shelf.enabled ~= false and cat and shelfType then
        cat.shelves[#cat.shelves + 1] = shelf
        shelf.group = 'evidence_' .. shelf.id
        shelf.label = ('Evidence - %s #%d'):format(cat.label, #cat.shelves)
        Config.Evidence.ShelfByGroup[shelf.group] = shelf

        Config.Lockers.Groups[shelf.group] = {
            label  = shelf.label,
            slots  = Config.Evidence.Slots,
            weight = Config.Evidence.Weight,
            shared = true,
        }

        addLocation({
            id         = shelf.id,
            group      = shelf.group,
            label      = shelf.label,
            coords     = shelf.coords,
            model      = shelfType.model,
            anim       = shelfType.anim,
            offset     = shelfType.offset,
            rotation   = shelfType.rotation,
            zoneOffset = vec3(0.0, 0.0, 0.0),   -- shelf origin is ~1.1 m up already
            jobs       = Config.Evidence.Jobs,
            minGrade   = Config.Evidence.ShelfMinGrade,
        })
    end
end

local M = Config.Evidence.MasterLocker
addLocation({
    id         = M.id,
    menu       = 'evidence',           -- opens the master menu instead of a stash
    label      = M.label,
    coords     = M.coords,
    model      = 'prompt_mrpd_evdlocker',
    anim       = MASTER_ANIM,
    offset     = vec3(1.4, 0.8, 1.0),
    rotation   = vec3(0.0, 0.0, 180.0),
    zoneOffset = vec3(0.0, 0.0, 0.0),
    jobs       = Config.Evidence.Jobs,
    minGrade   = Config.Evidence.MasterMinGrade,
    noAccessText = Config.Evidence.Text.noAccess,
})
