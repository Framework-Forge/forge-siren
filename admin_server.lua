-- Global megaphone policy. No player can write it through a cache/state bag.
local kvpKey = 'forge_siren:megaphone:global:v1'
local maxRange = math.max(1, math.min(200, GetConvarInt('voice_megaphoneMaxRange', 50)))
local current = ForgeSiren.megaphoneDefaults(maxRange)
local revision, epoch, lastSave = 1, tostring(os.time()) .. ':' .. GetGameTimer(), {}
local saved = GetResourceKvpString(kvpKey)
if saved then
    local ok, value = pcall(json.decode, saved)
    local settings = ok and type(value) == 'table' and value.version == 1
        and ForgeSiren.validateMegaphoneSettings(value.settings, 200)
    if settings then
        settings.range = math.min(settings.range, maxRange)
        current = settings
    end
end

local function copySettings()
    local result = {}; for key, value in pairs(current) do result[key] = value end
    return result
end
ForgeSiren.getMegaphoneSettings = copySettings

local function isAdmin(player)
    player = tonumber(player)
    if not player or player < 1 or not GetPlayerName(player) then return false end
    local admin, ace = ForgeSiren.config.admin or {}, pr_lib.ace
    if not ace or type(ace.isPlayerAceAllowed) ~= 'function' then return false end
    for _, permission in ipairs({ admin.ace or 'forge-siren.admin', admin.parentAce or 'forge-core.admin' }) do
        local ok, allowed = pcall(ace.isPlayerAceAllowed, player, permission)
        if ok and allowed == true then return true end
    end
    return false
end

local function snapshot(player)
    return { ok = true, allowed = isAdmin(player), settings = copySettings(),
        maxRange = maxRange, revision = revision, epoch = epoch }
end

local function apply()
    -- Replicated convars hydrate late joiners and PMA restarts without new loops.
    -- voice_megaphoneMaxRange remains the operator's independent hard ceiling.
    SetConvarReplicated('voice_enableMegaphone', current.enabled and '1' or '0')
    SetConvarReplicated('voice_megaphoneRange', tostring(current.range))
    SetConvarReplicated('voice_megaphoneListenerVolume', tostring(current.listenerVolume))
    SetConvarReplicated('voice_megaphoneFarVolume', tostring(current.farVolume))
    SetConvarReplicated('voice_megaphoneMonitor', current.monitorEnabled and '1' or '0')
    SetConvarReplicated('voice_megaphoneMonitorVolume', tostring(current.monitorVolume))
    SetConvarReplicated('voice_megaphoneRadioEffect', current.effectEnabled and '1' or '0')
    TriggerEvent('forge-siren:server:megaphoneConfigChanged')
    TriggerClientEvent('forge-siren:client:megaphoneConfigChanged', -1)
end

pr_lib.callback.register('forge-siren:server:adminGetMegaphone', snapshot)
pr_lib.callback.register('forge-siren:server:adminSaveMegaphone', function(player, input)
    if not isAdmin(player) then return { ok = false, error = 'Sem permissao de administrador.' } end
    if type(input) ~= 'table' or input.revision ~= revision or input.epoch ~= epoch then
        return { ok = false, error = 'A configuracao mudou. Recarregue antes de salvar.' }
    end
    local settings = ForgeSiren.validateMegaphoneSettings(input.settings, maxRange)
    if not settings then return { ok = false, error = 'Valores invalidos ou volume distante maior que o volume proximo.' } end
    local now = GetGameTimer()
    if now - (lastSave[player] or -1000) < 750 then return { ok = false, error = 'Aguarde antes de salvar novamente.' } end
    lastSave[player] = now
    local encoded = json.encode({ version = 1, settings = settings })
    local ok = pcall(SetResourceKvp, kvpKey, encoded)
    if not ok or GetResourceKvpString(kvpKey) ~= encoded then
        return { ok = false, error = 'Nao foi possivel salvar a configuracao no servidor.' }
    end
    current, revision = settings, revision + 1
    apply()
    print(('[Forge Siren] Configuracao global de megafone salva pelo jogador %s.'):format(player))
    return snapshot(player)
end)
AddEventHandler('playerDropped', function() lastSave[source] = nil end)
apply()
