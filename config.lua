return {
    ---@class audioConfig
    ---@field audioName string
    ---@field audioRef? string the audioBank to use, if for example you use custom serverside sirens

    ---@class SirenConfigTable
    ---@field models? table<number, boolean>
    ---@field sirenModes table<number, audioConfig> the key is the siren mode
    ---@field horn? audioConfig

    controls = {
        policeLights = 'Q',
        policeHorn   = 'E',
        sirenToggle  = 'LMENU',
        sirenCycle   = 'R',
        panel        = 'LCONTROL', -- Ctrl esquerdo: cursor; remapeavel nas teclas do FiveM.
        megaphone    = 'F2', -- Segure para falar (veiculo ou item equipado).
    },

    sirenShutOff = true,          -- Set to true if you want the siren to automatically shut off when the player exits the vehicle

    -- Preferencias iniciais. Cada jogador pode altera-las e salvar 3 presets
    -- no painel; os dados ficam no KVP local deste recurso.
    preferences = {
        keepLights = true,
        keepSound = false,
        primaryMode = 1,
        scale = 1.0,
    },

    ui = {
        command = 'sirene',
        right = 24, -- pixels da borda direita
        bottom = 32,
    },

    access = {
        classes = { [18] = true }, -- viaturas
        models = { [joaat('polmav')] = true, [joaat('policeb')] = true }, -- aeronaves/modelos especiais
    },

    admin = { ace = 'forge-siren.admin', parentAce = 'forge-core.admin' },

    megaphone = {
        enabled = true,
        item = 'megaphone', -- Nao consumido; usar novamente guarda o equipamento.
        range = 35.0, -- metros; limitado tambem pelo PMA Voice.
        volume = 1.0,
        farVolume = 0.25, -- volume no limite do alcance (nunca maior que volume)
        monitorEnabled = true,
        monitorVolume = 30, -- porcentagem; retorno local independente
        effectEnabled = true, -- efeito radio/megafone no retorno e nos ouvintes
        -- O painel ADMIN salva estes valores globalmente no KVP do servidor.
        -- Catalogo do PR Bridge aceita a categoria emergency. Modelos fora
        -- desse catalogo devem ser autorizados aqui (validacao no servidor).
        models = {
            [joaat('police')] = true, [joaat('police2')] = true,
            [joaat('police3')] = true, [joaat('police4')] = true,
            [joaat('policeb')] = true, [joaat('policet')] = true,
            [joaat('sheriff')] = true, [joaat('sheriff2')] = true,
            [joaat('fbi')] = true, [joaat('fbi2')] = true,
            [joaat('firetruk')] = true, [joaat('ambulance')] = true,
            [joaat('riot')] = true, [joaat('riot2')] = true,
            [joaat('pranger')] = true, [joaat('polmav')] = true,
        },
        prop = 'prop_megaphone_01',
        animation = { dict = 'amb@world_human_mobile_film_shocking@female@base', clip = 'base',
            bone = 28422, position = { 0.0, 0.0, 0.0 }, rotation = { 0.0, 0.0, 80.0 } },
    },

    performance = {
        discoveryInterval = 3000, -- recuperacao de veiculos que entram no streaming
        discoveryBatch = 32,      -- limita trabalho de descoberta por frame
        maintenanceInterval = 1000, -- apenas veiculos ja conhecidos
        seatWatchdogInterval = 1000, -- reserva caso um evento de cache seja perdido
    },

    -- Nome mostrado no visor; grupos de sons podem definir label em cada modo.
    modeLabels = { 'WAIL', 'YELP', 'PRIORITY' },

    disableDamagedSirens = false, -- Set to true if you want to disable the damaged siren
    useEngineHealth = false,      -- Determine wether to use engine health over body health for siren damage
    damageThreshold = 300,        -- If the vehicle's health is below this value, the siren will be considered damaged

    ---@type table<number, SirenConfigTable>
    --- Configure what siren sounds to use for a specific model and siren mode
    sirens = {
        --base
        {
            sirenModes = {
                { audioName = 'VEHICLES_HORNS_SIREN_1' },
                { audioName = 'VEHICLES_HORNS_SIREN_2' },
                { audioName = 'VEHICLES_HORNS_POLICE_WARNING' },
            },

            horn = {
                audioName = 'SIRENS_AIRHORN'
            }
        },

        --fire
        {
            sirenModes = {
                { audioName = 'RESIDENT_VEHICLES_SIREN_FIRETRUCK_QUICK_01', label = 'YELP' },
                { audioName = 'RESIDENT_VEHICLES_SIREN_FIRETRUCK_WAIL_01', label = 'WAIL' },
                { audioName = 'VEHICLES_HORNS_AMBULANCE_WARNING' }
            },

            horn = {
                audioName = 'VEHICLES_HORNS_FIRETRUCK_WARNING'
            },

            models = {
                [joaat('FIRETRUK')] = true,
                [joaat('ambulance')] = true,
            }
        },

        --unmarked
        {
            sirenModes = {
                { audioName = 'RESIDENT_VEHICLES_SIREN_WAIL_02' },
                { audioName = 'RESIDENT_VEHICLES_SIREN_QUICK_02' }
            },

            models = {
                [joaat('fbi')] = true,
                [joaat('fbi2')] = true,
                [joaat('police4')] = true,
            }
        },

        --bikes
        {
            sirenModes = {
                { audioName = 'RESIDENT_VEHICLES_SIREN_WAIL_03' },
                { audioName = 'RESIDENT_VEHICLES_SIREN_QUICK_03' }
            },

            models = {
                [joaat('policeb')] = true
            }
        },
    }
}
