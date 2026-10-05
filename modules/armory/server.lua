if not Config.Modules.armory then return end

local Q = Config.Armory.Quartermaster
local Text = Config.Armory.Text
local lastRequest = {}   -- [source] = os.time()

local function itemLabel(name)
    local def = exports.rps_lib:GetItemDefinition(name)
    return (def and def.label) or name
end

local function formatList(list)
    local parts = {}
    for _, entry in ipairs(list) do
        parts[#parts + 1] = ('%dx %s'):format(entry.count, itemLabel(entry.name))
    end
    return table.concat(parts, ', ')
end

local function playerGrade(source)
    local player = exports.rps_lib:GetPlayerData(source)
    local job = player and player.job
    return job and job.grade and tonumber(job.grade.level) or 0
end

--- Gives `source` every loadout item they're short of, taken from the armory
--- storages. Returns { given = {...}, missing = {...} } or { error = msg }.
local function fillLoadout(source)
    local grade = playerGrade(source)
    local given, missing = {}, {}

    for _, entry in ipairs(Config.Armory.Loadout) do
        if grade >= (entry.minGrade or 0) then
            local have = exports.rps_lib:GetItemCount(source, entry.name) or 0
            local need = entry.count - have

            if need > 0 then
                local moved = 0
                for _, group in ipairs(Config.Armory.LoadoutFrom) do
                    if moved >= need then break end
                    moved = moved + LockerInv.TakeFromStash(group, source, entry.name, need - moved)
                end

                if moved > 0 then given[#given + 1] = { name = entry.name, count = moved } end
                if moved < need then missing[#missing + 1] = { name = entry.name, count = need - moved } end
            end
        end
    end

    return { given = given, missing = missing }
end

exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:armory:loadout', function(source)
    local access = { jobs = Config.Armory.Jobs }
    if not LockerHasJobAccess(source, access) then
        return { error = Text.noAccess }
    end

    local ped = GetPlayerPed(source)
    if #(GetEntityCoords(ped) - Q.coords.xyz) > Q.maxDistance then
        return { error = Text.tooFar }
    end

    local now = os.time()
    local last = lastRequest[source]
    if last and now - last < Q.cooldown then
        return { error = Text.cooldown:format(Q.cooldown - (now - last)) }
    end
    lastRequest[source] = now

    local result = fillLoadout(source)
    DebugPrint(('%s loadout: given [%s] missing [%s]'):format(
        GetPlayerName(source), formatList(result.given), formatList(result.missing)))

    return {
        given   = #result.given > 0 and formatList(result.given) or nil,
        missing = #result.missing > 0 and formatList(result.missing) or nil,
    }
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
