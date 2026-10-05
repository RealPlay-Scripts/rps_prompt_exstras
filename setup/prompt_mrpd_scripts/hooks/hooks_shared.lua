-- ════════════════════════════════════════════════════════════════════════════
--  SHARED HOOKS  (open file — safe to edit)
--  Auto-created from this template on first start as hooks/hooks_shared.lua.
--  UPDATES NEVER OVERWRITE your hooks/hooks_shared.lua — edit it freely.
--
--  Loaded by BOTH sides: the CLIENT evaluates these gates for VISIBILITY (e.g.
--  hiding target options before you ever click) and the SERVER re-runs them as
--  AUTHORITY. Write a check ONCE here instead of duplicating it in
--  hooks_client.lua + hooks_server.lua — the side-specific files are AND-ed
--  with this one, so you can still add server-only logic there.
--
--  RULES for shared checks:
--    * only use data visible on BOTH sides: player statebags, ped anim probes,
--      the ctx fields. NOT server exports / DB / inventory — those belong in
--      hooks_server.lua.
--    * if one side needs a different data source, branch on IsDuplicityVersion()
--      (true = server) — still one file, one function.
--
--  Convoy ctx ('anims' feature, id 'convoy'):
--    canUse   — client: { ped, target = <aimed ped entity or nil> }
--               server: { source = <cop server id> }
--    canPartner (server only): { lead, partner }
--  NOTE: convoy's cop-job and target-cuffed checks are BUILT IN via config
--  (Config.Anims.Convoy.jobs / .requireCuffed) — write hooks only for logic
--  beyond that (duty flags, zones, ranks, ...).
-- ════════════════════════════════════════════════════════════════════════════

-- ── rps_prompt_exstras: personal lockers ────────────────────────────────────
-- When MRPD's own "Change Locker" animation starts, open the
-- player's personal stash. Closing the inventory makes rps_prompt_exstras call
-- StopPlayerAnim(false), so MRPD plays its close-door phase.
-- Remove a spot id from this list to keep it animation-only.
local RPS_LOCKER_SPOTS = {
    'changelocker_door_1', 'changelocker_door_2', 'changelocker_door_3',
    'changelocker_door_4', 'changelocker_door_5', 'changelocker_door_6',
    'changelocker_door_7', 'changelocker_door_8', 'changelocker_door_9',
    'changelocker_door_10',
    -- armory module: each gun locker opens its own shared armory storage
    'armory_gunlocker_1', 'armory_gunlocker_2',
    -- evidence module: master locker menu (high ranks) — the plan table is not used
    'evdlocker_1',
    -- tech module: body cam shelves (bodycam / dashcam) + drone wall (drone)
    'techbodycshelf_1', 'techbodycshelf_2', 'footdronewall_1',
}

-- evidence module: every evidence shelf is its own stash
for i = 1, 10 do RPS_LOCKER_SPOTS[#RPS_LOCKER_SPOTS + 1] = 'evdshelf2_' .. i end
for i = 1, 12 do RPS_LOCKER_SPOTS[#RPS_LOCKER_SPOTS + 1] = 'evdshelf4_' .. i end
for i = 1, 4  do RPS_LOCKER_SPOTS[#RPS_LOCKER_SPOTS + 1] = 'evdshelf5_' .. i end

local entries = {
    -- Example — convoy: require the cop's ON-DUTY statebag (set by your
    -- police job). Written ONCE; hides the option client-side AND blocks
    -- the pairing server-side:
    -- ['convoy'] = {
    --     canUse = function(ctx)
    --         local st = IsDuplicityVersion() and Player(ctx.source).state or LocalPlayer.state
    --         return st.onDuty == true
    --     end,
    -- },
}

for _, spotId in ipairs(RPS_LOCKER_SPOTS) do
    entries[spotId] = {
        onStart = function(ctx)
            -- the stash is opened client-side; the server half of this file skips it
            if IsDuplicityVersion() then return end
            if GetResourceState('rps_prompt_exstras') ~= 'started' then return end
            exports.rps_prompt_exstras:OpenFromMrpd(spotId)
        end,
    }
end

return {
    anims = {
        global = {},
        entries = entries,
    },
}
