--[[
    MUGSHOT
    1. The suspect uses MRPD's own mug cart (spot 'mugcart_1', open to everyone):
       MRPD plays the mugshot anim, shows their name on the plate and moves THEIR
       camera to the mugshot camera. This module notices that (IsPlayerAnimated).
    2. An officer uses the "Take Mugshot" target behind the camera.
    3. The server captures the SUSPECT's screen with screencapture (remoteUpload —
       the upload token never leaves the server), HUD hidden, and uploads it.
    4. The image URL is saved in the `rps_mugshots` table (auto-created), sent to
       an optional Discord log, and shown to the officer as a preview.
    /mugshots [serverId] lists saved mugshots (officers only).

    Requires: screencapture (https://github.com/itschip/screencapture), oxmysql, ox_lib.
]]

if not Config.Modules.mugshot then return end

Config.Mugshot = {}

-- Who may take / view mugshots. {} = Config.Lockers.DefaultJobs.
Config.Mugshot.Jobs = {}
Config.Mugshot.MinGrade = 0

-- MRPD mug cart (coords from prompt_mrpd_scripts config/anims.lua)
Config.Mugshot.Cart = {
    spotId     = 'mugcart_1',
    coords     = vec3(468.8115, -995.4656, 28.5347),
    radius     = 2.5,     -- suspect must be this close to the cart (server check)
    readyDelay = 2500,    -- ms after the cart anim starts before the camera has eased in
}

-- true  = the suspect MUST be in MRPD's mug-cart animation (MRPD camera + nameplate)
-- false = also allowed without it: a suspect standing at the cart gets this
--         module's own camera (same position as MRPD's) for the photo
Config.Mugshot.RequireMugCart = false

-- Camera used when the suspect is NOT on MRPD's cart (MRPD's camera position)
Config.Mugshot.Camera = {
    pos = vec3(466.873, -993.379, 29.427),
    fov = 40.0,
    -- aims at the head bone, lowered a bit to frame head + shoulders
    aimOffset = vec3(0.0, 0.0, -0.1),
}

-- Officer's "Take Mugshot" target (behind the camera)
Config.Mugshot.Station = {
    coords   = vec3(466.873, -993.379, 29.0),
    size     = vec3(1.2, 1.2, 2.0),
    heading  = 270.0,
    label    = 'Take Mugshot',
    icon     = 'fas fa-camera',
    distance = 2.0,
    maxDistance = 4.0,   -- server check
}

-- Upload target. The WEBHOOK / TOKEN go in server.cfg convars — NEVER in this
-- file (shared config is downloaded by every client):
--   set rps_mugshot_webhook "https://discord.com/api/webhooks/..."
--   set rps_mugshot_token   "your-fivemanage-api-key"        (fivemanage only)
-- provider:
--   'discord'    = the photo is posted straight to rps_mugshot_webhook, then the
--                  message gets the suspect / officer / time added. Discord image
--                  links expire after ~24h, so old previews in /mugshots stop loading.
--   'fivemanage' = permanent image URLs; rps_mugshot_webhook (optional) gets an embed log.
Config.Mugshot.Upload = {
    provider  = 'discord',
    url       = 'https://api.fivemanage.com/api/v3/file',   -- fivemanage only
    encoding  = 'jpg',
    maxWidth  = 1920,
    maxHeight = 1080,
    timeout   = 20000,   -- ms
}

Config.Mugshot.HideHudMs   = 2500   -- suspect's HUD/radar hidden around the capture
Config.Mugshot.CaptureWait = 600    -- ms between "prepare" and the capture (cam settle)
Config.Mugshot.Cooldown    = 10     -- seconds between mugshots of the same suspect

-- Optional: give the officer a photo item with the image in its metadata.
-- Using it shows the photo. Add it to your inventory first: see setup/items/.
Config.Mugshot.Item = { enabled = true, name = 'mugshot_photo' }

Config.Mugshot.ListLimit = 15       -- /mugshots shows this many

-- /mugcam = take the mugshot from the camera spot (same as the target option).
-- Officer must still be within Station.maxDistance of the camera. false = off.
Config.Mugshot.Command = 'mugcam'

Config.Mugshot.Text = {
    noAccess     = 'You are not allowed to take mugshots.',
    noSuspect    = 'Nobody is standing at the mugshot cart.',
    notOnCart    = 'The suspect has to use the mugshot cart first.',
    busy         = 'A mugshot is already being taken.',
    cooldown     = 'Wait a moment before taking another mugshot.',
    noCapture    = 'screencapture is not running — mugshots are disabled.',
    failed       = 'The mugshot could not be uploaded.',
    notConfigured = 'Mugshot upload is not configured on this server (rps_mugshot_webhook missing) — tell an admin.',
    uploadError  = 'The mugshot upload was rejected — an admin can see why in the server console.',
    tooFar       = 'You are too far from the camera.',
    taken        = 'Mugshot saved for %s.',
    suspectTaken = 'Your mugshot was taken.',
    noneFound    = 'No mugshots found.',
    listTitle    = 'Mugshots',
    photoTitle   = 'Mugshot',
    photoBlank   = 'This photo is blank.',
}
