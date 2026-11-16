local config, cache = ForgeSiren.config, pr_lib.cache
local resource, kvpKey = GetCurrentResourceName(), 'forge_siren:controller:v1'
local preferences, presets = ForgeSiren.preferences(), {}
local layout, layoutEditing = nil, false
local activeVehicle, activeSeat, selectedMode, manualHold, hornHold
local accessToken, registered = 0, false
local focused, paused, lastPayload, notice = false, false, nil, ''
local tracked, pendingBags, bindings, accessModels = {}, {}, {}, {}
local staticUI, publish, reconcile, publishScheduled
local adminUI, adminGeneration, loadAdmin = { allowed = false }, 0, nil
local controls = { 80, 81, 82, 83, 84, 85, 86, 172 }
-- Share driving keys with the game, but keep cursor movement/clicks out of
-- camera look, drive-by attacks and mouse steering (including aircraft).
local cursorControls = { 1, 2, 24, 25, 68, 69, 70, 91, 92, 99, 106, 114, 115, 122, 135, 200, 257 }
local pauseControls, pauseGuardUntil = { 199, 200 }, 0
local function blockPauseMenu()
    for group = 0, 2 do
        for index = 1, #pauseControls do DisableControlAction(group, pauseControls[index], true) end
    end
    SetPauseMenuActive(false)
end
local performance = config.performance or {}
local discoveryInterval = math.max(1000, performance.discoveryInterval or 3000)
local discoveryBatch = math.max(1, performance.discoveryBatch or 32)
local maintenanceInterval = math.max(500, performance.maintenanceInterval or 1000)
local seatInterval = math.max(500, performance.seatWatchdogInterval or 1000)

local saved = GetResourceKvpString(kvpKey)
if saved then
    local ok, data = pcall(json.decode, saved)
    if ok and type(data) == 'table' then
        preferences = ForgeSiren.preferences(data.preferences)
        layout = ForgeSiren.layout(data.layout)
        for index = 1, 3 do
            local preset = type(data.presets) == 'table' and data.presets[index]
            if type(preset) == 'table' then
                presets[index] = {
                    name = tostring(preset.name or ('PRESET %02d'):format(index)):sub(1, 24),
                    preferences = ForgeSiren.preferences(preset.preferences),
                }
            end
        end
    end
end

local function persist()
    local slots = {}
    for index = 1, 3 do slots[index] = presets[index] or false end
    SetResourceKvp(kvpKey, json.encode({ preferences = preferences, presets = slots, layout = layout }))
    staticUI = nil
end

local function exists(vehicle)
    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
end

local function controlledVehicle()
    local ped = cache.ped or PlayerPedId()
    if not ped or IsEntityDead(ped) then return end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not exists(vehicle) or IsEntityDead(vehicle) then return end
    local model = GetEntityModel(vehicle)
    local access = accessModels[model]
    if not access then
        local settings = config.access or {}
        access = {
            allowed = (settings.models and settings.models[model]) == true
                or (settings.classes or { [18] = true })[GetVehicleClass(vehicle)] == true,
            bike = GetVehicleType(vehicle) == 'bike',
        }
        accessModels[model] = access
    end
    if not access.allowed then return end
    local seat
    if GetPedInVehicleSeat(vehicle, -1) == ped then seat = -1
    elseif not access.bike and GetPedInVehicleSeat(vehicle, 0) == ped then seat = 0 end
    if not ForgeSiren.seatAllowed(seat, access.bike) then return end
    return vehicle, seat
end

local function stopSound(sound)
    if sound then StopSound(sound.id) ReleaseSoundId(sound.id) end
end

local function untrack(vehicle)
    local record = tracked[vehicle]
    if not record then return end
    stopSound(record.siren)
    stopSound(record.horn)
    tracked[vehicle] = nil
end

local function syncSound(record, key, audio)
    local old = record[key]
    -- A cached ID can outlive playback (for example around a vehicle exit or
    -- ownership migration). Reuse it only while the native sound is still live.
    if old and audio and old.name == audio.audioName and old.ref == audio.audioRef
        and not HasSoundFinished(old.id) then return end
    stopSound(old)
    record[key] = nil
    if audio then
        local id = GetSoundId()
        PlaySoundFromEntity(id, audio.audioName, record.vehicle, audio.audioRef or 0, false, 0)
        record[key] = { id = id, name = audio.audioName, ref = audio.audioRef }
    end
end

local function readState(vehicle)
    local state = Entity(vehicle).state
    if state.stateEnsured ~= true then return { stateEnsured = false } end
    return { stateEnsured = true, lightsOn = state.lightsOn == true,
        sirenMode = tonumber(state.sirenMode) or 0, horn = state.horn == true }
end

local function applyRecord(record)
    local vehicle, state = record.vehicle, record.state
    local dead = IsEntityDead(vehicle)
    local lights, owner = state.lightsOn and not dead, NetworkGetEntityOwner(vehicle)
    if record.lights ~= lights or record.owner ~= owner or IsVehicleSirenOn(vehicle) ~= lights then
        SetVehicleHasMutedSirens(vehicle, true)
        SetVehicleSiren(vehicle, lights)
        record.lights, record.owner = lights, owner
    end
    if dead then untrack(vehicle) return end
    local audio = state.sirenMode > 0 and record.profile.sirenModes[state.sirenMode] or nil
    if audio and not config.disableDamagedSirens then
        local health = config.useEngineHealth and GetVehicleEngineHealth(vehicle) or GetVehicleBodyHealth(vehicle)
        if health <= config.damageThreshold then audio = { audioName = 'PLAYER_FUCKED_SIREN' } end
    end
    syncSound(record, 'siren', not state.horn and audio or nil)
    syncSound(record, 'horn', state.horn and record.profile.horn or nil)
end

local function syncVehicle(vehicle, changes)
    if not exists(vehicle) or IsEntityDead(vehicle) then untrack(vehicle) return end
    local record = tracked[vehicle]
    if record and (record.netId ~= VehToNet(vehicle) or record.model ~= GetEntityModel(vehicle)) then
        untrack(vehicle)
        record = nil
    end
    if not record then
        local state = readState(vehicle)
        if changes then for key, value in pairs(changes) do state[key] = value end end
        if not state.stateEnsured then return end
        local model = GetEntityModel(vehicle)
        record = { vehicle = vehicle, model = model, netId = VehToNet(vehicle),
            profile = ForgeSiren.profile(model), state = state }
        tracked[vehicle] = record
    elseif changes then
        for key, value in pairs(changes) do record.state[key] = value end
    end
    if not record.state.stateEnsured then untrack(vehicle) return end
    if vehicle == activeVehicle and record.state.sirenMode > 0 then selectedMode = record.state.sirenMode end
    applyRecord(record)
end

local function queuePublish()
    if publishScheduled then return end
    publishScheduled = true
    SetTimeout(0, function() publishScheduled = false if publish then publish() end end)
end

local function notify(message)
    notice = message
    local expected = message
    queuePublish()
    SetTimeout(2400, function()
        if notice == expected then notice = '' queuePublish() end
    end)
end

local function request(name, value, hold)
    local target = hold or { netId = activeVehicle and VehToNet(activeVehicle), token = accessToken }
    if target.netId then TriggerServerEvent('forge-siren:server:control', target.netId, target.token, name, value) end
end

local function releaseHeld()
    if ForgeSirenMegaphone then ForgeSirenMegaphone.stop() end
    if hornHold then request('hornEnd', nil, hornHold) hornHold = nil end
    if manualHold then request('manualEnd', nil, manualHold) manualHold = nil end
end

local function setFocus(value)
    local wasFocused = focused
    releaseHeld()
    focused = value == true and activeVehicle ~= nil and controlledVehicle() == activeVehicle
    if wasFocused and not focused then pauseGuardUntil = GetGameTimer() + 250 end
    -- Apply immediately too: a NUI callback can release focus after this
    -- frame's control loop has already run.
    if focused or wasFocused then blockPauseMenu() end
    layoutEditing = false
    SetNuiFocus(focused, focused)
    SetNuiFocusKeepInput(focused)
    adminGeneration = adminGeneration + 1
    adminUI = { allowed = false }
    if focused and loadAdmin then loadAdmin() end
    staticUI, lastPayload = nil, nil
    queuePublish()
end

local function keyLabel(name, fallback)
    return bindings[name] and bindings[name]:getCurrentKey() or fallback
end

publish = function(force)
    local visible = activeVehicle ~= nil and not paused
    -- Outside an eligible seat there is no UI work, not even JSON encoding.
    if not visible then
        if lastPayload ~= 'hidden' or force then
            SendNUIMessage({ type = 'forge-siren:state', visible = false, focused = false })
            lastPayload = 'hidden'
        end
        return
    end
    local record = tracked[activeVehicle]
    local state = record and record.state or {}
    if not staticUI then
        local profile = ForgeSiren.profile(GetEntityModel(activeVehicle))
        local modes, slots = {}, {}
        for index, audio in ipairs(profile.sirenModes) do
            modes[index] = { id = index, label = audio.label or config.modeLabels[index] or ('TONE %d'):format(index) }
        end
        for index = 1, 3 do
            local preset = presets[index]
            slots[index] = { name = preset and preset.name or ('PRESET %02d'):format(index), saved = preset ~= nil }
        end
        staticUI = {
            modes = modes, presets = slots,
            vehicle = GetDisplayNameFromVehicleModel(GetEntityModel(activeVehicle)),
            keys = {
                lights = keyLabel('policeLights', 'Q'), horn = keyLabel('policeHorn', 'E'),
                sound = keyLabel('sirenToggle', 'ALT'), cycle = keyLabel('sirenCycle', 'R'),
                panel = keyLabel('panel', config.controls.panel or 'LCONTROL'),
                megaphone = ForgeSirenMegaphone and ForgeSirenMegaphone.key() or 'F7',
            },
        }
    end
    local payload = {
        type = 'forge-siren:state', visible = true, focused = focused, editing = layoutEditing,
        ready = registered and state.stateEnsured == true, lights = state.lightsOn == true,
        mode = state.sirenMode or 0, horn = state.horn == true, manual = manualHold ~= nil,
        megaphone = ForgeSirenMegaphone and ForgeSirenMegaphone.active() or false,
        selectedMode = selectedMode or 1, seat = activeSeat,
        modes = staticUI.modes, presets = staticUI.presets, vehicle = staticUI.vehicle,
        keys = staticUI.keys, preferences = preferences, notice = notice,
        admin = adminUI,
        layout = { right = config.ui.right, bottom = config.ui.bottom,
            x = layout and layout.x, y = layout and layout.y },
    }
    local encoded = json.encode(payload)
    if encoded ~= lastPayload or force then lastPayload = encoded SendNUIMessage(payload) end
end

loadAdmin = function(cb)
    if not focused or layoutEditing or not activeVehicle or controlledVehicle() ~= activeVehicle
        or not pr_lib.callback then if cb then cb({ ok = false }) end return end
    adminGeneration = adminGeneration + 1
    local generation, vehicle = adminGeneration, activeVehicle
    CreateThread(function()
        local ok, result = pcall(pr_lib.callback.await, 'forge-siren:server:adminGetMegaphone', 10000)
        if generation ~= adminGeneration or not focused or controlledVehicle() ~= vehicle then
            if cb then cb({ ok = false, error = 'Painel fechado.' }) end
            return
        end
        if ok and type(result) == 'table' and result.ok == true then
            adminUI = result
            queuePublish()
        end
        if cb then cb(ok and type(result) == 'table' and result or { ok = false, error = 'Servidor indisponivel.' }) end
    end)
end

local function setPrimary(mode)
    local profile = ForgeSiren.profile(GetEntityModel(activeVehicle))
    mode = tonumber(mode)
    if not mode or not profile.sirenModes[mode] then return false end
    preferences.primaryMode, selectedMode = mode, mode
    persist()
    notify('PRINCIPAL ' .. (profile.sirenModes[mode].label or config.modeLabels[mode] or tostring(mode)))
    return true
end

local function action(name, value)
    if name == 'megaphoneEnd' then
        if ForgeSirenMegaphone then ForgeSirenMegaphone.stop() end
        return true
    elseif name == 'hornEnd' then
        if hornHold then request(name, nil, hornHold) hornHold = nil end
        queuePublish()
        return true
    elseif name == 'manualEnd' then
        if manualHold then request(name, nil, manualHold) manualHold = nil end
        queuePublish()
        return true
    end
    local vehicle = controlledVehicle()
    if not vehicle or vehicle ~= activeVehicle or not registered or layoutEditing then return false end
    local record = tracked[vehicle]
    if not record then return false end
    local profile, state = record.profile, record.state
    local current = state.sirenMode or 0
    if name == 'megaphoneStart' then
        return ForgeSirenMegaphone and ForgeSirenMegaphone.start() or false
    elseif name == 'off' then
        releaseHeld()
        request('off')
        notify('SISTEMA DESLIGADO')
    elseif manualHold then
        return false
    elseif name == 'lights' or name == 'sound' then
        request(name, ForgeSiren.mode(profile, selectedMode))
    elseif name == 'hornStart' or name == 'manualStart' then
        if name == 'manualStart' and current > 0 then return false end
        local hold = { netId = record.netId, token = accessToken }
        if name == 'hornStart' then hornHold = hold else manualHold = hold end
        request(name, ForgeSiren.mode(profile, selectedMode), hold)
    elseif name == 'cycle' or name == 'previous' or name == 'next' or name == 'tone' then
        local mode
        if name == 'tone' then mode = tonumber(value)
        else mode = ForgeSiren.nextMode(profile, current > 0 and current or selectedMode, name == 'previous' and -1 or 1) end
        if not mode or not profile.sirenModes[mode] then return false end
        selectedMode = mode
        -- The server cycles its authoritative audible tone; an idle selection
        -- stays local so one occupant does not overwrite the other's preset.
        if current > 0 then request(name, mode) end
        notify(profile.sirenModes[mode].label or config.modeLabels[mode] or ('TONE %d'):format(mode))
    elseif name == 'primary' then
        return setPrimary(ForgeSiren.nextMode(profile, preferences.primaryMode, 1))
    elseif name == 'keepLights' or name == 'keepSound' then
        preferences[name] = not preferences[name]
        persist()
        notify((name == 'keepLights' and 'LUZ AO SAIR ' or 'SOM AO SAIR ') .. (preferences[name] and 'MANTER' or 'DESLIGAR'))
    else
        return false
    end
    queuePublish()
    return true
end

AddEventHandler('forge-siren:megaphoneChanged', queuePublish)

local function leaveVehicle(vehicle, token)
    releaseHeld()
    if exists(vehicle) then
        TriggerServerEvent('forge-siren:server:leave', VehToNet(vehicle), token, preferences.keepLights, preferences.keepSound)
    end
end

local function ensureAccess(vehicle, token)
    if activeVehicle == vehicle and accessToken == token and controlledVehicle() == vehicle then
        TriggerServerEvent('forge-siren:server:ensure', VehToNet(vehicle), token)
    end
end

reconcile = function()
    local vehicle, seat = controlledVehicle()
    if vehicle == activeVehicle then
        if seat ~= activeSeat then activeSeat = seat queuePublish() end
        return
    end
    if activeVehicle then leaveVehicle(activeVehicle, accessToken) end
    activeVehicle, activeSeat, registered = vehicle, seat, false
    accessToken = accessToken + 1
    staticUI, lastPayload, notice = nil, nil, ''
    setFocus(false)
    if vehicle then
        syncVehicle(vehicle)
        local record = tracked[vehicle]
        selectedMode = ForgeSiren.mode(ForgeSiren.profile(GetEntityModel(vehicle)),
            record and record.state.sirenMode > 0 and record.state.sirenMode or preferences.primaryMode)
        if seat == -1 then SetVehRadioStation(vehicle, 'OFF') SetVehicleRadioEnabled(vehicle, false) end
        local token = accessToken
        ensureAccess(vehicle, token)
        for _, delay in ipairs({ 350, 1200 }) do SetTimeout(delay, function()
            if not registered then ensureAccess(vehicle, token) end
        end) end
    end
    queuePublish()
end

local reconcileScheduled = false
local function scheduleReconcile()
    if reconcileScheduled then return end
    reconcileScheduled = true
    SetTimeout(0, function() reconcileScheduled = false reconcile() end)
end
pr_lib.onCache('vehicle', scheduleReconcile)
pr_lib.onCache('seat', scheduleReconcile)
pr_lib.onCache('ped', scheduleReconcile)

RegisterNetEvent('forge-siren:client:ready', function(netId, token, state)
    if not activeVehicle or VehToNet(activeVehicle) ~= netId or token ~= accessToken then return end
    registered = true
    syncVehicle(activeVehicle, state)
    queuePublish()
end)

for _, key in ipairs({ 'lightsOn', 'sirenMode', 'horn', 'stateEnsured' }) do
    AddStateBagChangeHandler(key, '', function(bagName, changedKey, value)
        local netId = tonumber(bagName:match('^entity:(%d+)$'))
        if not netId then return end
        -- Deleted keys must clear the snapshot too; nil cannot be queued in a table.
        if changedKey == 'sirenMode' then
            value = tonumber(value) or 0
            if value ~= value or value < 0 or value == math.huge or value % 1 ~= 0 then value = 0 end
        else value = value == true end
        local pending = pendingBags[netId]
        if pending then pending[changedKey] = value return end
        pending = { [changedKey] = value }
        pendingBags[netId] = pending
        SetTimeout(0, function()
            pendingBags[netId] = nil
            -- No per-frame waiting for an out-of-scope entity. Discovery will
            -- recover it later if its state was delivered before streaming.
            if not NetworkDoesEntityExistWithNetworkId(netId) then return end
            local vehicle = NetToVeh(netId)
            syncVehicle(vehicle, pending)
            if vehicle == activeVehicle then queuePublish() end
        end)
    end)
end

local function bind(name, description, pressed, released)
    bindings[name] = pr_lib.addKeybind({
        name = name, description = description, defaultKey = config.controls[name],
        onPressed = function() if not focused then pressed() end end, onReleased = released,
    })
end
bind('policeLights', 'Forge Siren: ligar/desligar luzes', function() action('lights') end)
bind('policeHorn', 'Forge Siren: segurar corneta', function() action('hornStart') end, function() action('hornEnd') end)
bind('sirenToggle', 'Forge Siren: ligar/desligar som', function() action('sound') end)
bind('sirenCycle', 'Forge Siren: alternar tom / segurar manual', function()
    local record = activeVehicle and tracked[activeVehicle]
    if record then action(record.state.sirenMode > 0 and 'cycle' or 'manualStart') end
end, function() action('manualEnd') end)
bindings.panel = pr_lib.addKeybind({
    name = 'forgeSirenPanel', description = 'Forge Siren: cursor do painel', defaultKey = config.controls.panel,
    -- The native mapping alone owns the cursor key, even with it open. The NUI
    -- must not toggle it again when the same key reaches both input paths.
    onPressed = function() reconcile() setFocus(not focused) end,
})
RegisterCommand(config.ui.command, function(_, args)
    reconcile()
    if args and (args[1] == 'ajustar' or args[1] == 'layout') then
        setFocus(true)
        layoutEditing = focused
        queuePublish()
    else setFocus(not focused) end
end, false)
RegisterNUICallback('ready', function(_, cb) lastPayload = nil publish(true) cb({ ok = true }) end)
RegisterNUICallback('close', function(_, cb) setFocus(false) cb({ ok = true }) end)
RegisterNUICallback('release', function(_, cb) releaseHeld() queuePublish() cb({ ok = true }) end)
RegisterNUICallback('adminGet', function(_, cb) loadAdmin(cb) end)
RegisterNUICallback('adminSave', function(data, cb)
    if not focused or layoutEditing or not activeVehicle or controlledVehicle() ~= activeVehicle
        or type(data) ~= 'table' or not pr_lib.callback then cb({ ok = false }) return end
    local generation, vehicle = adminGeneration, activeVehicle
    CreateThread(function()
        -- The server re-checks permission and every field; the NUI is not authority.
        local ok, result = pcall(pr_lib.callback.await, 'forge-siren:server:adminSaveMegaphone', 10000, data)
        if generation == adminGeneration and focused and controlledVehicle() == vehicle
            and ok and type(result) == 'table' and result.ok == true then
            adminUI = result
            notify('MEGAFONE GLOBAL SALVO')
            queuePublish()
        end
        cb(ok and type(result) == 'table' and result or { ok = false, error = 'Servidor indisponivel.' })
    end)
end)
RegisterNetEvent('forge-siren:client:megaphoneConfigChanged', function()
    if source ~= 65535 then return end
    if focused then loadAdmin() end
end)
RegisterNUICallback('layoutEdit', function(data, cb)
    if not focused or not activeVehicle or controlledVehicle() ~= activeVehicle
        or type(data) ~= 'table' or type(data.enabled) ~= 'boolean' then cb({ ok = false }) return end
    releaseHeld()
    layoutEditing = data.enabled
    queuePublish()
    cb({ ok = true })
end)
RegisterNUICallback('layout', function(data, cb)
    if not focused or not layoutEditing or not activeVehicle or controlledVehicle() ~= activeVehicle
        or type(data) ~= 'table' or type(data.scale) ~= 'number' or data.scale ~= data.scale
        or data.scale == math.huge or data.scale == -math.huge then cb({ ok = false }) return end
    local position = ForgeSiren.layout(data)
    if not position then cb({ ok = false }) return end
    layout = position
    preferences.scale = ForgeSiren.preferences({ scale = data.scale }).scale
    layoutEditing = false
    persist()
    notify('PAINEL AJUSTADO')
    cb({ ok = true })
end)
RegisterNUICallback('action', function(data, cb)
    cb({ ok = focused and type(data) == 'table' and action(data.name, data.value) or false })
end)
RegisterNUICallback('preference', function(data, cb)
    if not focused or layoutEditing or not activeVehicle or controlledVehicle() ~= activeVehicle or type(data) ~= 'table' then cb({ ok = false }) return end
    local ok = false
    if (data.key == 'keepLights' or data.key == 'keepSound') and type(data.value) == 'boolean' then
        preferences[data.key] = data.value
        persist()
        notify((data.key == 'keepLights' and 'LUZ AO SAIR ' or 'SOM AO SAIR ') .. (data.value and 'MANTER' or 'DESLIGAR'))
        ok = true
    elseif data.key == 'primaryMode' then ok = setPrimary(data.value)
    elseif data.key == 'scale' and type(data.value) == 'number' then
        preferences = ForgeSiren.preferences({ keepLights = preferences.keepLights, keepSound = preferences.keepSound,
            primaryMode = preferences.primaryMode, scale = data.value })
        persist()
        ok = true
    end
    queuePublish()
    cb({ ok = ok })
end)
RegisterNUICallback('preset', function(data, cb)
    if not focused or layoutEditing or not activeVehicle or controlledVehicle() ~= activeVehicle or type(data) ~= 'table' then cb({ ok = false }) return end
    local slot = tonumber(data.slot)
    if not slot or slot % 1 ~= 0 or slot < 1 or slot > 3 then cb({ ok = false }) return end
    if data.operation == 'save' then
        local name = type(data.name) == 'string' and data.name:gsub('[%c]', ''):sub(1, 24) or ''
        if name:match('^%s*$') then name = ('PRESET %02d'):format(slot) end
        presets[slot] = { name = name, preferences = ForgeSiren.preferences(preferences) }
        persist()
        notify(('PRESET %02d SALVO'):format(slot))
    elseif data.operation == 'load' and presets[slot] then
        preferences = ForgeSiren.preferences(presets[slot].preferences)
        selectedMode = ForgeSiren.mode(ForgeSiren.profile(GetEntityModel(activeVehicle)), preferences.primaryMode)
        persist()
        notify(('PRESET %02d ATIVO'):format(slot))
    else cb({ ok = false }) return end
    queuePublish()
    cb({ ok = true })
end)

CreateThread(function()
    local nextSeatCheck, nextKeysCheck = 0, 0
    while true do
        local now = GetGameTimer()
        if now >= nextSeatCheck then
            reconcile()
            if activeVehicle and not registered then ensureAccess(activeVehicle, accessToken) end
            nextSeatCheck = now + seatInterval
        end
        if activeVehicle then
            local value = IsPauseMenuActive()
            if value ~= paused then
                paused = value
                if paused and focused then setFocus(false) end
                queuePublish()
            end
            -- Key remaps are rare; do not rebuild their labels on every UI tick.
            if now >= nextKeysCheck then
                nextKeysCheck = now + 5000
                staticUI = nil
                queuePublish()
            end
        end
        Wait(activeVehicle and 250 or 1000)
    end
end)
CreateThread(function()
    while true do
        local now = GetGameTimer()
        local blockPause = focused or now < pauseGuardUntil
        if blockPause then
            blockPauseMenu()
            -- Consume the same Esc press, including its release, after NUI
            -- focus closes. Holding it must not open GTA once a timer expires.
            for group = 0, 2 do
                for index = 1, #pauseControls do
                    if IsDisabledControlPressed(group, pauseControls[index]) then pauseGuardUntil = now + 100 end
                end
            end
        end
        if activeVehicle and not paused then
            for index = 1, #controls do DisableControlAction(0, controls[index], true) end
            if focused then
                for index = 1, #cursorControls do DisableControlAction(0, cursorControls[index], true) end
            end
            Wait(0)
        else Wait(blockPause and 0 or 250) end
    end
end)
CreateThread(function()
    while true do
        for vehicle, record in pairs(tracked) do
            if not exists(vehicle) or record.netId ~= VehToNet(vehicle) or record.model ~= GetEntityModel(vehicle) then
                untrack(vehicle)
            else applyRecord(record) end
        end
        Wait(maintenanceInterval)
    end
end)
CreateThread(function()
    while true do
        local pool = GetGamePool('CVehicle')
        for index = 1, #pool do
            local vehicle = pool[index]
            if not tracked[vehicle] and exists(vehicle) and not IsEntityDead(vehicle) then
                -- Read an unknown entity once; known ones use cached state.
                syncVehicle(vehicle)
            end
            if index % discoveryBatch == 0 then Wait(0) end
        end
        Wait(discoveryInterval)
    end
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    if activeVehicle then leaveVehicle(activeVehicle, accessToken) end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    for vehicle in pairs(tracked) do untrack(vehicle) end
end)
