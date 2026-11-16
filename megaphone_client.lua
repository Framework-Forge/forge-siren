ForgeSirenMegaphone = {}
local api, config = ForgeSirenMegaphone, ForgeSiren.config.megaphone or {}
local equipped, held, transmitting, sequence, prop, equipGeneration = false, nil, false, 0, nil, 0
local binding, equipPed
local function notify(message, kind)
    pr_lib.notify({ title = 'Megafone', description = message, type = kind or 'inform' })
end
local voiceMessages = {
    resource_stopped = 'O PMA Voice nao esta iniciado.',
    integration_unavailable = 'A integracao de megafone do PMA Voice nao esta disponivel. Reinicie o PMA Voice e o Forge Siren.',
    unsupported_game = 'O megafone requer FiveM.',
    megaphone_disabled = 'O megafone esta desabilitado pelo administrador no painel Forge Siren.',
    native_audio_disabled = 'O audio nativo esta desabilitado. Configure voice_useNativeAudio true no voice.cfg.',
    submix_disabled = 'O efeito de voz esta desabilitado. Configure voice_enableSubmix 1 no voice.cfg.',
    voice_disconnected = 'A voz do FiveM nao esta conectada. Verifique o bate-papo de voz e aguarde a conexao.',
    voice_initializing = 'A voz esta inicializando. Aguarde alguns segundos e pressione %s novamente.',
    character_unavailable = 'O PMA Voice ainda nao recebeu os dados do personagem. Use /megafonediag para conferir.',
    proximity_disabled = 'A voz por proximidade esta desativada por outro recurso.',
    radio_active = 'Encerre a transmissao pelo radio antes de usar o megafone.',
    call_active = 'Encerre a chamada antes de usar o megafone.',
    incapacitated = 'O estado de voz indica personagem morto ou incapacitado.',
}
local function voiceReady()
    if GetResourceState('pma-voice') ~= 'started' then return false, 'resource_stopped' end
    local ok, ready, reason = pcall(function() return exports['pma-voice']:canUseMegaphone() end)
    if not ok then return false, 'integration_unavailable' end
    return ready == true, reason
end
local function notifyVoice(reason)
    local message = voiceMessages[reason]
    if reason == 'voice_initializing' then message = message:format(api.key()) end
    notify(message or 'A voz ainda nao esta disponivel. Use /megafonediag para identificar o bloqueio.', 'error')
end
local function alive(ped)
    return not IsEntityDead(ped) and not pr_lib.cache.GetMetadata('isdead')
        and not pr_lib.cache.GetMetadata('inlaststand') and not IsPauseMenuActive()
end
local function context()
    local ped = PlayerPedId()
    if not alive(ped) then return end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        local model = GetEntityModel(vehicle)
        local access = ForgeSiren.config.access or {}
        local allowed = (access.models or {})[model] or (access.classes or { [18] = true })[GetVehicleClass(vehicle)]
            or (config.models or {})[model]
        if not allowed or IsEntityDead(vehicle) then return end
        local bike = GetVehicleType(vehicle) == 'bike'
        if GetPedInVehicleSeat(vehicle, -1) == ped or not bike and GetPedInVehicleSeat(vehicle, 0) == ped then
            return ped, vehicle
        end
    elseif equipped and pr_lib.inventory.GetItemCount(config.item or 'megaphone') > 0 then return ped, 0 end
end
function api.key() return binding and binding:getCurrentKey() or ForgeSiren.config.controls.megaphone or 'F7' end
function api.active() return transmitting end
function api.stop()
    local token = held
    held = nil
    if GetResourceState('pma-voice') == 'started' then exports['pma-voice']:setMegaphoneInput(false) end
    if token then TriggerServerEvent('forge-siren:server:megaphone', token, false) end
end
function api.start()
    if held then return false end
    local ped, vehicle = context()
    if not ped then return false end
    local ready, reason = voiceReady()
    if not ready then
        notifyVoice(reason)
        return false
    end
    sequence = sequence + 1
    local token = sequence
    held = token
    exports['pma-voice']:setMegaphoneInput(token)
    TriggerServerEvent('forge-siren:server:megaphone', token, true)
    SetTimeout(2000, function() if held == token and not transmitting then api.stop() end end)
    CreateThread(function()
        local heartbeat = GetGameTimer()
        while held == token do
            local currentPed, currentVehicle = context()
            if currentPed ~= ped or currentVehicle ~= vehicle then api.stop() break end
            if GetGameTimer() - heartbeat >= 1000 then
                heartbeat = GetGameTimer()
                TriggerServerEvent('forge-siren:server:megaphoneHeartbeat', token)
            end
            Wait(150)
        end
    end)
    return true
end

local function unequip(send)
    equipGeneration = equipGeneration + 1
    equipped = false
    api.stop()
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = nil
    local animation = config.animation
    if equipPed and animation then StopAnimTask(equipPed, animation.dict, animation.clip, -4.0) end
    equipPed = nil
    if send then TriggerServerEvent('forge-siren:server:megaphoneUnequip') end
end

RegisterNetEvent('forge-siren:client:megaphoneItem', function(enabled)
    if source ~= 65535 then return end
    if not enabled then unequip(false) return end
    unequip(false)
    equipped = true
    equipPed = PlayerPedId()
    local generation, ped = equipGeneration, equipPed
    local model, animation = joaat(config.prop or 'prop_megaphone_01'), config.animation
    pr_lib.inventory.closeInventory()
    CreateThread(function()
        RequestModel(model)
        RequestAnimDict(animation.dict)
        local deadline = GetGameTimer() + 5000
        while equipped and generation == equipGeneration and GetGameTimer() < deadline
            and (not HasModelLoaded(model) or not HasAnimDictLoaded(animation.dict)) do Wait(50) end
        if not equipped or generation ~= equipGeneration then SetModelAsNoLongerNeeded(model) return end
        if not HasModelLoaded(model) or not HasAnimDictLoaded(animation.dict) then
            SetModelAsNoLongerNeeded(model)
            unequip(true)
            notify('Nao foi possivel carregar o megafone.', 'error')
            return
        end
        local position = GetEntityCoords(ped)
        prop = CreateObjectNoOffset(model, position.x, position.y, position.z, true, true, false)
        SetModelAsNoLongerNeeded(model)
        if not prop or prop == 0 then unequip(true) return end
        SetEntityCollision(prop, false, false)
        local p, r = animation.position, animation.rotation
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, animation.bone),
            p[1], p[2], p[3], r[1], r[2], r[3], true, true, false, true, 2, true)
        SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
        notify(('Segure %s para falar. Use o item novamente ou /megafone para guardar.'):format(api.key()))
        while equipped and generation == equipGeneration do
            if PlayerPedId() ~= ped or not context() or GetVehiclePedIsIn(ped, false) ~= 0 then unequip(true) break end
            if not IsEntityPlayingAnim(ped, animation.dict, animation.clip, 3) then
                TaskPlayAnim(ped, animation.dict, animation.clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
            end
            Wait(250)
        end
        RemoveAnimDict(animation.dict)
    end)
end)
RegisterNetEvent('forge-siren:client:megaphoneStopped', function(token, reason)
    if source ~= 65535 or token ~= held then return end
    api.stop()
    if reason then notify(reason, 'error') end
end)
AddEventHandler('pma-voice:megaphoneActive', function(active)
    transmitting = active == true
    TriggerEvent('forge-siren:megaphoneChanged')
end)
AddEventHandler('pma-voice:megaphoneInterrupted', api.stop)
AddEventHandler('pma-voice:megaphoneMonitorNotice', notify)
AddEventHandler('pr_bridge:client:OnPlayerUnloaded', function() unequip(true) end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pma-voice' then
        unequip(true)
        transmitting = false
        TriggerEvent('forge-siren:megaphoneChanged')
    end
end)
binding = pr_lib.addKeybind({
    name = 'forgeSirenMegaphone', description = 'Forge Siren: segurar megafone',
    defaultKey = ForgeSiren.config.controls.megaphone or 'F7', onPressed = api.start, onReleased = api.stop,
})
RegisterCommand('megafone', function() if equipped then unequip(true) end end, false)

-- Self-only diagnostic: no identifiers, channel IDs, inventory writes or
-- server transmission request. It also works with no other player online.
pr_lib.addCommand('megafonediag', { help = 'Verificar a disponibilidade da voz do megafone' }, function()
    local ready, reason = voiceReady()
    if GetResourceState('pma-voice') == 'started' then
        local ok, status = pcall(function() return exports['pma-voice']:getMegaphoneStatus() end)
        if ok and type(status) == 'table' then
            print(('[Forge Siren] Megafone: %s'):format(json.encode(status)))
        else
            print(('[Forge Siren] Megafone: %s'):format(reason or 'integration_unavailable'))
        end
    else
        print('[Forge Siren] Megafone: resource_stopped')
    end
    if ready then notify('Voz pronta para o megafone. Segure ' .. api.key() .. ' para falar.', 'success')
    else notifyVoice(reason) end
end)
