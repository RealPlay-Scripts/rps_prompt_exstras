-- ════════════════════════════════════════════════════════════════════════════
--  rps_prompt_exstras items — ESX `items` table
--  Only needed if your ESX inventory reads items from the database
--  (ox_inventory does NOT — use ox_inventory.lua instead).
--  Safe to run twice: existing rows only get their label updated.
-- ════════════════════════════════════════════════════════════════════════════

INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('mri_scan',      'MRI Film',      1, 0, 1),
    ('mugshot_photo', 'Mugshot Photo', 1, 0, 1),
    ('bodycam',       'Bodycam',       1, 0, 1),
    ('dash_cam',      'Dashcam',       1, 0, 1),
    ('drone',         'Drone',         1, 0, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
