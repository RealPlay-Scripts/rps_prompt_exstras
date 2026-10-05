-- ════════════════════════════════════════════════════════════════════════════
--  rps_prompt_exstras items — QBCore (qb-inventory / ps-inventory / lj-inventory)
--  Paste INSIDE QBShared.Items in qb-core/shared/items.lua, then restart.
--  Images: copy setup/items/images/*.png to your inventory's html/images/.
--  (Qbox uses ox_inventory — use ox_inventory.lua instead.)
-- ════════════════════════════════════════════════════════════════════════════

    mri_scan      = { name = 'mri_scan', label = 'MRI Film', weight = 100, type = 'item', image = 'mri_scan.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'MRI report from Pillbox Hill Medical Center' },
    mugshot_photo = { name = 'mugshot_photo', label = 'Mugshot Photo', weight = 50, type = 'item', image = 'mugshot_photo.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'LSPD booking photo' },

    -- tech module (skip any you already have)
    bodycam       = { name = 'bodycam', label = 'Bodycam', weight = 100, type = 'item', image = 'bodycam.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = '' },
    dash_cam      = { name = 'dash_cam', label = 'Dashcam', weight = 100, type = 'item', image = 'dash_cam.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = '' },
    drone         = { name = 'drone', label = 'Drone', weight = 1000, type = 'item', image = 'drone.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = '' },
