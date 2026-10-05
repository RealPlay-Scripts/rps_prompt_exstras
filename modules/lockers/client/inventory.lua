--[[
    Client half of the stash bridge: opens stashes for inventories that can
    only be opened client-side, and waits until the inventory UI is closed
    again (so the locker "close door" animation plays at the right moment).
]]

if not LockerEngineEnabled() then return end

LockerInvClient = {}

--- data = the table returned by the server's LockerInv.Open (nil when the
--- server already opened it, e.g. ox_inventory / qb-inventory v2).
function LockerInvClient.Open(data)
    if not data then return end

    if data.inventory == 'tgiann-inventory' then
        exports['tgiann-inventory']:OpenInventory('stash', data.id, {
            maxweight = data.weight,
            slots     = data.slots,
        })
    else
        -- qb-inventory (legacy) / ps-inventory / lj-inventory / qs-inventory
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', data.id, {
            maxweight = data.weight,
            slots     = data.slots,
        })
        TriggerEvent('inventory:client:SetCurrentStash', data.id)
    end
end

local function usesOx()
    local forced = Config.Lockers.Inventory
    if forced and forced ~= 'auto' then return forced == 'ox_inventory' end
    return GetResourceState('ox_inventory') == 'started'
end

local function isInventoryOpen()
    if usesOx() then
        return LocalPlayer.state.invOpen == true
    end
    return IsNuiFocused()
end

--- Blocks until the inventory UI has opened and closed again.
--- Returns false if it never opened (within openTimeout ms).
function LockerInvClient.WaitForClose(openTimeout)
    local started = GetGameTimer()
    while not isInventoryOpen() do
        if GetGameTimer() - started > (openTimeout or 3000) then return false end
        Wait(50)
    end

    local ped = PlayerPedId()
    while isInventoryOpen() do
        if IsEntityDead(ped) then break end
        Wait(150)
    end
    return true
end

-- Admin inspection for client-opened inventories
RegisterNetEvent('rps_prompt_exstras:lockers:clientOpen', function(data)
    LockerInvClient.Open(data)
end)
