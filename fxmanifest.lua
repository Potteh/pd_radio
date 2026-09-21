fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pd_radio'
author 'you'
description 'Motorola-style police radio with in-game voice integration (pma-voice)'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/*.png'
}
