if not Config.Modules.mugshot then return end

local C = Config.Mugshot
local Text = C.Text
local capturing = false
local lastShot = {}   -- [suspect identifier] = os.time()

-- ─── helpers ────────────────────────────────────────────────────────────────

local function hasAccess(source)
    local jobs = C.Jobs
    if not jobs or #jobs == 0 then jobs = Config.Lockers.DefaultJobs end

    local player = exports.rps_lib:GetPlayerData(source)
    local job = player and player.job
    if not job or not job.name then return false end

    local grade = job.grade and tonumber(job.grade.level) or 0
    for _, name in ipairs(jobs) do
        if name == job.name then return grade >= (C.MinGrade or 0) end
    end
    return false
end

local function distanceTo(source, coords)
    return #(GetEntityCoords(GetPlayerPed(source)) - coords)
end

local function playerName(source)
    local data = exports.rps_lib:GetPlayerData(source)
    return (data and data.name) or GetPlayerName(source)
end

--- The player standing at the mug cart (prefers one in MRPD's cart anim).
local function findSuspect()
    local fallback = nil
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if distanceTo(src, C.Cart.coords) <= C.Cart.radius then
            if Player(src).state.rpsMugshotReady then return src, true end
            fallback = fallback or src
        end
    end
    return fallback, false
end

local function webhookBase()
    -- strip any ?query (e.g. ?wait=true / ?thread_id=) from the convar
    return (GetConvar('rps_mugshot_webhook', ''):gsub('%?.*$', ''))
end

local function uploadSettings()
    local U = C.Upload
    if U.provider == 'discord' then
        local hook = webhookBase()
        if hook == '' then return nil end
        -- ?wait=true makes Discord return the message JSON (attachment URL + message id)
        return hook .. '?wait=true', {}, 'files[0]'
    end

    local token = GetConvar('rps_mugshot_token', '')
    if token == '' then return nil end
    return U.url, { ['Authorization'] = token }, 'file'
end

--- Returns imageUrl, discordMessageId (the latter only for the discord provider).
local function parseResponse(resp)
    if type(resp) == 'string' then
        local ok, decoded = pcall(json.decode, resp)
        resp = ok and decoded or nil
    end
    if type(resp) ~= 'table' then return nil end

    local url = (resp.data and resp.data.url)
        or resp.url
        or (resp.attachments and resp.attachments[1] and resp.attachments[1].url)
    return url, resp.id
end

local function logError(msg)
    print('^1[rps_prompt_exstras] mugshot:^7 ' .. msg)
end

--- Captures + uploads `target`'s screen.
--- Returns imageUrl, messageId — or nil, nil, reason (shown to the officer).
local function captureSuspect(target)
    local url, headers, formField = uploadSettings()
    if not url then
        local convar = C.Upload.provider == 'discord' and 'rps_mugshot_webhook' or 'rps_mugshot_token'
        logError(('convar "%s" is empty on THIS server — add  set %s "..."  to server.cfg and restart the SERVER (not just the resource)')
            :format(convar, convar))
        return nil, nil, Text.notConfigured
    end

    local p = promise.new()
    local settled = false
    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value)
    end

    local options = {
        encoding  = C.Upload.encoding,
        headers   = headers,
        formField = formField,
        maxWidth  = C.Upload.maxWidth,
        maxHeight = C.Upload.maxHeight,
    }
    -- screencapture adds an extra "filename" form field when this is set,
    -- which Discord's webhook endpoint doesn't expect — only send it to fivemanage.
    if C.Upload.provider ~= 'discord' then
        options.filename = ('mugshot_%d_%d'):format(target, os.time())
    end

    exports.screencapture:remoteUpload(target, url, options, function(response)
        local imageUrl, messageId = parseResponse(response)
        if not imageUrl then
            logError('upload answered without an image URL: ' .. tostring(type(response) == 'table' and json.encode(response) or response):sub(1, 500))
        end
        settle({ url = imageUrl, messageId = messageId })
    end, 'blob')

    -- screencapture never calls back when the upload itself fails (it only
    -- logs "Error uploading file: ... Status: ... Response: ...").
    SetTimeout(C.Upload.timeout, function() settle(false) end)

    local result = Citizen.Await(p)
    if result == false then
        logError(('no answer from screencapture within %d ms — look for "Error uploading file" from [screencapture] just above this line for the HTTP status / reason')
            :format(C.Upload.timeout))
        return nil, nil, Text.uploadError
    end
    if not result.url then return nil, nil, Text.uploadError end
    return result.url, result.messageId
end

local function sendDiscordLog(name, identifier, officer, imageUrl, messageId)
    local hook = webhookBase()
    if hook == '' then return end

    local details = ('**Mugshot:** %s\n**Identifier:** `%s`\n**Officer:** %s\n**Time:** <t:%d:f>')
        :format(name, identifier, officer, os.time())

    -- discord provider: the upload already IS the message (with the photo) —
    -- edit it to add the details instead of posting a second message.
    if C.Upload.provider == 'discord' then
        if messageId then
            PerformHttpRequest(('%s/messages/%s'):format(hook, messageId), function() end, 'PATCH',
                json.encode({ content = details }), { ['Content-Type'] = 'application/json' })
        end
        return
    end

    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        embeds = { {
            title = 'Mugshot: ' .. name,
            color = 3447003,
            image = { url = imageUrl },
            fields = {
                { name = 'Identifier', value = identifier, inline = true },
                { name = 'Officer', value = officer, inline = true },
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- ─── take a mugshot ─────────────────────────────────────────────────────────

exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:mugshot:take', function(source)
    if GetResourceState('screencapture') ~= 'started' then return { error = Text.noCapture } end
    if not hasAccess(source) then return { error = Text.noAccess } end
    if distanceTo(source, C.Station.coords) > C.Station.maxDistance then return { error = Text.tooFar } end
    if capturing then return { error = Text.busy } end

    local suspect, onCart = findSuspect()
    if not suspect then return { error = Text.noSuspect } end
    if C.RequireMugCart and not onCart then return { error = Text.notOnCart } end

    local identifier = exports.rps_lib:GetIdentifier(suspect) or ('player:' .. suspect)
    local now = os.time()
    if lastShot[identifier] and now - lastShot[identifier] < C.Cooldown then
        return { error = Text.cooldown }
    end

    capturing = true
    lastShot[identifier] = now

    -- suspect hides HUD (and uses our camera if MRPD's isn't active), then capture
    TriggerClientEvent('rps_prompt_exstras:mugshot:prepare', suspect, not onCart)
    Wait(C.CaptureWait)
    local imageUrl, messageId, reason = captureSuspect(suspect)
    TriggerClientEvent('rps_prompt_exstras:mugshot:finish', suspect, imageUrl ~= nil)

    capturing = false
    if not imageUrl then
        lastShot[identifier] = nil   -- a failed upload shouldn't start the cooldown
        return { error = reason or Text.failed }
    end

    local name = playerName(suspect)
    local officer = playerName(source)

    MySQL.insert('INSERT INTO rps_mugshots (identifier, name, officer, url) VALUES (?, ?, ?, ?)',
        { identifier, name, officer, imageUrl })
    sendDiscordLog(name, identifier, officer, imageUrl, messageId)

    if C.Item.enabled then
        exports.rps_lib:AddItem(source, C.Item.name, 1, {
            photo       = imageUrl,                 -- read when the item is used
            imageurl    = imageUrl,                 -- ox_inventory shows it as the item icon
            suspect     = name,
            description = ('%s — %s'):format(name, os.date('%Y-%m-%d %H:%M')),
        })
    end

    DebugPrint(('%s took a mugshot of %s: %s'):format(officer, name, imageUrl))
    return { ok = true, url = imageUrl, name = name }
end)

-- ─── mugshot photo item: using it shows the photo ───────────────────────────

if C.Item.enabled then
    -- safe at top level: rps_lib queues this until framework detection is done
    exports.rps_lib:CreateUseableItem(C.Item.name, function(source)
        local photos = {}
        for _, item in ipairs(exports.rps_lib:GetInventory(source) or {}) do
            local meta = item.metadata
            if item.name == C.Item.name and type(meta) == 'table' and type(meta.photo or meta.image) == 'string' then
                photos[#photos + 1] = {
                    url   = meta.photo or meta.image,
                    title = meta.suspect or Text.photoTitle,
                    desc  = meta.description or '',
                }
            end
        end
        if #photos == 0 then return exports.rps_lib:Notify(source, Text.photoBlank, 'error') end
        TriggerClientEvent('rps_prompt_exstras:mugshot:photos', source, photos)
    end)
end

-- ─── /mugshots list ─────────────────────────────────────────────────────────

exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:mugshot:list', function(source, targetId)
    if not hasAccess(source) then return { error = Text.noAccess } end

    local rows
    local target = tonumber(targetId)
    if target and GetPlayerName(target) then
        local identifier = exports.rps_lib:GetIdentifier(target)
        rows = MySQL.query.await('SELECT name, officer, url, created_at FROM rps_mugshots WHERE identifier = ? ORDER BY id DESC LIMIT ?',
            { identifier, C.ListLimit })
    else
        rows = MySQL.query.await('SELECT name, officer, url, created_at FROM rps_mugshots ORDER BY id DESC LIMIT ?',
            { C.ListLimit })
    end

    for _, row in ipairs(rows or {}) do
        -- oxmysql returns TIMESTAMP as ms since epoch
        if type(row.created_at) == 'number' then
            row.created_at = os.date('%Y-%m-%d %H:%M', math.floor(row.created_at / 1000))
        end
    end
    return { rows = rows or {} }
end)

-- ─── test: mugshot_test [serverId] ──────────────────────────────────────────
-- Server console (or an admin in-game) uploads a player's CURRENT screen with
-- the configured provider and prints the result — no cart / camera / job needed.
RegisterCommand('mugshot_test', function(source, args)
    if source ~= 0 and not exports.rps_lib:HasPermission(source, 'admin') then return end

    local target = tonumber(args[1]) or (source ~= 0 and source) or nil
    if not target or not GetPlayerName(target) then
        return print('usage: mugshot_test <serverId>')
    end
    if GetResourceState('screencapture') ~= 'started' then
        return logError('screencapture is not started')
    end

    print(('[rps_prompt_exstras] mugshot_test: provider=%s, webhook set=%s, token set=%s — capturing %s ...'):format(
        C.Upload.provider,
        tostring(GetConvar('rps_mugshot_webhook', '') ~= ''),
        tostring(GetConvar('rps_mugshot_token', '') ~= ''),
        GetPlayerName(target)))

    CreateThread(function()
        local imageUrl, _, reason = captureSuspect(target)
        if imageUrl then
            print('^2[rps_prompt_exstras] mugshot_test OK:^7 ' .. imageUrl)
        else
            logError('mugshot_test FAILED: ' .. tostring(reason))
        end
    end)
end, true)

-- ─── setup ──────────────────────────────────────────────────────────────────

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rps_mugshots` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(80) NOT NULL,
            `name` VARCHAR(100) NULL,
            `officer` VARCHAR(100) NULL,
            `url` VARCHAR(512) NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `identifier` (`identifier`)
        )
    ]])

    if GetResourceState('screencapture') ~= 'started' then
        print('^3[rps_prompt_exstras]^7 mugshot: screencapture is not started — install https://github.com/itschip/screencapture')
    end
end)
