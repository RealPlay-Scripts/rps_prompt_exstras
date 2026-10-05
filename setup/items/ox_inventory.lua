-- ════════════════════════════════════════════════════════════════════════════
--  rps_prompt_exstras items — ox_inventory
--  Paste INSIDE the table returned by ox_inventory/data/items.lua,
--  then restart ox_inventory.
--  Images: copy setup/items/images/*.png to ox_inventory/web/images/.
--
--  Using mri_scan / mugshot_photo is registered through rps_lib
--  (CreateUseableItem → your framework), which ox_inventory calls on use.
--  mugshot_photo also shows the actual photo as its icon (metadata.imageurl).
-- ════════════════════════════════════════════════════════════════════════════

    ['mri_scan'] = {
        label = 'MRI Film',
        weight = 100,
        stack = false,
        close = true,
        description = 'MRI report from Pillbox Hill Medical Center',
        client = { image = 'mri_scan.png' },
    },

    ['mugshot_photo'] = {
        label = 'Mugshot Photo',
        weight = 50,
        stack = false,
        close = true,
        description = 'LSPD booking photo',
        client = { image = 'mugshot_photo.png' },
    },

    -- tech module (skip any you already have)
    ['bodycam'] = { label = 'Bodycam', weight = 100, stack = false, close = true, client = { image = 'bodycam.png' } },
    ['dash_cam'] = { label = 'Dashcam', weight = 100, stack = false, close = true, client = { image = 'dash_cam.png' } },
    ['drone'] = { label = 'Drone', weight = 1000, stack = false, close = true, client = { image = 'drone.png' } },
