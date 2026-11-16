ForgeSiren = { config = pr_lib.load('config') }

local config = ForgeSiren.config
local profiles = {}

function ForgeSiren.profile(model)
    if profiles[model] then return profiles[model] end
    local profile = { sirenModes = {}, horn = { audioName = 'SIRENS_AIRHORN' } }
    for _, group in ipairs(config.sirens or {}) do
        if not group.models or group.models[model] then
            -- A lista do grupo substitui a base inteira: motos com 2 tons nao
            -- recebem um terceiro tom policial por heranca acidental.
            if group.sirenModes then profile.sirenModes = group.sirenModes end
            if group.horn then profile.horn = group.horn end
        end
    end
    profiles[model] = profile
    return profile
end

function ForgeSiren.seatAllowed(seat, isBike)
    return seat == -1 or (seat == 0 and not isBike)
end

function ForgeSiren.preferences(value)
    local defaults = config.preferences or {}
    value = type(value) == 'table' and value or {}
    local function boolean(key, fallback)
        if type(value[key]) == 'boolean' then return value[key] end
        if type(defaults[key]) == 'boolean' then return defaults[key] end
        return fallback
    end
    local mode = tonumber(value.primaryMode) or tonumber(defaults.primaryMode) or 1
    local scale = tonumber(value.scale) or tonumber(defaults.scale) or 1.0
    if mode ~= mode or mode == math.huge or mode == -math.huge then mode = 1 end
    if scale ~= scale or scale == math.huge or scale == -math.huge then scale = 1.0 end
    return {
        keepLights = boolean('keepLights', true),
        keepSound = boolean('keepSound', config.sirenShutOff == false),
        primaryMode = math.max(1, math.min(16, math.floor(mode))),
        scale = math.max(0.4, math.min(1.3, scale)),
    }
end

function ForgeSiren.layout(value)
    if type(value) ~= 'table' then return end
    local x, y = value.x, value.y
    local function finite(number)
        return type(number) == 'number' and number == number and number > -math.huge and number < math.huge
    end
    if not finite(x) or not finite(y) then return end
    return { x = math.max(0, math.min(1, x)), y = math.max(0, math.min(1, y)) }
end

function ForgeSiren.mode(profile, wanted)
    local mode = tonumber(wanted) or 1
    if mode ~= mode or mode == math.huge or mode == -math.huge then mode = 1 end
    mode = math.floor(mode)
    if profile.sirenModes[mode] then return mode end
    return 1
end

function ForgeSiren.nextMode(profile, current, direction)
    local count = #profile.sirenModes
    if count == 0 then return 0 end
    return ((ForgeSiren.mode(profile, current) - 1 + direction) % count) + 1
end

-- Shared schema only; permission, persistence and application are server-owned.
function ForgeSiren.validateMegaphoneSettings(value, maxRange)
    if type(value) ~= 'table' then return end
    local result = {}
    local allowed = { enabled = true, monitorEnabled = true, effectEnabled = true,
        range = true, monitorVolume = true, listenerVolume = true, farVolume = true }
    for key in pairs(value) do if not allowed[key] then return end end
    for _, key in ipairs({ 'enabled', 'monitorEnabled', 'effectEnabled' }) do
        if type(value[key]) ~= 'boolean' then return end
        result[key] = value[key]
    end
    for _, key in ipairs({ 'range', 'monitorVolume', 'listenerVolume', 'farVolume' }) do
        local number = value[key]
        local minimum, maximum = key == 'range' and 1 or 0, key == 'range' and maxRange or 100
        if type(number) ~= 'number' or number ~= number or number % 1 ~= 0
            or number < minimum or number > maximum then return end
        result[key] = number
    end
    if result.farVolume > result.listenerVolume then return end
    return result
end

function ForgeSiren.megaphoneDefaults(maxRange)
    local settings = config.megaphone or {}
    local function number(value, fallback, minimum, maximum)
        if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then value = fallback end
        return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
    end
    local volume = number(type(settings.volume) == 'number' and settings.volume * 100, 100, 0, 100)
    return {
        enabled = settings.enabled ~= false, monitorEnabled = settings.monitorEnabled ~= false,
        effectEnabled = settings.effectEnabled ~= false,
        range = number(settings.range, 35, 1, maxRange),
        monitorVolume = number(settings.monitorVolume, 30, 0, 100),
        listenerVolume = volume, farVolume = number(type(settings.farVolume) == 'number' and settings.farVolume * 100, 25, 0, volume),
    }
end
