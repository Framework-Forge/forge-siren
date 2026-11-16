local config = ForgeSiren.config.megaphone or {}
local sessions, equipped, lastRequests = {}, {}, {}
local function settings()
    return ForgeSiren.getMegaphoneSettings and ForgeSiren.getMegaphoneSettings()
        or ForgeSiren.megaphoneDefaults(math.max(1, GetConvarInt('voice_megaphoneMaxRange', 50)))
end
local function grant(player, token)
    local value = settings()
    return value.enabled and exports['pma-voice']:setPlayerMegaphone(player, {
        token = token, range = value.range, volume = value.listenerVolume / 100,
        farVolume = value.farVolume / 100,
    })
end

local function alive(player, ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return false end
    local metadata = pr_lib.framework.GetPlayerMetadata
    if metadata and (metadata(player, 'isdead') or metadata(player, 'inlaststand')) then return false end
    return true
end

local function hasItem(player)
    return pr_lib.inventory.GetItemCount(player, config.item or 'megaphone') > 0
end

local function allowedVehicle(vehicle, ped)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityHealth(vehicle) <= 0 then return false end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped
        and (GetVehicleType(vehicle) == 'bike' or GetPedInVehicleSeat(vehicle, 0) ~= ped) then return false end
    local model = GetEntityModel(vehicle)
    if (config.models or {})[model] or ((ForgeSiren.config.access or {}).models or {})[model] then return true end
    local data = pr_lib.framework.GetVehicleData(model)
    -- GetVehicleClass is client-only; use the framework's authoritative
    -- catalog or an explicit model allowlist, not a client-reported class.
    return type(data) == 'table' and data.category == 'emergency'
end

local function voiceAvailable(player)
    if GetResourceState('pma-voice') ~= 'started' then return false end
    local state = exports['pma-voice']:GetVoiceState(player)
    return state.identifier ~= nil and (state.assignedChannel or 0) > 0 and not state.disableProximity and not state.radioActive
        and (state.callChannel or 0) == 0
end

local function stop(player, reason)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil
    if GetResourceState('pma-voice') == 'started' then exports['pma-voice']:setPlayerMegaphone(player, false) end
    TriggerClientEvent('forge-siren:client:megaphoneStopped', player, session.token, reason)
end

local function valid(player, session)
    local ped = GetPlayerPed(player)
    if session.ped ~= ped or not alive(player, ped) or GetPlayerRoutingBucket(player) ~= session.bucket
        or not voiceAvailable(player) then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if session.vehicle then return vehicle == session.vehicle and allowedVehicle(vehicle, ped) end
    return vehicle == 0 and equipped[player] and hasItem(player)
end

RegisterNetEvent('forge-siren:server:megaphone', function(token, enabled)
    local player = source
    if type(token) ~= 'number' or token <= 0 or token % 1 ~= 0 or token == math.huge then return end
    if enabled == false then
        if sessions[player] and sessions[player].token == token then stop(player) end
        return
    end
    if enabled ~= true or not settings().enabled then return end
    local now = GetGameTimer()
    if now - (lastRequests[player] or -1000) < 200 then
        TriggerClientEvent('forge-siren:client:megaphoneStopped', player, token)
        return
    end
    lastRequests[player] = now
    stop(player)
    local ped = GetPlayerPed(player)
    local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    local session = { token = token, ped = ped, vehicle = vehicle ~= 0 and vehicle or nil,
        bucket = GetPlayerRoutingBucket(player), heartbeat = now }
    if not valid(player, session) then
        TriggerClientEvent('forge-siren:client:megaphoneStopped', player, token, 'Acesso ao megafone indisponivel.')
        return
    end
    if not grant(player, token) then
        TriggerClientEvent('forge-siren:client:megaphoneStopped', player, token, 'Megafone desabilitado no PMA Voice.')
        return
    end
    sessions[player] = session
end)

RegisterNetEvent('forge-siren:server:megaphoneHeartbeat', function(token)
    local session = sessions[source]
    if session and session.token == token then session.heartbeat = GetGameTimer() end
end)
RegisterNetEvent('forge-siren:server:megaphoneUnequip', function()
    equipped[source] = nil
    stop(source)
end)

local function registerItem()
    pr_lib.inventory.RegisterUsableItem(config.item or 'megaphone', function(player)
        if not settings().enabled then return false end
        local ped = GetPlayerPed(player)
        if not alive(player, ped) or GetVehiclePedIsIn(ped, false) ~= 0 or not hasItem(player) then return false end
        equipped[player] = not equipped[player] or nil
        if not equipped[player] then stop(player) end
        TriggerClientEvent('forge-siren:client:megaphoneItem', player, equipped[player] == true)
        return false -- equipment is never consumed
    end)
end
CreateThread(registerItem)
AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_inventory' then SetTimeout(500, registerItem) end
end)
AddEventHandler('forge-siren:server:megaphoneConfigChanged', function()
    -- Update existing grants without extending their heartbeat or changing tokens.
    for player, session in pairs(sessions) do
        if not valid(player, session) or not grant(player, session.token) then stop(player) end
    end
end)

CreateThread(function()
    while true do
        Wait((next(sessions) or next(equipped)) and 500 or 1000)
        for player, session in pairs(sessions) do
            if GetGameTimer() - session.heartbeat > 3000 or not valid(player, session) then stop(player) end
        end
        for player in pairs(equipped) do
            local ped = GetPlayerPed(player)
            if not alive(player, ped) or GetVehiclePedIsIn(ped, false) ~= 0 or not hasItem(player) then
                equipped[player] = nil
                stop(player)
                TriggerClientEvent('forge-siren:client:megaphoneItem', player, false)
            end
        end
    end
end)
local function cleanup(player)
    player = tonumber(player)
    if not player then return end
    stop(player)
    equipped[player], lastRequests[player] = nil, nil
end
AddEventHandler('playerDropped', function() cleanup(source) end)
AddEventHandler('pr_bridge:server:OnPlayerUnloaded', cleanup)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'pma-voice' then return end
    for player in pairs(sessions) do stop(player) end
end)
