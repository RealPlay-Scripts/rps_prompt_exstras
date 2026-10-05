if not Config.Modules.tech then return end

local function awaitServer(name, ...)
    local p = promise.new()
    exports.rps_lib:TriggerServerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

-- Locker-engine handler for the tech spots (`menu = 'tech'`). Runs once the
-- spot's openDelay has passed (animation playing); returning ends the anim.
LockerMenus.tech = function(loc)
    local res = awaitServer('rps_prompt_exstras:tech:take', loc.id)
    if res and res.ok then
        exports.rps_lib:Notify(res.message, 'success')
    else
        exports.rps_lib:Notify(res and res.reason or Config.Lockers.Text.failed, 'error')
    end
end
