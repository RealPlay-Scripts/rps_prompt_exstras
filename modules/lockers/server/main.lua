if not LockerEngineEnabled() then return end

local Text = Config.Lockers.Text

--- loc = anything with `jobs` / `minGrade` (locker location, armory ped, ...)
function LockerHasJobAccess(source, loc)
    local jobs = loc.jobs
    if jobs == 'all' then return true end
    if not jobs or #jobs == 0 then jobs = Config.Lockers.DefaultJobs end

    local player = exports.rps_lib:GetPlayerData(source)
    local job = player and player.job
    if not job or not job.name then return false end

    local grade = job.grade and tonumber(job.grade.level) or 0
    for _, name in ipairs(jobs) do
        if name == job.name then
            return grade >= (loc.minGrade or 0)
        end
    end
    return false
end

local function isNear(source, loc)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - loc.coords.xyz) <= Config.Lockers.MaxDistance
end

local function validate(source, locationId)
    local loc = Config.Lockers.ById[locationId]
    if not loc or loc.enabled == false then return nil, Text.failed end
    if not LockerHasJobAccess(source, loc) then return nil, loc.noAccessText or Text.noAccess end
    if not isNear(source, loc) then return nil, Text.tooFar end
    return loc
end

-- Step 1: access check before the client starts the animation.
exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:lockers:prepare', function(source, locationId)
    local loc, reason = validate(source, locationId)
    return { ok = loc ~= nil, reason = reason }
end)

-- Step 2: re-validate and open (called once the "open door" phase finished).
exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:lockers:open', function(source, locationId)
    local loc, reason = validate(source, locationId)
    if not loc then return { ok = false, reason = reason } end

    local identifier = exports.rps_lib:GetIdentifier(source)
    if not identifier then return { ok = false, reason = Text.failed } end

    local ok, clientData = LockerInv.Open(source, loc.group, identifier, false)
    if not ok then
        return { ok = false, reason = LockerInv.Name() == 'none' and Text.noInventory or Text.failed }
    end

    DebugPrint(('%s opened locker %s (%s)'):format(GetPlayerName(source), loc.id, loc.group))
    return { ok = true, client = clientData }
end)

-- /lockerinspect <serverId> [group]
RegisterCommand(Config.Lockers.AdminCommand, function(source, args)
    if source == 0 then return end
    if not exports.rps_lib:HasPermission(source, Config.Lockers.AdminPermission) then
        return exports.rps_lib:Notify(source, Text.noPerm, 'error')
    end

    local target = tonumber(args[1])
    local identifier = target and exports.rps_lib:GetIdentifier(target)
    if not identifier then
        return exports.rps_lib:Notify(source, Text.noTarget, 'error')
    end

    local group = args[2] or 'mrpd_change'
    if not Config.Lockers.Groups[group] then
        return exports.rps_lib:Notify(source, Text.failed, 'error')
    end

    local ok, clientData = LockerInv.Open(source, group, identifier, true)
    if not ok then
        return exports.rps_lib:Notify(source, Text.failed, 'error')
    end
    if clientData then
        TriggerClientEvent('rps_prompt_exstras:lockers:clientOpen', source, clientData)
    end
end, false)

CreateThread(function()
    -- rps_lib's inventory detection is async; give it a moment.
    Wait(1500)
    LockerInv.Init()
end)
