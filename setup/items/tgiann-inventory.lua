-- ════════════════════════════════════════════════════════════════════════════
--  rps_prompt_exstras items — tgiann-inventory
--  Paste INSIDE the `itemsData = { ... }` table in
--  tgiann-inventory/items/items.lua, then restart tgiann-inventory.
--  Images: copy setup/items/images/*.png to tgiann-inventory's item image
--  folder (see https://tgiann.gitbook.io/tgiann/scripts/tgiann-inventory/guides/item-images).
--
--  bodycam / dash_cam / drone already exist in tgiann's default list — only
--  add them if your list doesn't have them yet (a duplicate key overwrites).
-- ════════════════════════════════════════════════════════════════════════════

    -- rps_prompt_exstras: MRI film (using it reopens the MRI report sheet)
    mri_scan       = { hasMetadata = true, label = 'MRI Film', weight = 100, type = 'item', image = 'mri_scan.png', useable = true, shouldClose = true, description = 'MRI report from Pillbox Hill Medical Center' },

    -- rps_prompt_exstras: mugshot photo (using it shows the photo)
    mugshot_photo  = { hasMetadata = true, label = 'Mugshot Photo', weight = 50, type = 'item', image = 'mugshot_photo.png', useable = true, shouldClose = true, description = 'LSPD booking photo' },

    -- rps_prompt_exstras tech module (only if missing from your list)
    -- bodycam     = { label = 'Bodycam', weight = 100, type = 'item', image = 'bodycam.png', useable = true, shouldClose = true, description = '' },
    -- dash_cam    = { label = 'Dashcam', weight = 100, type = 'item', image = 'dash_cam.png', useable = true, shouldClose = true, description = '' },
    -- drone       = { label = 'Drone', weight = 100, type = 'item', image = 'drone.png', useable = true, shouldClose = true, description = '' },
