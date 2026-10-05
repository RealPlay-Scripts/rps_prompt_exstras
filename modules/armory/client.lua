if not Config.Modules.armory then return end

local Q = Config.Armory.Quartermaster
local Text = Config.Armory.Text
local access = { jobs = Config.Armory.Jobs }

local ped = nil
local zoneId = nil
local busy = false

local function awaitServer(name, ...)
    local p = promise.new()
    exports.rps_lib:TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

-- Ped hands something over, player takes it.
local function playHandover()
    if not Q.handover or not ped or not loadDict('mp_common') then return end

    local player = PlayerPedId()
    TaskTurnPedToFaceEntity(player, ped, 800)
    Wait(800)

    ClearPedTasks(ped)
    TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 0, 0.0, false, false, false)
    TaskPlayAnim(player, 'mp_common', 'givetake1_a', 8.0, -8.0, 2000, 0, 0.0, false, false, false)
    Wait(2000)

    if Q.scenario then TaskStartScenarioInPlace(ped, Q.scenario, 0, true) end
    RemoveAnimDict('mp_common')
end

local function collectLoadout()
    if busy then return end
    busy = true

    playHandover()

    local res = awaitServer('rps_prompt_exstras:armory:loadout')
    if not res then
        exports.rps_lib:Notify(Config.Lockers.Text.failed, 'error')
    elseif res.error then
        exports.rps_lib:Notify(res.error, 'error')
    else
        if res.given then
            exports.rps_lib:ShowNotification({ title = 'Armory', description = Text.received:format(res.given), type = 'success', duration = 7000 })
        end
        if res.missing then
            exports.rps_lib:ShowNotification({ title = 'Armory', description = Text.outOfStock:format(res.missing), type = 'error', duration = 7000 })
        end
        -- nothing given and nothing short = player already carries the full loadout
        if not res.given and not res.missing then
            exports.rps_lib:ShowNotification({ title = 'Quartermaster', description = Text.complete, type = 'info', duration = 6000 })
        end
    end

    busy = false
end

-- ─── Ped lifecycle (spawned locally when close, removed when far) ────────────

local function spawnPed()
    local hash = joaat(Q.model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return end
        Wait(10)
    end

    local c = Q.coords
    ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    if Q.scenario then TaskStartScenarioInPlace(ped, Q.scenario, 0, true) end

    -- Box zone instead of an entity target: works with every target rps_lib
    -- supports (tgiann-target needs net ids, which a local ped doesn't have).
    if Config.Lockers.Interaction == 'target' and exports.rps_lib:GetTargetName() ~= 'none' then
        zoneId = exports.rps_lib:AddBoxZone('rps_armory_quartermaster', c.xyz, 1.0, 1.0, c.w, {
            {
                name = 'rps_armory_loadout',
                icon = Q.target.icon,
                label = Q.target.label,
                canInteract = function() return not busy and LockerCanSee(access) end,
                onSelect = function() CreateThread(collectLoadout) end,
            },
        }, Q.target.distance)
    end
end

local function deletePed()
    if zoneId then
        exports.rps_lib:RemoveZone(zoneId)
        zoneId = nil
    end
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    ped = nil
end

CreateThread(function()
    Wait(1000)   -- rps_lib target detection is async
    local T = Config.Lockers.Text3D

    while true do
        local wait = 1000
        local dist = #(GetEntityCoords(PlayerPedId()) - Q.coords.xyz)

        if dist < Q.spawnDistance and not ped then
            spawnPed()
        elseif dist >= Q.spawnDistance and ped then
            deletePed()
        end

        -- 3D text fallback when no target system is used
        if ped and not zoneId and dist < T.drawDistance and not busy and LockerCanSee(access) then
            wait = 0
            local inRange = dist < Q.target.distance
            exports.rps_lib:DrawText3D(Q.coords.xyz + vec3(0.0, 0.0, 1.0),
                inRange and (Q.target.label .. '\n' .. T.text) or Q.target.label,
                { fancy = true, accentColor = { 90, 160, 255 }, maxDistance = T.drawDistance, marker = inRange })
            if inRange and IsControlJustPressed(0, T.key) then
                CreateThread(collectLoadout)
            end
        end

        Wait(wait)
    end
end)

-- Stand where the quartermaster should be and run /armorypos → paste into config.
RegisterCommand('armorypos', function()
    local p = PlayerPedId()
    local c, h = GetEntityCoords(p), GetEntityHeading(p)
    local line = ('coords = vec4(%.2f, %.2f, %.2f, %.1f),'):format(c.x, c.y, c.z, h)
    print(line)
    exports.rps_lib:Notify('Printed to F8: ' .. line, 'info')
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then deletePed() end
end)
