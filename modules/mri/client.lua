if not Config.Modules.mri then return end

local M = Config.MRI
local Text = M.Text

local function awaitServer(name, ...)
    local p = promise.new()
    exports.rps_lib:TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

-- ═══ PATIENT: body probe (server asks via rps_lib client callback) ═══════════

local function regionFromBone(bone)
    for key, region in pairs(M.Regions) do
        for _, id in ipairs(region.bones) do
            if id == bone then return key end
        end
    end
    return nil
end

local ENV_CAUSES = {
    fall      = { 'WEAPON_FALL' },
    vehicle   = { 'WEAPON_RUN_OVER_BY_CAR', 'WEAPON_RAMMED_BY_CAR' },
    explosion = { 'WEAPON_EXPLOSION' },
    fire      = { 'WEAPON_FIRE' },
}

local function damageCause(ped)
    for cause, weapons in pairs(ENV_CAUSES) do
        for _, weapon in ipairs(weapons) do
            if HasPedBeenDamagedByWeapon(ped, joaat(weapon), 0) then return cause end
        end
    end
    if HasPedBeenDamagedByWeapon(ped, 0, 1) then return 'melee' end   -- any melee
    if HasPedBeenDamagedByWeapon(ped, 0, 2) then return 'gunshot' end -- any other weapon
    return nil
end

exports.rps_lib:RegisterClientCallback('rps_prompt_exstras:mri:probe', function()
    local ped = PlayerPedId()
    local maxHealth = math.max(GetEntityMaxHealth(ped) - 100, 1)
    local health = math.max(GetEntityHealth(ped) - 100, 0)

    local hasBone, bone = GetPedLastDamageBone(ped)

    return {
        healthPct = IsEntityDead(ped) and 0 or math.floor(health / maxHealth * 100 + 0.5),
        armour    = GetPedArmour(ped),
        region    = hasBone and regionFromBone(bone) or nil,
        cause     = damageCause(ped),
        onMri     = GetResourceState(M.Resource) == 'started' and exports[M.Resource]:IsOnMri() or false,
    }
end)

RegisterNetEvent('rps_prompt_exstras:mri:patientDone', function()
    exports.rps_lib:Notify(Text.patientDone, 'info')
end)

-- ═══ OPERATOR: report on screen ══════════════════════════════════════════════

-- MRI report sheet (web/mri.*). uploadToken = the server wants the rendered
-- sheet back as a JPEG for the Discord log.
local function showScan(scan, uploadToken)
    if not scan then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'mriShow', scan = scan, uploadToken = uploadToken })
end

RegisterNUICallback('mriClose', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- NUI rendered the whole sheet → send it to the server (latent: ~200-400 KB)
RegisterNUICallback('mriImage', function(data, cb)
    cb('ok')
    if type(data) ~= 'table' or type(data.token) ~= 'string' or type(data.image) ~= 'string' then return end
    local b64 = data.image:gsub('^data:image/%a+;base64,', '')
    TriggerLatentServerEvent('rps_prompt_exstras:mri:image', 200000, data.token, b64)
end)

RegisterNetEvent('rps_prompt_exstras:mri:report', function(report)
    PlaySoundFrontend(-1, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET', true)
    showScan(report.scan, report.uploadToken)
end)

-- MRI film item used → show that report
RegisterNetEvent('rps_prompt_exstras:mri:show', function(scan)
    showScan(scan)
end)

-- several films in the inventory → pick one
RegisterNetEvent('rps_prompt_exstras:mri:pickFilm', function(films)
    local options = {}
    for _, film in ipairs(films) do
        options[#options + 1] = {
            title = film.label,
            icon = 'x-ray',
            onSelect = function() TriggerServerEvent('rps_prompt_exstras:mri:openFilm', film.id) end,
        }
    end
    lib.registerContext({ id = 'rps_mri_films', title = Text.pickFilm, options = options })
    lib.showContext('rps_mri_films')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)

-- /mriscans [serverId]
local function listScans(targetId)
    local res = awaitServer('rps_prompt_exstras:mri:list', targetId)
    if not res or res.error then
        return exports.rps_lib:Notify(res and res.error or Text.noAccess, 'error')
    end
    if #res.rows == 0 then return exports.rps_lib:Notify(Text.noneFound, 'info') end

    local options = {}
    for _, row in ipairs(res.rows) do
        options[#options + 1] = {
            title = ('%s — %s'):format(row.name or '?', row.severity or '?'),
            description = ('%s · by %s'):format(row.created_at or '', row.operator or '?'),
            icon = 'x-ray',
            onSelect = function() showScan(row.scan) end,
        }
    end

    lib.registerContext({ id = 'rps_mri_list', title = Text.listTitle, options = options })
    lib.showContext('rps_mri_list')
end

RegisterCommand('mriscans', function(_, args)
    CreateThread(function() listScans(args[1]) end)
end, false)
