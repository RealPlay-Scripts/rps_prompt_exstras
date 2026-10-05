if not Config.Modules.evidence then return end

local E = Config.Evidence
local MAIN_MENU = 'rps_evidence_main'

local function awaitServer(name, ...)
    local p = promise.new()
    exports.rps_lib:TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

--- Shows the category → shelf context menu. Blocks until the player either
--- picks a shelf (returns its group) or closes the menu (returns nil).
local function pickShelf()
    local selected = nil
    local mainOptions = {}

    for _, cat in ipairs(E.Categories) do
        if #cat.shelves > 0 then
            local menuId = 'rps_evidence_' .. cat.key
            local shelfOptions = {}

            for _, shelf in ipairs(cat.shelves) do
                shelfOptions[#shelfOptions + 1] = {
                    title = shelf.label,
                    description = E.Text.shelfDesc,
                    icon = 'box-open',
                    onSelect = function() selected = shelf.group end,
                }
            end

            lib.registerContext({ id = menuId, title = cat.label, menu = MAIN_MENU, options = shelfOptions })

            mainOptions[#mainOptions + 1] = {
                title = cat.label,
                description = E.Text.categoryFmt:format(#cat.shelves),
                icon = cat.icon,
                menu = menuId,
                arrow = true,
            }
        end
    end

    lib.registerContext({ id = MAIN_MENU, title = E.Text.menuTitle, options = mainOptions })
    lib.showContext(MAIN_MENU)

    -- Wait for the menu to close (moving between sub-menus keeps one open;
    -- a short grace re-check covers the switch itself).
    while true do
        Wait(100)
        if not lib.getOpenContextMenu() then
            Wait(150)
            if not lib.getOpenContextMenu() then break end
        end
    end

    return selected
end

-- Locker-engine handler for the evdlocker_1 location (`menu = 'evidence'`).
-- Loops: pick a shelf → its inventory → back to the menu, until the menu is closed.
LockerMenus.evidence = function()
    while true do
        local group = pickShelf()
        if not group or IsEntityDead(PlayerPedId()) then return end

        local res = awaitServer('rps_prompt_exstras:evidence:openShelf', group)
        if not res or not res.ok then
            exports.rps_lib:Notify(res and res.reason or Config.Lockers.Text.failed, 'error')
            return
        end

        LockerInvClient.Open(res.client)
        LockerInvClient.WaitForClose(3000)
    end
end
