if not Config.Modules.tech then return end

local T = Config.Tech

local function itemLabel(name)
    local def = exports.rps_lib:GetItemDefinition(name)
    return (def and def.label) or name
end

exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:tech:take', function(source, spotId)
    local spot = T.ById[spotId]
    if not spot then return { ok = false, reason = Config.Lockers.Text.failed } end

    if not LockerHasJobAccess(source, { jobs = T.Jobs, minGrade = spot.minGrade }) then
        return { ok = false, reason = Config.Lockers.Text.noAccess }
    end

    local ped = GetPlayerPed(source)
    if #(GetEntityCoords(ped) - spot.coords.xyz) > T.MaxDistance then
        return { ok = false, reason = Config.Lockers.Text.tooFar }
    end

    local label = itemLabel(spot.item)
    local have = exports.rps_lib:GetItemCount(source, spot.item) or 0
    if spot.max and have >= spot.max then
        return { ok = false, reason = T.Text.alreadyHave:format(label) }
    end

    local count = spot.count or 1
    if spot.max then count = math.min(count, spot.max - have) end

    if not exports.rps_lib:CanCarryItem(source, spot.item, count) then
        return { ok = false, reason = T.Text.cantCarry:format(label) }
    end

    exports.rps_lib:AddItem(source, spot.item, count)
    DebugPrint(('%s took %dx %s from %s'):format(GetPlayerName(source), count, spot.item, spot.id))
    return { ok = true, message = T.Text.received:format(('%dx %s'):format(count, label)) }
end)
