if not Config.Modules.evidence then return end

local E = Config.Evidence
local masterAccess = { jobs = E.Jobs, minGrade = E.MasterMinGrade }

-- Master locker menu → open any shelf. Re-checks rank + that the player is
-- actually at the evidence locker (the menu itself is client-side).
exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:evidence:openShelf', function(source, group)
    local shelf = E.ShelfByGroup[group]
    if not shelf then return { ok = false, reason = Config.Lockers.Text.failed } end

    if not LockerHasJobAccess(source, masterAccess) then
        return { ok = false, reason = E.Text.noAccess }
    end

    local ped = GetPlayerPed(source)
    if #(GetEntityCoords(ped) - E.MasterLocker.coords.xyz) > E.MasterMaxDistance then
        return { ok = false, reason = Config.Lockers.Text.tooFar }
    end

    local identifier = exports.rps_lib:GetIdentifier(source)
    local ok, clientData = LockerInv.Open(source, group, identifier, false)
    if not ok then return { ok = false, reason = Config.Lockers.Text.failed } end

    DebugPrint(('%s opened %s via the evidence locker'):format(GetPlayerName(source), shelf.label))
    return { ok = true, client = clientData }
end)
