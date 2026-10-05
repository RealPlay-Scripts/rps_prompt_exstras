--[[
    MRI  (Prompt's Pillbox Hill Medical Center — prompt_pillbox_hospital)
    Pillbox runs the MRI itself (bed, slide, scan light, progress). This module
    turns a FINISHED scan into an MRI report:
      - the patient's client is probed (health, armour, last damaged body part,
        what damaged it) and turned into findings (texts below)
      - the operator gets the report on screen (+ optional film item)
      - the report is saved (rps_mri_scans, auto-created) and can go to Discord
      - /mriscans [serverId] lists past reports (medical staff)

    Triggered by Pillbox's `controls.onScanComplete` hook (exact operator +
    patient — see setup/prompt_pillbox_hospital/hooks/hooks_server.lua) and,
    as a fallback, by watching exports.prompt_pillbox_hospital:GetMriState().
]]

if not Config.Modules.mri then return end

Config.MRI = {}

Config.MRI.Resource = 'prompt_pillbox_hospital'

-- Who counts as medical staff for reports / /mriscans.
-- 'pillbox' = use Pillbox's own IsMedic() (its Config.access); otherwise a job list.
Config.MRI.Staff = 'pillbox'
Config.MRI.Jobs = { 'ambulance', 'ems', 'doctor' }   -- used when Staff ~= 'pillbox'
Config.MRI.MinGrade = 0

-- Fallback watcher (when the hook isn't installed): poll GetMriState().
Config.MRI.Watch = { enabled = true, interval = 500 }
-- Fallback only: the operator is the nearest staff member within this range of the patient.
Config.MRI.OperatorRadius = 15.0

-- Discord log: set rps_mri_webhook "https://discord.com/api/webhooks/..." in server.cfg
-- image = the operator's screen renders the full report sheet and it is posted
-- as a JPEG inside the embed. Text-only embed if it doesn't arrive in time.
Config.MRI.Discord = { image = true, imageTimeout = 25000 }

-- Film item for the operator; using it reopens the report sheet.
-- Add it to your inventory first: see setup/items/.
Config.MRI.Item = { enabled = true, name = 'mri_scan' }

Config.MRI.ListLimit = 15

-- ─── Report texts ────────────────────────────────────────────────────────────
-- Body part from the ped's last damaged bone.
Config.MRI.Regions = {
    head  = { label = 'head',      bones = { 31086, 39317, 12844, 65068 } },
    torso = { label = 'chest',     bones = { 24816, 24817, 24818, 10706, 64729, 23553 } },
    abdomen = { label = 'abdomen', bones = { 57597, 11816, 0 } },
    larm  = { label = 'left arm',  bones = { 45509, 61163, 18905, 26610 } },
    rarm  = { label = 'right arm', bones = { 40269, 28252, 57005, 58866 } },
    lleg  = { label = 'left leg',  bones = { 58271, 63931, 14201, 2108 } },
    rleg  = { label = 'right leg', bones = { 51826, 36864, 52301, 20781 } },
}

-- What caused the damage → finding (%s = body part).
Config.MRI.Causes = {
    gunshot   = 'Metallic foreign body (projectile fragment) lodged in the %s.',
    melee     = 'Soft-tissue contusion and haematoma in the %s, consistent with blunt force.',
    fall      = 'Hairline fracture in the %s consistent with a fall.',
    vehicle   = 'Compression injury to the %s consistent with a vehicle impact.',
    explosion = 'Blast trauma with multiple small fragments around the %s.',
    fire      = 'Thermal damage to tissue around the %s.',
    unknown   = 'Localised trauma in the %s, cause undetermined.',
}

-- Overall condition by health % (first match from the top).
-- advice = last line of the report's Conclusion.
Config.MRI.Severity = {
    { min = 90, label = 'Normal',   impression = 'No significant abnormalities detected.',
      advice = 'No follow-up imaging required.' },
    { min = 60, label = 'Mild',     impression = 'Minor injuries. Outpatient treatment advised.',
      advice = 'Clinical correlation recommended. Re-assess if symptoms persist or worsen.' },
    { min = 30, label = 'Moderate', impression = 'Significant trauma. Admission and observation advised.',
      advice = 'Admit for observation. Repeat imaging in 24 hours.' },
    { min = 1,  label = 'Severe',   impression = 'Critical trauma. Immediate surgical intervention required.',
      advice = 'Urgent surgical consult. Prepare theatre.' },
    { min = 0,  label = 'Critical', impression = 'Patient unresponsive. Resuscitation required.',
      advice = 'Immediate resuscitation. Repeat imaging once the patient is stable.' },
}

-- ─── Report sheet (header + texts) ───────────────────────────────────────────
Config.MRI.Report = {
    hospital   = 'PILLBOX HILL',
    subtitle   = 'MEDICAL CENTER',
    department = 'Emergency & Radiology Department',
    idPrefix   = 'PHMC',
    studyType  = 'MRI SERIES',
    deptLabel  = 'Radiology',
    signatureTitle = 'Radiology Operator',
}

-- Header "Indication" line per cause (%s = body part). `none` = no injury found.
Config.MRI.Indications = {
    gunshot   = 'Gunshot wound (%s)',
    melee     = 'Blunt force trauma (%s)',
    fall      = 'Fall injury (%s)',
    vehicle   = 'Motor vehicle accident (%s)',
    explosion = 'Blast injury (%s)',
    fire      = 'Burn injury (%s)',
    unknown   = 'Trauma (%s)',
    none      = 'Routine examination',
}

-- Extra "Findings" bullets per cause, after the main finding (%s = body part).
Config.MRI.ExtraFindings = {
    gunshot   = { 'Susceptibility artefact surrounding the metallic fragment.',
                  'Surrounding oedema within the %s soft tissues.',
                  'No secondary projectile tract identified.' },
    melee     = { 'Increased T2 signal in the %s soft tissues (oedema).',
                  'No acute fracture or dislocation identified.' },
    fall      = { 'Bone marrow oedema adjacent to the fracture line.',
                  'Joint alignment of the %s is maintained.' },
    vehicle   = { 'Bone marrow oedema with cortical disruption.',
                  'Diffuse soft-tissue oedema in the %s.' },
    explosion = { 'Multiple punctate susceptibility artefacts (fragments).',
                  'Diffuse soft-tissue oedema in the %s.' },
    fire      = { 'Subcutaneous oedema and skin thickening over the %s.',
                  'Deeper structures appear preserved.' },
    unknown   = { 'Abnormal signal intensity in the %s.' },
    none      = { 'Normal signal intensity throughout the study.',
                  'No acute fracture or dislocation identified.',
                  'Soft tissues are unremarkable.' },
}

Config.MRI.Text = {
    reportTitle = 'MRI Report — %s',
    patientDone = 'Your MRI scan is complete.',
    noAccess    = 'Only medical staff can view MRI reports.',
    noneFound   = 'No MRI reports found.',
    listTitle   = 'MRI Reports',
    noFindings  = 'No localised injuries found.',
    armour      = 'Ballistic vest detected (%d%% integrity) — removed for imaging.',
    filmBlank   = 'This MRI film is blank.',
    filmMissing = 'This MRI report no longer exists.',
    pickFilm    = 'MRI Films',
}
