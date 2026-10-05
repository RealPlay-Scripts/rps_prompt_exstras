if not LockerEngineEnabled() then return end

local Text = Config.Lockers.Text
local busy = false

-- [menuName] = function(loc) — blocking handlers for `loc.menu` locations,
-- registered by modules (see modules/evidence/client.lua).
LockerMenus = LockerMenus or {}
local activeSession = nil
local zoneIds = {}

local function notify(message, type)
    exports.rps_lib:Notify(message, type or 'info')
end

local function awaitServer(name, ...)
    local p = promise.new()
    exports.rps_lib:TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

-- UI gating only — the server re-checks everything. Global so the armory
-- quartermaster can reuse it (loc = anything with `jobs` / `minGrade`).
function LockerCanSee(loc)
    local jobs = loc.jobs
    if jobs == 'all' then return true end
    if not jobs or #jobs == 0 then jobs = Config.Lockers.DefaultJobs end

    local player = exports.rps_lib:GetPlayerData()
    local job = player and player.job
    if not job or not job.name then return false end

    local grade = job.grade and tonumber(job.grade.level) or 0
    for _, name in ipairs(jobs) do
        if name == job.name then return grade >= (loc.minGrade or 0) end
    end
    return false
end

local function zonePoint(loc)
    return loc.coords.xyz + (loc.zoneOffset or vec3(0.0, 0.0, 0.0))
end

--- Waits until GetGameTimer() reaches `deadline`. Returns false early if the
--- player died or stillValid() says the interaction was cancelled.
local function waitUntil(deadline, stillValid)
    while GetGameTimer() < deadline do
        if IsEntityDead(PlayerPedId()) then return false end
        if stillValid and not stillValid() then return false end
        Wait(100)
    end
    return true
end

--- loc.openDelay (optional) overrides Config.Lockers.OpenDelay for one location.
local function openDelay(loc)
    if loc and loc.openDelay then return tonumber(loc.openDelay) or 0 end
    return tonumber(Config.Lockers.OpenDelay) or 0
end

--- Shared open flow.
--- opts.anim       = true to play our own locker animation (false when MRPD animates)
--- opts.startedAt  = GetGameTimer() when the player used the locker (OpenDelay counts from here)
--- opts.stillValid = optional fn, false = interaction cancelled during the delay
--- opts.onClosed   = optional fn, runs at the very end
local function runLocker(loc, opts)
    busy = true

    local function finish()
        if activeSession then
            LockerAnim.End(activeSession)
            activeSession = nil
        end
        busy = false
        if opts.onClosed then opts.onClosed() end
    end

    local prep = awaitServer('rps_prompt_exstras:lockers:prepare', loc.id)
    if not prep or not prep.ok then
        notify(prep and prep.reason or Text.failed, 'error')
        return finish()
    end

    if opts.anim then
        activeSession = LockerAnim.Begin(loc)
    end

    if not waitUntil((opts.startedAt or GetGameTimer()) + openDelay(loc), opts.stillValid) then
        return finish()
    end

    -- Menu locations (e.g. the evidence master locker): a module-provided,
    -- blocking handler replaces the stash. The animation keeps looping until it returns.
    if loc.menu then
        local handler = LockerMenus[loc.menu]
        if handler then handler(loc) else notify(Text.failed, 'error') end
        return finish()
    end

    local res = awaitServer('rps_prompt_exstras:lockers:open', loc.id)
    if res and res.ok then
        LockerInvClient.Open(res.client)
        LockerInvClient.WaitForClose(3000)
    else
        notify(res and res.reason or Text.failed, 'error')
    end

    finish()
end

local function OpenLocker(locationId)
    local loc = Config.Lockers.ById[locationId]
    if not loc or loc.enabled == false then return false end
    if busy then notify(Text.busy, 'error') return false end

    local startedAt = GetGameTimer()
    CreateThread(function()
        runLocker(loc, { anim = true, startedAt = startedAt })
    end)
    return true
end

local MRPD = Config.Lockers.Mrpd.resource

-- Lets MRPD's "open door" clip finish before the inventory covers the screen.
local function waitForMrpdOpenPhase(loc)
    local open = loc.anim and loc.anim.open and loc.anim.open.ped
    if open and HasAnimDictLoaded(open.dict) then
        Wait(math.floor(GetAnimDuration(open.dict, open.name) * 1000))
    end
end

--- MRPD's own target started the locker animation on `spotId` (Mode = 'mrpd').
--- MRPD keeps animating; when the inventory closes we ask it to play its
--- close phase. Also callable from an MRPD anims onStart hook.
local function OpenFromMrpd(spotId)
    local loc = Config.Lockers.ById[spotId]
    if not loc or loc.enabled == false or busy then return false end

    local function stillOnSpot()
        local animating, current = exports[MRPD]:IsPlayerAnimated()
        return animating and current == spotId
    end

    busy = true
    local startedAt = GetGameTimer()
    CreateThread(function()
        -- no OpenDelay configured → at least let the open-door clip finish
        if openDelay(loc) <= 0 then
            waitForMrpdOpenPhase(loc)
        end

        -- player cancelled MRPD's anim before we even started
        if not stillOnSpot() then
            busy = false
            return
        end

        runLocker(loc, {
            anim = false,
            startedAt = startedAt,
            stillValid = stillOnSpot,   -- cancelling MRPD's anim during the delay aborts the open
            onClosed = function()
                if stillOnSpot() then
                    exports[MRPD]:StopPlayerAnim(false)
                end
            end,
        })
    end)
    return true
end

-- Watches MRPD's public IsPlayerAnimated() export and fires OpenFromMrpd on
-- the moment a locker spot's animation starts (rising edge only).
local function runMrpdWatcher()
    local M = Config.Lockers.Mrpd
    local lastSpot = nil

    while true do
        local wait = 1500
        if #(GetEntityCoords(PlayerPedId()) - M.center) < M.radius then
            wait = M.pollInterval
            local animating, spotId = exports[MRPD]:IsPlayerAnimated()
            spotId = animating and spotId or nil

            if spotId and spotId ~= lastSpot and Config.Lockers.ById[spotId] then
                DebugPrint('MRPD locker anim started on ' .. spotId)
                OpenFromMrpd(spotId)
            end
            lastSpot = spotId
        else
            lastSpot = nil
        end
        Wait(wait)
    end
end

exports('OpenLocker', OpenLocker)
exports('OpenFromMrpd', OpenFromMrpd)
exports('IsUsingLocker', function() return busy end)

-- ─── Interaction: target ────────────────────────────────────────────────────

local function addZones()
    local T = Config.Lockers.Target
    for _, loc in ipairs(Config.Lockers.Locations) do
        if loc.enabled ~= false then
            local id = exports.rps_lib:AddBoxZone('rps_locker_' .. loc.id, zonePoint(loc), T.size.y, T.size.x, loc.coords.w, {
                {
                    name = 'rps_locker_open_' .. loc.id,
                    icon = T.icon,
                    label = T.label,
                    canInteract = function()
                        return not busy and LockerCanSee(loc)
                    end,
                    onSelect = function()
                        OpenLocker(loc.id)
                    end,
                },
            }, T.distance)
            zoneIds[#zoneIds + 1] = id
        end
    end
end

local function removeZones()
    for _, id in ipairs(zoneIds) do
        exports.rps_lib:RemoveZone(id)
    end
    zoneIds = {}
end

-- ─── Interaction: 3D text (draws only the nearest locker — they're ~0.4 m apart)

local function run3dText()
    local T = Config.Lockers.Text3D
    while true do
        local wait = 1000
        if not busy then
            local pos = GetEntityCoords(PlayerPedId())
            local nearest, nearestDist, nearestPoint

            for _, loc in ipairs(Config.Lockers.Locations) do
                if loc.enabled ~= false then
                    local point = zonePoint(loc)
                    local dist = #(pos - point)
                    if dist < T.drawDistance and (not nearestDist or dist < nearestDist) then
                        nearest, nearestDist, nearestPoint = loc, dist, point
                    end
                end
            end

            if nearest and LockerCanSee(nearest) then
                wait = 0
                local inRange = nearestDist < T.interactDistance
                exports.rps_lib:DrawText3D(nearestPoint, inRange and (nearest.label .. '\n' .. T.text) or nearest.label, {
                    fancy = true,
                    accentColor = { 90, 160, 255 },
                    maxDistance = T.drawDistance,
                    marker = inRange,
                })
                if inRange and IsControlJustPressed(0, T.key) then
                    OpenLocker(nearest.id)
                end
            end
        end
        Wait(wait)
    end
end

-- ─── Startup / cleanup ──────────────────────────────────────────────────────

CreateThread(function()
    -- rps_lib's target detection is async; give it a moment.
    Wait(1000)

    local mode = Config.Lockers.Mode
    if mode == 'mrpd' or mode == 'mrpd_hooks' then
        while GetResourceState(MRPD) == 'starting' do Wait(100) end
        if GetResourceState(MRPD) == 'started' then
            return runMrpdWatcher()
        end
        print(('^3[rps_prompt_exstras]^7 Lockers Mode = "mrpd" but %s is not started, falling back to standalone'):format(MRPD))
    end

    if Config.Lockers.Interaction == 'target' and exports.rps_lib:GetTargetName() ~= 'none' then
        addZones()
    else
        run3dText()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeZones()
    if activeSession then
        LockerAnim.End(activeSession, true)
        activeSession = nil
    end
end)
