fx_version 'cerulean'
game 'gta5'
use_experimental_fxv2_oal 'yes'
author 'Forge // AvarianKnight // FjamZoo'
description 'Forge Siren - PR Bridge e controlador retro em Svelte'
version '2.0.0'

lua54 'yes'

dependencies { 'pr_bridge', 'pma-voice' }

shared_scripts {
    '@pr_bridge/init.lua',
    'shared.lua',
}

client_scripts { 'megaphone_client.lua', 'client.lua' }

server_scripts { 'server.lua', 'admin_server.lua', 'megaphone_server.lua' }

ui_page 'web/dist/index.html'

files {
    'config.lua',
    'web/dist/index.html',
    'web/dist/assets/*',
}
