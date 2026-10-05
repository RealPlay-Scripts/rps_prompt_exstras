if not Config.Modules.mri then return end

local M = Config.MRI
local Text = M.Text
local RES = M.Resource
local recent = {}   -- [patient] = GetGameTimer() of the last report (hook + watcher dedupe)

-- ─── helpers ────────────────────────────────────────────────────────────────

local function pillboxRunning()
    return GetResourceState(RES) == 'started'
end

local function isStaff(source)
    if M.Staff == 'pillbox' and pillboxRunning() then
        return exports[RES]:IsMedic(source) == true
    end

    local player = exports.rps_lib:GetPlayerData(source)
    local job = player and player.job
    if not job or not job.name then return false end
    local grade = job.grade and tonumber(job.grade.level) or 0
    for _, name in ipairs(M.Jobs) do
        if name == job.name then return grade >= (M.MinGrade or 0) end
    end
    return false
end

local function playerName(source)
    local data = exports.rps_lib:GetPlayerData(source)
    return (data and data.name) or GetPlayerName(source) or ('#' .. tostring(source))
end

--- Asks the patient's client for its body state (nil after 5 s).
local function probePatient(patient)
    local p = promise.new()
    local done = false
    exports.rps_lib:TriggerClientCallback(patient, 'rps_prompt_exstras:mri:probe', function(result)
        if done then return end
        done = true
        p:resolve(result)
    end)
    SetTimeout(5000, function()
        if done then return end
        done = true
        p:resolve(nil)
    end)
    return Citizen.Await(p)
end

local function severityFor(pct)
    for _, s in ipairs(M.Severity) do
        if pct >= s.min then return s end
    end
    return M.Severity[#M.Severity]
end

--- Character date of birth from whichever framework runs (nil if unknown).
local function getDob(source)
    local ok, dob = pcall(function()
        if GetResourceState('qbx_core') == 'started' then
            local p = exports.qbx_core:GetPlayer(source)
            return p and p.PlayerData.charinfo and p.PlayerData.charinfo.birthdate
        elseif GetResourceState('qb-core') == 'started' then
            local p = exports['qb-core']:GetCoreObject().Functions.GetPlayer(source)
            return p and p.PlayerData.charinfo and p.PlayerData.charinfo.birthdate
        elseif GetResourceState('es_extended') == 'started' then
            local x = exports.es_extended:getSharedObject().GetPlayerFromId(source)
            return x and (x.get('dateofbirth') or x.get('dob'))
        end
    end)
    return ok and dob or nil
end

--- 'YYYY-MM-DD' or 'DD/MM/YYYY' → normalised 'YYYY-MM-DD', age
local function parseDob(dob)
    if type(dob) ~= 'string' then return nil end
    local y, m, d = dob:match('^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)')
    if not y then d, m, y = dob:match('^(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)') end
    if not y then return dob, nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    local now = os.date('*t')
    local age = now.year - y - (((now.month < m) or (now.month == m and now.day < d)) and 1 or 0)
    return ('%04d-%02d-%02d'):format(y, m, d), age
end

--- Stable per-character patient number, e.g. PHMC-482913
local function patientId(identifier)
    local h = 0
    for i = 1, #identifier do h = (h * 31 + identifier:byte(i)) % 1000000 end
    return ('%s-%06d'):format(M.Report.idPrefix, h)
end

local function fmtList(list, regionLabel)
    local out = {}
    for _, line in ipairs(list or {}) do
        out[#out + 1] = line:find('%%s') and line:format(regionLabel or '') or line
    end
    return out
end

local function buildReport(patient, operator, probe, identifier)
    local name = playerName(patient)
    local pct = probe.healthPct or 100
    local severity = severityFor(pct)

    local injured = probe.region and M.Regions[probe.region] and pct < 100
    local region = injured and probe.region or nil
    local regionLabel = injured and M.Regions[probe.region].label or nil
    local cause = injured and (probe.cause or 'unknown') or nil

    -- Findings: main finding + per-cause extras (or the normal set)
    local findings = {}
    if injured then
        findings[1] = (M.Causes[cause] or M.Causes.unknown):format(regionLabel)
    end
    for _, line in ipairs(fmtList(M.ExtraFindings[cause or 'none'], regionLabel)) do
        findings[#findings + 1] = line
    end

    -- Additional observations
    local observations = {}
    if (probe.armour or 0) > 0 then observations[#observations + 1] = Text.armour:format(probe.armour) end
    observations[#observations + 1] = ('Overall condition graded %s (%d%% vital capacity).'):format(severity.label:lower(), pct)
    if injured then
        observations[#observations + 1] = 'No other acute abnormality identified elsewhere in the study.'
    end

    -- Conclusion
    local conclusion = {}
    if injured then conclusion[1] = findings[1] else conclusion[1] = Text.noFindings end
    conclusion[#conclusion + 1] = severity.impression
    conclusion[#conclusion + 1] = severity.advice

    local dob, age = parseDob(getDob(patient))
    local operatorName = operator and GetPlayerName(operator) and playerName(operator) or nil
    local R = M.Report

    return {
        name = name,
        severity = severity.label,
        findings = findings,
        -- everything the NUI report sheet (web/mri.*) is drawn from
        scan = {
            hospital = R.hospital, subtitle = R.subtitle, department = R.department,
            studyType = R.studyType, deptLabel = R.deptLabel, signatureTitle = R.signatureTitle,

            name        = name,
            dob         = dob,
            age         = age,
            date        = os.date('%Y-%m-%d %H:%M'),
            patientId   = patientId(identifier),
            accession   = ('%s-MRI-%s'):format(R.idPrefix, os.date('%y%m%d-%H%M%S')),
            indication  = (M.Indications[cause or 'none'] or M.Indications.none):format(regionLabel or ''),
            operator    = operatorName,

            severity    = severity.label,
            impression  = severity.impression,
            health      = pct,
            armour      = probe.armour or 0,
            region      = region,
            regionLabel = regionLabel,
            cause       = cause,

            findings     = findings,
            observations = observations,
            conclusion   = conclusion,
        },
    }
end

-- ─── Discord ────────────────────────────────────────────────────────────────

local function webhook()
    return GetConvar('rps_mri_webhook', '')
end

local function reportEmbed(report, identifier, operatorName, withImage)
    return {
        title = 'MRI Report: ' .. report.name,
        description = '• ' .. table.concat(report.findings, '\n• '),
        color = 15158332,
        fields = {
            { name = 'Indication', value = report.scan.indication, inline = true },
            { name = 'Condition', value = report.severity, inline = true },
            { name = 'Operator', value = operatorName or '—', inline = true },
            { name = 'Conclusion', value = table.concat(report.scan.conclusion, '\n'), inline = false },
            { name = 'Patient ID', value = report.scan.patientId, inline = true },
            { name = 'Accession', value = report.scan.accession, inline = true },
            { name = 'Identifier', value = identifier, inline = false },
        },
        image = withImage and { url = 'attachment://mri_report.jpg' } or nil,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
end

local function sendDiscordText(report, identifier, operatorName)
    if webhook() == '' then return end
    PerformHttpRequest(webhook(), function() end, 'POST',
        json.encode({ embeds = { reportEmbed(report, identifier, operatorName, false) } }),
        { ['Content-Type'] = 'application/json' })
end

-- base64 → binary (Lua 5.4 bit ops; fast enough for a ~400 KB JPEG)
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_LOOKUP = {}
for i = 1, #B64 do B64_LOOKUP[B64:byte(i)] = i - 1 end

local function base64Decode(s)
    s = s:gsub('[^%w%+/=]', '')
    local out, n = {}, 0
    for i = 1, #s, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local v = ((B64_LOOKUP[a] or 0) << 18) | ((B64_LOOKUP[b] or 0) << 12)
                | ((B64_LOOKUP[c] or 0) << 6) | (B64_LOOKUP[d] or 0)
        n = n + 1
        if c == 61 or c == nil then
            out[n] = string.char((v >> 16) & 255)
        elseif d == 61 or d == nil then
            out[n] = string.char((v >> 16) & 255, (v >> 8) & 255)
        else
            out[n] = string.char((v >> 16) & 255, (v >> 8) & 255, v & 255)
        end
    end
    return table.concat(out)
end

--- Embed + the report sheet as an attached JPEG, in one webhook message.
local function sendDiscordImage(report, identifier, operatorName, jpeg)
    local boundary = ('----rpsMRI%d%d'):format(os.time(), math.random(100000, 999999))
    local payload = json.encode({
        embeds = { reportEmbed(report, identifier, operatorName, true) },
        attachments = { { id = 0, filename = 'mri_report.jpg' } },
    })
    local body = table.concat({
        '--', boundary, '\r\n',
        'Content-Disposition: form-data; name="payload_json"\r\n',
        'Content-Type: application/json\r\n\r\n',
        payload, '\r\n',
        '--', boundary, '\r\n',
        'Content-Disposition: form-data; name="files[0]"; filename="mri_report.jpg"\r\n',
        'Content-Type: image/jpeg\r\n\r\n',
        jpeg, '\r\n',
        '--', boundary, '--\r\n',
    })

    PerformHttpRequest(webhook(), function(status, response)
        if status < 200 or status >= 300 then
            print(('^3[rps_prompt_exstras]^7 MRI: Discord rejected the report image (HTTP %s): %s — sent the text report instead')
                :format(tostring(status), tostring(response):sub(1, 300)))
            sendDiscordText(report, identifier, operatorName)
        end
    end, 'POST', body, { ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary })
end

-- One-time tokens: the operator's NUI renders the sheet and sends it back as
-- a JPEG. Only a client that was handed a token can upload, once, in time.
local pendingImages = {}   -- [token] = { operator, report, identifier, operatorName }
local MAX_IMAGE_B64 = 4 * 1024 * 1024

RegisterNetEvent('rps_prompt_exstras:mri:image', function(token, b64)
    local src = source
    local job = pendingImages[token]
    if not job or job.operator ~= src or type(b64) ~= 'string' or #b64 > MAX_IMAGE_B64 then return end
    pendingImages[token] = nil

    local jpeg = base64Decode(b64)
    if #jpeg < 1000 or jpeg:sub(1, 2) ~= '\255\216' then   -- JPEG magic FF D8
        return sendDiscordText(job.report, job.identifier, job.operatorName)
    end
    sendDiscordImage(job.report, job.identifier, job.operatorName, jpeg)
end)

--- Discord log for a finished scan: with the rendered sheet when the operator
--- is online to render it (fallback text after M.Discord.imageTimeout).
local function sendDiscord(report, identifier, operatorName, operator)
    if webhook() == '' then return end
    if not (M.Discord.image and operator and GetPlayerName(operator)) then
        return sendDiscordText(report, identifier, operatorName)
    end

    local token = ('%x%x%x'):format(os.time(), math.random(0, 0xFFFFFF), math.random(0, 0xFFFFFF))
    pendingImages[token] = { operator = operator, report = report, identifier = identifier, operatorName = operatorName }
    report.uploadToken = token

    SetTimeout(M.Discord.imageTimeout, function()
        if pendingImages[token] then
            pendingImages[token] = nil
            sendDiscordText(report, identifier, operatorName)
        end
    end)
end

-- ─── a scan finished ────────────────────────────────────────────────────────

local function handleScanComplete(operator, patient)
    patient = tonumber(patient)
    operator = tonumber(operator)
    if not patient or not GetPlayerName(patient) then return end

    local now = GetGameTimer()
    if recent[patient] and now - recent[patient] < 10000 then return end   -- hook + watcher
    recent[patient] = now

    local probe = probePatient(patient)
    if not probe then
        print(('^3[rps_prompt_exstras]^7 MRI: no answer from patient %s'):format(patient))
        return
    end

    local identifier = exports.rps_lib:GetIdentifier(patient) or ('player:' .. patient)
    local report = buildReport(patient, operator, probe, identifier)
    local operatorName = report.scan.operator

    -- `findings` holds the full scan JSON so /mriscans + the film item can redraw
    -- the sheet later; `report` keeps a plain-text copy for anyone reading the DB.
    local scanId = MySQL.insert.await('INSERT INTO rps_mri_scans (identifier, name, operator, severity, findings, report) VALUES (?, ?, ?, ?, ?, ?)',
        { identifier, report.name, operatorName, report.severity, json.encode(report.scan),
          table.concat(report.scan.conclusion, '\n') })

    -- sets report.uploadToken when the operator should render + upload the sheet
    sendDiscord(report, identifier, operatorName, operator)

    if operator and GetPlayerName(operator) then
        TriggerClientEvent('rps_prompt_exstras:mri:report', operator, report)

        if M.Item.enabled and scanId then
            exports.rps_lib:AddItem(operator, M.Item.name, 1, {
                mriId       = scanId,
                patient     = report.name,
                description = ('%s — %s · %s'):format(report.name, report.severity, os.date('%Y-%m-%d')),
            })
        end
    end
    TriggerClientEvent('rps_prompt_exstras:mri:patientDone', patient)

    DebugPrint(('MRI report for %s by %s: %s'):format(report.name, operatorName or '?', report.severity))
end

--- Called from prompt_pillbox_hospital's hooks_server.lua (controls.onScanComplete).
exports('MriScanComplete', function(operator, patient)
    CreateThread(function() handleScanComplete(operator, patient) end)
end)

-- ─── fallback: watch GetMriState() ──────────────────────────────────────────

local function nearestStaff(patient)
    local origin = GetEntityCoords(GetPlayerPed(patient))
    local best, bestDist = nil, M.OperatorRadius
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src ~= patient then
            local dist = #(GetEntityCoords(GetPlayerPed(src)) - origin)
            if dist < bestDist and isStaff(src) then best, bestDist = src, dist end
        end
    end
    return best
end

CreateThread(function()
    if not M.Watch.enabled then return end
    while GetResourceState(RES) == 'starting' do Wait(100) end

    local wasScanning, lastPatient = false, nil
    while true do
        Wait(M.Watch.interval)
        if pillboxRunning() then
            local ok, state = pcall(function() return exports[RES]:GetMriState() end)
            state = ok and state or nil
            local scanning = state and state.scanning == true
            local patient = state and tonumber(state.patient)

            -- scanning → not scanning with the same patient still on the bed = scan completed
            if wasScanning and not scanning and patient and patient == lastPatient then
                local operator = nearestStaff(patient)
                CreateThread(function() handleScanComplete(operator, patient) end)
            end
            wasScanning, lastPatient = scanning, patient
        end
    end
end)

-- ─── /mriscans list ─────────────────────────────────────────────────────────

exports.rps_lib:RegisterServerCallback('rps_prompt_exstras:mri:list', function(source, targetId)
    if not isStaff(source) then return { error = Text.noAccess } end

    local rows
    local target = tonumber(targetId)
    if target and GetPlayerName(target) then
        rows = MySQL.query.await('SELECT name, operator, severity, findings, created_at FROM rps_mri_scans WHERE identifier = ? ORDER BY id DESC LIMIT ?',
            { exports.rps_lib:GetIdentifier(target), M.ListLimit })
    else
        rows = MySQL.query.await('SELECT name, operator, severity, findings, created_at FROM rps_mri_scans ORDER BY id DESC LIMIT ?',
            { M.ListLimit })
    end

    for _, row in ipairs(rows or {}) do
        if type(row.created_at) == 'number' then
            row.created_at = os.date('%Y-%m-%d %H:%M', math.floor(row.created_at / 1000))
        end
        local ok, scan = pcall(json.decode, row.findings or '')
        row.scan = (ok and type(scan) == 'table' and scan.severity) and scan
            or { name = row.name, severity = row.severity, operator = row.operator, date = row.created_at, findings = {} }
        row.findings = nil
    end
    return { rows = rows or {} }
end)

-- ─── MRI film item: using it reopens the report sheet ───────────────────────

--- The player's films (inventory metadata carries the report id).
local function filmsOf(source)
    local films = {}
    for _, item in ipairs(exports.rps_lib:GetInventory(source) or {}) do
        local meta = item.metadata
        if item.name == M.Item.name and type(meta) == 'table' and tonumber(meta.mriId) then
            films[#films + 1] = { id = tonumber(meta.mriId), label = meta.description or meta.patient or ('#' .. meta.mriId) }
        end
    end
    return films
end

local function openFilm(source, scanId)
    local row = MySQL.single.await('SELECT findings FROM rps_mri_scans WHERE id = ?', { scanId })
    local ok, scan = pcall(json.decode, row and row.findings or '')
    if not ok or type(scan) ~= 'table' then
        return exports.rps_lib:Notify(source, Text.filmMissing, 'error')
    end
    TriggerClientEvent('rps_prompt_exstras:mri:show', source, scan)
end

if M.Item.enabled then
    -- safe at top level: rps_lib queues this until framework detection is done
    exports.rps_lib:CreateUseableItem(M.Item.name, function(source)
        CreateThread(function()   -- MySQL.*.await needs a coroutine
            local films = filmsOf(source)
            if #films == 0 then return exports.rps_lib:Notify(source, Text.filmBlank, 'error') end
            if #films == 1 then return openFilm(source, films[1].id) end
            TriggerClientEvent('rps_prompt_exstras:mri:pickFilm', source, films)
        end)
    end)
end

-- chosen from the pick list — only films the player actually carries
RegisterNetEvent('rps_prompt_exstras:mri:openFilm', function(scanId)
    local src = source
    scanId = tonumber(scanId)
    for _, film in ipairs(filmsOf(src)) do
        if film.id == scanId then
            return CreateThread(function() openFilm(src, scanId) end)
        end
    end
end)

-- ─── setup ──────────────────────────────────────────────────────────────────

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rps_mri_scans` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(80) NOT NULL,
            `name` VARCHAR(100) NULL,
            `operator` VARCHAR(100) NULL,
            `severity` VARCHAR(30) NULL,
            `findings` TEXT NULL,
            `report` TEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `identifier` (`identifier`)
        )
    ]])

    if not pillboxRunning() then
        print(('^3[rps_prompt_exstras]^7 MRI: %s is not started — MRI reports are idle'):format(RES))
    end
end)
