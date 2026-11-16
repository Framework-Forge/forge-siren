local vehicles, players, entities = {}, {}, {}

local function integer(value)
    return type(value) == 'number' and value == value and value > 0 and value < math.huge and value % 1 == 0
end

local function resolve(netId)
    if not integer(netId) then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
    return vehicle
end

local function authorized(vehicle, ped)
    if not ped or ped == 0 then return false end
    if GetPedInVehicleSeat(vehicle, -1) == ped then return true end
    return GetVehicleType(vehicle) ~= 'bike' and GetPedInVehicleSeat(vehicle, 0) == ped
end

local function set(record, key, value)
    local state = Entity(record.vehicle).state
    if state[key] ~= value then state:set(key, value, true) end
end

local function release(record, player)
    if record.horns[player] then
        record.horns[player] = nil
        set(record, 'horn', next(record.horns) ~= nil)
    end
    if record.manual == player then
        record.manual = nil
        set(record, 'sirenMode', 0)
    end
end

local function removeMember(record, player)
    release(record, player)
    record.members[player] = nil
    if players[player] == record then players[player] = nil end
    record.revision = record.revision + 1
end

local function ensure(netId, token)
    local player = source
    local vehicle, ped = resolve(netId), GetPlayerPed(player)
    if not integer(token) or not vehicle or not authorized(vehicle, ped) then return end
    local record = vehicles[netId]
    if record and record.vehicle ~= vehicle then return end
    if not record then
        record = { vehicle = vehicle, netId = netId, members = {}, horns = {}, revision = 0,
            profile = ForgeSiren.profile(GetEntityModel(vehicle)) }
        vehicles[netId], entities[vehicle] = record, netId
        -- A momentary horn has no valid holder after a resource restart.
        set(record, 'horn', false)
    end
    local previous = players[player]
    if previous and previous ~= record then removeMember(previous, player) end
    local member = record.members[player]
    if not member or member.token ~= token or member.ped ~= ped then
        if member then release(record, player) end
        record.members[player] = { token = token, ped = ped }
        record.revision = record.revision + 1
    end
    players[player] = record
    local state = Entity(vehicle).state
    if type(state.lightsOn) ~= 'boolean' then set(record, 'lightsOn', false) end
    if type(state.sirenMode) ~= 'number' then set(record, 'sirenMode', 0) end
    if type(state.horn) ~= 'boolean' then set(record, 'horn', false) end
    set(record, 'stateEnsured', true)
    TriggerClientEvent('forge-siren:client:ready', player, netId, token, {
        stateEnsured = true, lightsOn = state.lightsOn, sirenMode = state.sirenMode, horn = state.horn,
    })
end
RegisterNetEvent('forge-siren:server:ensure', ensure)
RegisterNetEvent('Renewed-Sirensync:server:SyncState', function(netId) ensure(netId, 1) end)

local function session(player, netId, token)
    local record = vehicles[netId]
    local member = record and record.members[player]
    if not member or member.token ~= token or record.vehicle ~= resolve(netId) then return end
    return record, member
end

RegisterNetEvent('forge-siren:server:control', function(netId, token, name, value)
    local player = source
    local record, member = session(player, netId, token)
    if not record then return end
    -- A release belongs to its original session even after a seat change.
    if name == 'hornEnd' or name == 'manualEnd' then
        if name == 'hornEnd' and record.horns[player] then
            record.horns[player] = nil
            set(record, 'horn', next(record.horns) ~= nil)
        elseif name == 'manualEnd' and record.manual == player then
            record.manual = nil
            set(record, 'sirenMode', 0)
        end
        return
    end
    if member.ped ~= GetPlayerPed(player) or not authorized(record.vehicle, member.ped) then return end
    local state, profile = Entity(record.vehicle).state, record.profile
    local mode = state.sirenMode or 0
    if name == 'off' then
        record.horns, record.manual = {}, nil
        set(record, 'horn', false)
        set(record, 'sirenMode', 0)
        set(record, 'lightsOn', false)
    elseif name == 'hornStart' then
        record.horns[player] = true
        set(record, 'horn', true)
    elseif record.manual then
        return
    elseif name == 'lights' then
        local lights = not state.lightsOn
        set(record, 'lightsOn', lights)
        if not lights then set(record, 'sirenMode', 0) end
    elseif name == 'sound' or name == 'manualStart' or name == 'tone' then
        if not integer(value) or not profile.sirenModes[value] then return end
        if name == 'manualStart' then
            if mode > 0 then return end
            record.manual = player
            set(record, 'lightsOn', true)
            set(record, 'sirenMode', value)
        elseif name == 'sound' then
            if mode > 0 then set(record, 'sirenMode', 0)
            else set(record, 'lightsOn', true) set(record, 'sirenMode', value) end
        elseif mode > 0 then set(record, 'sirenMode', value) end
    elseif name == 'cycle' or name == 'previous' or name == 'next' then
        if mode > 0 then set(record, 'sirenMode', ForgeSiren.nextMode(profile, mode, name == 'previous' and -1 or 1)) end
    else
        return
    end
    record.revision = record.revision + 1
end)

local function exitPolicy(record, ped, keepLights, keepSound)
    local revision = record.revision
    local function apply()
        if vehicles[record.netId] ~= record or record.revision ~= revision or resolve(record.netId) ~= record.vehicle then return end
        -- Protect the other front occupant, including one whose ensure packet
        -- has not arrived yet. Motorcycle pillions never retain panel access.
        local driver = GetPedInVehicleSeat(record.vehicle, -1)
        local copilot = GetVehicleType(record.vehicle) ~= 'bike' and GetPedInVehicleSeat(record.vehicle, 0) or 0
        if (driver ~= 0 and driver ~= ped) or (copilot ~= 0 and copilot ~= ped) then return end
        if not keepSound then set(record, 'sirenMode', 0) end
        if not keepLights then set(record, 'lightsOn', false) end
    end
    -- Let replicated seats settle; the revision cancels stale delayed exits.
    SetTimeout(250, apply)
    SetTimeout(1000, apply)
end

RegisterNetEvent('forge-siren:server:leave', function(netId, token, keepLights, keepSound)
    if type(keepLights) ~= 'boolean' or type(keepSound) ~= 'boolean' then return end
    local record, member = session(source, netId, token)
    if not record then return end
    removeMember(record, source)
    exitPolicy(record, member.ped, keepLights, keepSound)
end)

AddEventHandler('entityRemoved', function(entity)
    local netId = entities[entity]
    local record = netId and vehicles[netId]
    if not record then return end
    for player in pairs(record.members) do if players[player] == record then players[player] = nil end end
    vehicles[netId], entities[entity] = nil, nil
end)

AddEventHandler('playerDropped', function()
    local record = players[source]
    if not record then return end
    local member = record.members[source]
    if resolve(record.netId) == record.vehicle then
        removeMember(record, source)
        local defaults = ForgeSiren.preferences()
        exitPolicy(record, member.ped, defaults.keepLights, defaults.keepSound)
    else
        record.members[source], record.horns[source], players[source] = nil, nil, nil
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for netId, record in pairs(vehicles) do
        if resolve(netId) == record.vehicle then
            set(record, 'horn', false)
            if record.manual then set(record, 'sirenMode', 0) end
        end
    end
end)
