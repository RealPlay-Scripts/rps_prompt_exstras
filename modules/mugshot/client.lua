if not Config.Modules.mugshot then return end

local C = Config.Mugshot
local Text = C.Text
local MRPD = 'prompt_mrpd_scripts'

local zoneId = nil
local busy = false
local cam = nil

local function awaitServer(name, ...)
    local p = promise.new()
    exports.rps_lib:TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

-- Same rule as the locker engine (UI gating only — the server re-checks).
local function canUse()
    local jobs = C.Jobs
    if not jobs or #jobs == 0 then jobs = Config.Lockers.DefaultJobs end
    local player = exports.rps_lib:GetPlayerData()
    local job = player and player.job
    if not job or not job.name then return false end
    local grade = job.grade and tonumber(job.grade.level) or 0
    for _, name in ipairs(jobs) do
        if name == job.name then return grade >= (C.MinGrade or 0) end
    end
    return false
end

-- ═══ SUSPECT SIDE ═══════════════════════════════════════════════════════════

-- Flags this player as "ready" while they're in MRPD's mug-cart animation
-- (after the camera has eased in), via a replicated state bag the server reads.
CreateThread(function()
    while GetResourceState(MRPD) == 'starting' do Wait(100) end
    if GetResourceState(MRPD) ~= 'started' then return end

    local ready = false
    local function setReady(value)
        if ready == value then return end
        ready = value
        LocalPlayer.state:set('rpsMugshotReady', value, true)
    end

    while true do
        local wait = 1500
        if #(GetEntityCoords(PlayerPedId()) - C.Cart.coords) < 15.0 then
            wait = 250
            local animating, spotId = exports[MRPD]:IsPlayerAnimated()
            local onCart = animating and spotId == C.Cart.spotId

            if onCart and not ready then
                Wait(C.Cart.readyDelay)
                animating, spotId = exports[MRPD]:IsPlayerAnimated()
                setReady(animating and spotId == C.Cart.spotId)
            elseif not onCart then
                setReady(false)
            end
        else
            setReady(false)
        end
        Wait(wait)
    end
end)

local function destroyCam()
    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

-- Server is about to capture this player's screen.
RegisterNetEvent('rps_prompt_exstras:mugshot:prepare', function(useOwnCam)
    if useOwnCam then
        local ped = PlayerPedId()
        local p = C.Camera.pos
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z, 0.0, 0.0, 0.0, C.Camera.fov, false, 0)
        local o = C.Camera.aimOffset
        PointCamAtPedBone(cam, ped, 31086, o.x, o.y, o.z, true)   -- SKEL_Head
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
    end

    -- hide HUD / radar for the capture
    CreateThread(function()
        local untilTime = GetGameTimer() + C.HideHudMs
        DisplayRadar(false)
        while GetGameTimer() < untilTime do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
        DisplayRadar(true)
    end)
end)

RegisterNetEvent('rps_prompt_exstras:mugshot:finish', function(success)
    if success then
        PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
        exports.rps_lib:Notify(Text.suspectTaken, 'info')
    end
    Wait(300)
    destroyCam()
end)

-- ═══ OFFICER SIDE ═══════════════════════════════════════════════════════════

local function showMugshot(title, url, subtitle)
    lib.alertDialog({
        header   = title,
        content  = ('![mugshot](%s)%s'):format(url, subtitle and ('\n\n' .. subtitle) or ''),
        centered = true,
        size     = 'lg',
    })
end

local function takeMugshot()
    if busy then return end
    busy = true

    local res = awaitServer('rps_prompt_exstras:mugshot:take')
    if not res or res.error then
        exports.rps_lib:Notify(res and res.error or Text.failed, 'error')
    else
        exports.rps_lib:Notify(Text.taken:format(res.name), 'success')
        showMugshot(res.name, res.url)
    end

    busy = false
end

local function someoneAtCart()
    if not C.RequireMugCart then return true end
    for _, player in ipairs(GetActivePlayers()) do
        if Player(GetPlayerServerId(player)).state.rpsMugshotReady then return true end
    end
    return false
end

CreateThread(function()
    Wait(1000)   -- rps_lib target detection is async
    local S = C.Station

    if exports.rps_lib:GetTargetName() ~= 'none' then
        zoneId = exports.rps_lib:AddBoxZone('rps_mugshot_station', S.coords, S.size.y, S.size.x, S.heading, {
            {
                name = 'rps_mugshot_take',
                icon = S.icon,
                label = S.label,
                canInteract = function() return not busy and canUse() and someoneAtCart() end,
                onSelect = function() CreateThread(takeMugshot) end,
            },
        }, S.distance)
        return
    end

    -- 3D text fallback
    local T = Config.Lockers.Text3D
    while true do
        local wait = 1000
        local dist = #(GetEntityCoords(PlayerPedId()) - S.coords)
        if dist < T.drawDistance and not busy and canUse() then
            wait = 0
            local inRange = dist < S.distance
            exports.rps_lib:DrawText3D(S.coords + vec3(0.0, 0.0, 0.5),
                inRange and (S.label .. '\n' .. T.text) or S.label,
                { fancy = true, accentColor = { 90, 160, 255 }, maxDistance = T.drawDistance, marker = inRange })
            if inRange and IsControlJustPressed(0, T.key) then CreateThread(takeMugshot) end
        end
        Wait(wait)
    end
end)

-- /mugshots [serverId] — latest mugshots (of one player, or everyone)
local function listMugshots(targetId)
    local res = awaitServer('rps_prompt_exstras:mugshot:list', targetId)
    if not res or res.error then
        return exports.rps_lib:Notify(res and res.error or Text.failed, 'error')
    end
    if #res.rows == 0 then return exports.rps_lib:Notify(Text.noneFound, 'info') end

    local options = {}
    for _, row in ipairs(res.rows) do
        options[#options + 1] = {
            title = row.name or '?',
            description = ('%s · by %s'):format(row.created_at or '', row.officer or '?'),
            icon = 'camera',
            image = row.url,   -- ox_lib shows this as a hover preview
            onSelect = function()
                showMugshot(row.name or '?', row.url, ('%s · by %s'):format(row.created_at or '', row.officer or '?'))
            end,
        }
    end

    lib.registerContext({ id = 'rps_mugshot_list', title = Text.listTitle, options = options })
    lib.showContext('rps_mugshot_list')
end

-- mugshot photo item used → show it (pick one if there are several)
RegisterNetEvent('rps_prompt_exstras:mugshot:photos', function(photos)
    if #photos == 1 then
        return showMugshot(photos[1].title, photos[1].url, photos[1].desc)
    end
    local options = {}
    for _, p in ipairs(photos) do
        options[#options + 1] = {
            title = p.title,
            description = p.desc,
            icon = 'camera',
            image = p.url,
            onSelect = function() showMugshot(p.title, p.url, p.desc) end,
        }
    end
    lib.registerContext({ id = 'rps_mugshot_photos', title = Text.listTitle, options = options })
    lib.showContext('rps_mugshot_photos')
end)

-- /mugcam — take the mugshot without the target (server checks the distance)
if C.Command then
    RegisterCommand(C.Command, function()
        if not canUse() then return exports.rps_lib:Notify(Text.noAccess, 'error') end
        if busy then return exports.rps_lib:Notify(Text.busy, 'error') end
        CreateThread(takeMugshot)
    end, false)
end

RegisterCommand('mugshots', function(_, args)
    if not canUse() then return exports.rps_lib:Notify(Text.noAccess, 'error') end
    CreateThread(function() listMugshots(args[1]) end)
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if zoneId then exports.rps_lib:RemoveZone(zoneId) end
    destroyCam()
    LocalPlayer.state:set('rpsMugshotReady', false, true)
end)
