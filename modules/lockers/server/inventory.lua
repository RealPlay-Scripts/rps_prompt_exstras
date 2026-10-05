--[[
    Server stash bridge. rps_lib has no stash abstraction (see rps_stashcreator),
    so this talks to each inventory directly.

    Open() either opens the stash server-side (ox_inventory, qb-inventory v2)
    and returns nil, or returns a table the client uses to open it.
]]

if not LockerEngineEnabled() then return end

LockerInv = {}

local inventoryName
local registered = {}   -- [stashId] = true (tgiann / qs registration cache)

local function isQbV2()
    local version = GetResourceMetadata('qb-inventory', 'version', 0) or '0'
    return (tonumber(version:match('^(%d+)')) or 0) >= 2
end

function LockerInv.Name()
    if inventoryName then return inventoryName end

    local forced = Config.Lockers.Inventory
    if forced and forced ~= 'auto' then
        inventoryName = forced
    elseif GetResourceState('qs-inventory') == 'started' then
        inventoryName = 'qs-inventory'
    else
        inventoryName = exports.rps_lib:GetInventoryName()
    end

    print(('^5[rps_prompt_exstras]^7 lockers using inventory: ^3%s^7'):format(inventoryName))
    return inventoryName
end

local function sanitize(identifier)
    return (tostring(identifier):gsub('[^%w_]', '_'))
end

--- Shared groups (armory storages) have one stash for everyone.
--- ox_inventory personal groups get ONE stash registered with owner = true
--- (it instances it per player itself); everything else gets one id per player.
function LockerInv.StashId(group, identifier)
    local data = Config.Lockers.Groups[group]
    if (data and data.shared) or LockerInv.Name() == 'ox_inventory' then
        return 'rps_locker_' .. group
    end
    return ('rps_locker_%s_%s'):format(group, sanitize(identifier))
end

--- Called once on start (ox_inventory needs every group registered up front).
function LockerInv.Init()
    if LockerInv.Name() ~= 'ox_inventory' then return end

    for group, data in pairs(Config.Lockers.Groups) do
        local owner = (not data.shared) or nil   -- true = per player, nil = shared
        exports.ox_inventory:RegisterStash('rps_locker_' .. group, data.label, data.slots, data.weight, owner)
    end
end

local function ensureRegistered(source, inv, stashId, data)
    if inv == 'tgiann-inventory' then
        if not registered[stashId] then
            exports['tgiann-inventory']:RegisterStash(stashId, data.label, data.slots, data.weight)
            registered[stashId] = true
        end
    elseif inv == 'qs-inventory' then
        -- qs registers per opening player
        exports['qs-inventory']:RegisterStash(source, stashId, data.slots, data.weight)
    end
end

--- Opens `group` stash owned by `ownerIdentifier` for `source`.
--- ownerIdentifier ~= source's own identifier only for admin inspection.
function LockerInv.Open(source, group, ownerIdentifier, isInspect)
    local inv = LockerInv.Name()
    local data = Config.Lockers.Groups[group]
    if not data then return false end

    local stashId = LockerInv.StashId(group, ownerIdentifier)

    if inv == 'ox_inventory' then
        local payload = (isInspect and not data.shared) and { id = stashId, owner = ownerIdentifier } or stashId
        local opened = exports.ox_inventory:forceOpenInventory(source, 'stash', payload)
        return opened ~= nil, nil
    end

    if inv == 'qb-inventory' and isQbV2() then
        exports['qb-inventory']:OpenInventory(source, stashId, {
            label = data.label, maxweight = data.weight, slots = data.slots,
        })
        return true, nil
    end

    if inv == 'tgiann-inventory' or inv == 'qs-inventory'
        or inv == 'qb-inventory' or inv == 'ps-inventory' or inv == 'lj-inventory' then
        ensureRegistered(source, inv, stashId, data)
        return true, {
            inventory = inv,
            id        = stashId,
            label     = data.label,
            slots     = data.slots,
            weight    = data.weight,
        }
    end

    return false, nil
end

--- Moves up to `wanted` of `item` from a (shared) group stash into `source`'s
--- inventory, slot by slot so per-item metadata (weapon serials, ammo,
--- durability) is kept. Returns the amount actually moved.
--- Supported: ox_inventory, tgiann-inventory (both accept a stash name as the
--- inventory argument). Other inventories return 0.
local warnedUnsupported = false
function LockerInv.TakeFromStash(group, source, item, wanted)
    local inv = LockerInv.Name()
    local stashId = LockerInv.StashId(group)
    local moved = 0

    if inv == 'ox_inventory' then
        local ox = exports.ox_inventory
        for _, slot in pairs(ox:GetSlotsWithItem(stashId, item) or {}) do
            if moved >= wanted then break end
            local take = math.min(slot.count or 0, wanted - moved)
            if take > 0 and ox:CanCarryItem(source, item, take, slot.metadata) then
                if ox:RemoveItem(stashId, item, take, slot.metadata, slot.slot) then
                    ox:AddItem(source, item, take, slot.metadata)
                    moved = moved + take
                end
            end
        end

    elseif inv == 'tgiann-inventory' then
        local tg = exports['tgiann-inventory']
        ensureRegistered(source, inv, stashId, Config.Lockers.Groups[group])
        for _, slot in pairs(tg:GetSlotsWithItem(stashId, item) or {}) do
            if moved >= wanted then break end
            local take = math.min(slot.amount or slot.count or 0, wanted - moved)
            local meta = slot.info or slot.metadata
            if take > 0 and tg:CanCarryItem(source, item, take) then
                if tg:RemoveItem(stashId, item, take, slot.slot) then
                    tg:AddItem(source, item, take, nil, meta)
                    moved = moved + take
                end
            end
        end

    elseif not warnedUnsupported then
        warnedUnsupported = true
        print(('^3[rps_prompt_exstras]^7 armory loadout needs ox_inventory or tgiann-inventory (current: %s)'):format(inv))
    end

    return moved
end
