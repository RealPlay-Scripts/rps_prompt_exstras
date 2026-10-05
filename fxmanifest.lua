
--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--]]

fx_version 'cerulean'

game 'gta5'

lua54 'yes'

name 'rps_prompt_exstras'

author 'Realplay Scrips'

description 'Extras for Prompt maps (MRPD personal lockers, ...) built on rps_lib'

version     '1.0.0'

--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--]]

shared_scripts {
    '@ox_lib/init.lua',   -- evidence master menu (lib.registerContext)
    'config.lua',
    'modules/lockers/config.lua',
    'modules/armory/config.lua',
    'modules/evidence/config.lua',
    'modules/tech/config.lua',
    'modules/mugshot/config.lua',
    'modules/mri/config.lua'
}

client_scripts {
    'modules/lockers/client/inventory.lua',
    'modules/lockers/client/anim.lua',
    'modules/lockers/client/main.lua',
    'modules/armory/client.lua',
    'modules/evidence/client.lua',
    'modules/tech/client.lua',
    'modules/mugshot/client.lua',
    'modules/mri/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',   -- mugshot records
    'modules/lockers/server/inventory.lua',
    'modules/lockers/server/main.lua',
    'modules/armory/server.lua',
    'modules/evidence/server.lua',
    'modules/tech/server.lua',
    'modules/mugshot/server.lua',
    'modules/mri/server.lua'
}

--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--]]

-- MRI scan image
ui_page 'web/mri.html'

files {
    'web/mri.html',
    'web/mri.css',
    'web/mri.js'
}

dependency {
    'ox_lib',
    'oxmysql',
    'rps_lib'
}

escrow_ignore {
    'config.lua',
    'modules/lockers/config.lua',
    'modules/armory/config.lua',
    'modules/evidence/config.lua',
    'modules/tech/config.lua',
    'modules/mugshot/config.lua',
    'modules/mri/config.lua',
    'web/mri.html',
    'web/mri.css',
    'web/mri.js'
}

--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--]]
