Config = {}

-- Prints extra [rps_prompt_exstras] lines to the F8 / server console.
Config.Debug = false

-- Turn modules on/off. A disabled module registers nothing (no zones, threads, commands).
Config.Modules = {
    lockers = true,   -- personal lockers in Prompt's MRPD (change lockers)
    armory  = true,   -- MRPD armory: 2 gun-locker storages + quartermaster loadout ped
    evidence = true,  -- MRPD evidence: every shelf its own stash + high-rank master locker menu
    tech     = true,  -- MRPD tech: body cam shelves (bodycam / dashcam) + drone wall (drone)
    mugshot  = true,  -- MRPD mug cart + screencapture → uploaded mugshots (needs screencapture + oxmysql)
    mri      = true,  -- Prompt Pillbox MRI → MRI reports for finished scans (needs prompt_pillbox_hospital)
}

-- Armory / evidence / tech spots run on the locker engine, so it loads when any is on.
function LockerEngineEnabled()
    return Config.Modules.lockers or Config.Modules.armory or Config.Modules.evidence or Config.Modules.tech
end

function DebugPrint(...)
    if Config.Debug then
        print('^5[rps_prompt_exstras]^7', ...)
    end
end
