--[[
    Locker animation, done the same way prompt_mrpd_scripts does it:
      1. find the static MLO prop near the configured coords
      2. hide it (CreateModelHide) and spawn its local, animatable "_anim" twin
      3. walk the ped to the stand point (twin + offset) and freeze-pin it
      4. play  open → loop  (prop + ped clips together)
      5. ...inventory is open...
      6. play  close, then restore everything

    If the twin model or the prompt@mrpd anim dicts are not streamed (or the
    location has no `anim` data), it falls back to a base-game loop.
]]

if not LockerEngineEnabled() then return end

LockerAnim = {}

local A = Config.Lockers.Animation
local HIDE_RADIUS = 0.2

local function rotate(heading, off)
    local r = math.rad(heading)
    local c, s = math.cos(r), math.sin(r)
    return vector3(off.x * c - off.y * s, off.x * s + off.y * c, off.z)
end

local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

local function loadModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(10)
    end
    return hash
end

-- Loads every dict the MRPD anim data references. Returns the list or nil.
local function loadMrpdDicts(anim)
    local dicts, seen = {}, {}
    for _, key in ipairs({ 'open', 'loop', 'close' }) do
        local phase = anim[key]
        if phase then
            for _, part in ipairs({ phase.ped, phase.prop }) do
                if part and not seen[part.dict] then
                    seen[part.dict] = true
                    if not loadDict(part.dict) then return nil end
                    dicts[#dicts + 1] = part.dict
                end
            end
        end
    end
    return dicts
end

local function walkTo(ped, pos, heading)
    TaskGoStraightToCoord(ped, pos.x, pos.y, pos.z, 1.0, A.WalkTimeout, heading, 0.1)
    local timeout = GetGameTimer() + A.WalkTimeout
    while #(GetEntityCoords(ped).xy - pos.xy) > 0.3 and GetGameTimer() < timeout do
        Wait(50)
    end
end

local function playPhase(session, key, loop)
    local phase = session.anim and session.anim[key]
    if not phase or not phase.ped then return end

    local ped = session.ped
    TaskPlayAnim(ped, phase.ped.dict, phase.ped.name, A.BlendSpeed, A.BlendSpeed, -1, loop and 1 or 2, 0.0, false, false, false)

    if session.twin and phase.prop then
        PlayEntityAnim(session.twin, phase.prop.name, phase.prop.dict, 1000.0, loop, true, false, 0.0, 0)
    end

    if not loop then
        Wait(math.floor(GetAnimDuration(phase.ped.dict, phase.ped.name) * 1000))
    end
end

--- Walks to the locker and plays open → loop. Returns a session for End().
function LockerAnim.Begin(loc)
    local ped = PlayerPedId()
    local session = { ped = ped, dicts = {} }

    -- 1. static prop (fall back to the configured coords if it isn't found)
    local base, heading = loc.coords.xyz, loc.coords.w
    local staticHash = loc.model and joaat(loc.model)
    if staticHash then
        local obj = GetClosestObjectOfType(base.x, base.y, base.z, A.PropSearchRadius, staticHash, false, false, false)
        if obj ~= 0 then
            base, heading = GetEntityCoords(obj), GetEntityHeading(obj)
        end
    end

    -- twin placement + ped stand point (same maths as MRPD's offset/rotation)
    local anim = loc.anim
    local twinHeading = heading + (anim and anim.animHeadingOffset or 0.0)
    local twinPos = base
    if anim and anim.animOffset then
        twinPos = anim.animOffsetLocal and (base + rotate(heading, anim.animOffset)) or (base + anim.animOffset)
    end

    local offset = loc.offset or vec3(0.0, -0.8, 1.0)
    local pinPos = twinPos + rotate(twinHeading, offset)
    local pinHeading = twinHeading + (loc.rotation and loc.rotation.z or 0.0)

    -- 2. are the MRPD assets available?
    local twinHash = anim and anim.loop and loadModel(anim.animModel)
    local dicts = twinHash and loadMrpdDicts(anim)

    if twinHash and dicts then
        session.anim, session.dicts = anim, dicts

        -- 3. walk + pin
        walkTo(ped, pinPos, pinHeading)
        ClearPedTasks(ped)
        SetEntityCoordsNoOffset(ped, pinPos.x, pinPos.y, pinPos.z, false, false, false)
        SetEntityHeading(ped, pinHeading)
        FreezeEntityPosition(ped, true)

        -- swap the static prop for the animatable twin
        if staticHash then
            CreateModelHide(base.x, base.y, base.z, HIDE_RADIUS, staticHash, true)
            session.hide = { pos = base, hash = staticHash }
        end
        local twin = CreateObjectNoOffset(twinHash, twinPos.x, twinPos.y, twinPos.z, false, false, false)
        SetEntityHeading(twin, twinHeading)
        FreezeEntityPosition(twin, true)
        SetEntityCollision(twin, false, false)
        SetModelAsNoLongerNeeded(twinHash)
        session.twin = twin

        -- 4. open → loop
        playPhase(session, 'open', false)
        playPhase(session, 'loop', true)
    else
        DebugPrint(('locker %s: MRPD anim assets unavailable, using fallback'):format(loc.id))
        if twinHash then SetModelAsNoLongerNeeded(twinHash) end

        walkTo(ped, pinPos, pinHeading)
        SetEntityHeading(ped, pinHeading)

        local fb = A.Fallback
        if fb and loadDict(fb.dict) then
            session.dicts = { fb.dict }
            TaskPlayAnim(ped, fb.dict, fb.clip, A.BlendSpeed, A.BlendSpeed, -1, 1, 0.0, false, false, false)
        end
    end

    return session
end

--- Restores the world. instant = skip the close clip (death / resource stop).
function LockerAnim.End(session, instant)
    if not session then return end
    local ped = session.ped

    if not instant and session.anim and not IsEntityDead(ped) then
        playPhase(session, 'close', false)
    end

    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)

    if session.twin and DoesEntityExist(session.twin) then
        DeleteEntity(session.twin)
    end
    if session.hide then
        local p = session.hide.pos
        RemoveModelHide(p.x, p.y, p.z, HIDE_RADIUS, session.hide.hash, false)
    end
    for _, dict in ipairs(session.dicts) do
        RemoveAnimDict(dict)
    end
end
