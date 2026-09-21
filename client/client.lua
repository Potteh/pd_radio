local radioOpen        = false
local radioPowered     = false
local currentChannel   = nil
local isTransmitting   = false
local batteryPct       = 100
local batteryTimer     = nil

-- ==================================================================
-- HELPERS
-- ==================================================================

local function notify(msg)
    -- Replace with your server's notification system if you have one
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function getChannelById(id)
    for _, c in ipairs(Config.Channels) do
        if c.id == id then return c end
    end
    return nil
end

-- ==================================================================
-- VOICE INTEGRATION
-- Every actual voice-plugin call lives in this block. If you're not
-- running pma-voice, this is the only section you need to touch.
-- ==================================================================

local function voice_JoinChannel(channelId)
    if Config.VoiceResource == 'pma-voice' then
        -- pma-voice radio channels are numeric; 0 = no channel
        exports['pma-voice']:setRadioChannel(channelId)
    end
    -- else: add your voice resource's join call here
end

local function voice_LeaveChannel()
    if Config.VoiceResource == 'pma-voice' then
        exports['pma-voice']:setRadioChannel(0)
    end
end

local function voice_SetTransmitting(state)
    isTransmitting = state
    SendNUIMessage({ action = 'setTransmitting', state = state })
end

-- Let pma-voice handle the actual radio transmission. Its +radiotalk /
-- -radiotalk commands update Mumble voice targets and also play pma-voice's
-- built-in mic click/squelch sounds.
local function voice_StartRadioTalk()
    if Config.VoiceResource == 'pma-voice' then
        ExecuteCommand('+radiotalk')
    end
end

local function voice_StopRadioTalk()
    if Config.VoiceResource == 'pma-voice' then
        ExecuteCommand('-radiotalk')
    end
end

CreateThread(function()
    Wait(1000)
    if Config.VoiceResource == 'pma-voice' and GetResourceState('pma-voice') == 'started' then
        if Config.RadioClickOnVolume then
            exports['pma-voice']:setMicClickOnVolume(Config.RadioClickOnVolume)
        end
        if Config.RadioClickOffVolume then
            exports['pma-voice']:setMicClickOffVolume(Config.RadioClickOffVolume)
        end
    end
end)

-- ==================================================================
-- RADIO POWER / BATTERY
-- ==================================================================

local function stopBatteryDrain()
    if batteryTimer then
        batteryTimer = nil
    end
end

local function startBatteryDrain()
    if Config.BatteryLifeMinutes <= 0 then return end
    batteryTimer = true
    CreateThread(function()
        local drainPerTick = 100 / (Config.BatteryLifeMinutes * 60)
        while batteryTimer do
            Wait(1000)
            if radioPowered then
                batteryPct = math.max(0, batteryPct - drainPerTick)
                SendNUIMessage({ action = 'setBattery', value = math.floor(batteryPct) })
                if batteryPct <= 0 then
                    notify('Your radio battery has died.')
                    TriggerEvent('pd_radio:powerOff')
                end
            end
        end
    end)
end

local function powerOn()
    radioPowered = true
    batteryPct = batteryPct == 0 and 100 or batteryPct
    SendNUIMessage({ action = 'powerState', state = true })
    startBatteryDrain()
end

local function powerOff()
    radioPowered = false
    if currentChannel then
        voice_LeaveChannel()
        TriggerServerEvent('pd_radio:leaveChannel')
        currentChannel = nil
    end
    SendNUIMessage({ action = 'clearReceiving' })
    SendNUIMessage({ action = 'powerState', state = false })
    stopBatteryDrain()
end

RegisterNetEvent('pd_radio:powerOff', powerOff)

-- ==================================================================
-- CHANNEL MANAGEMENT
-- ==================================================================

local function setChannel(channelId)
    local chan = getChannelById(channelId)
    if not chan then return end

    QBCore_CheckJob = nil -- placeholder no-op, framework hook lives server-side

    TriggerServerEvent('pd_radio:requestChannel', channelId)
end

RegisterNetEvent('pd_radio:channelDenied', function(reason)
    notify('Radio: access denied (' .. (reason or 'restricted channel') .. ')')
end)

RegisterNetEvent('pd_radio:channelGranted', function(channelId)
    local chan = getChannelById(channelId)
    if not chan then return end
    currentChannel = channelId
    SendNUIMessage({ action = 'clearReceiving' })
    voice_JoinChannel(channelId)
    SendNUIMessage({
        action = 'setChannel',
        id = chan.id,
        name = chan.name,
        freq = chan.freq,
        encrypted = chan.encrypted
    })
end)

local function cycleChannel(direction)
    if not radioPowered then return end
    local idx = 1
    for i, c in ipairs(Config.Channels) do
        if currentChannel == c.id then idx = i break end
    end
    local newIdx = idx + direction
    if newIdx < 1 then newIdx = #Config.Channels end
    if newIdx > #Config.Channels then newIdx = 1 end
    setChannel(Config.Channels[newIdx].id)
end

-- ==================================================================
-- UI OPEN / CLOSE
-- ==================================================================

local function openRadio()
    if radioOpen then return end
    radioOpen = true
    SetNuiFocus(false, false) -- keep game controls usable; this is a HUD-style radio, not a menu
    SendNUIMessage({
        action = 'open',
        channels = Config.Channels,
        battery = math.floor(batteryPct),
        powered = radioPowered
    })
end

local function closeRadio()
    radioOpen = false
    SendNUIMessage({ action = 'close' })
end

RegisterCommand('toggleradio', function()
    if radioOpen then closeRadio() else openRadio() end
end, false)

RegisterKeyMapping('toggleradio', 'Toggle Police Radio', 'keyboard', Config.OpenRadioKey)

RegisterCommand('radiopower', function()
    if not radioOpen then return end
    if radioPowered then powerOff() else powerOn() end
end, false)
RegisterKeyMapping('radiopower', 'Radio Power On/Off', 'keyboard', 'F6')

RegisterCommand('radiochanup', function() cycleChannel(1) end, false)
RegisterCommand('radiochandown', function() cycleChannel(-1) end, false)
RegisterKeyMapping('radiochanup', 'Radio Channel Up', 'keyboard', Config.ChannelUpKey)
RegisterKeyMapping('radiochandown', 'Radio Channel Down', 'keyboard', Config.ChannelDownKey)

-- ==================================================================
-- PUSH TO TALK
-- ==================================================================

RegisterCommand('+radioptt', function()
    if not radioPowered or not currentChannel then return end
    voice_StartRadioTalk()
    if Config.CustomPTTSounds then
        SendNUIMessage({ action = 'playPTTSound', sound = 'on', volume = Config.CustomPTTVolume or 0.55 })
    end
    voice_SetTransmitting(true)

    -- Show our own transmission in the RX display as well.
    local myServerId = GetPlayerServerId(PlayerId())
    local myName = GetPlayerName(PlayerId()) or ('UNIT ' .. tostring(myServerId))
    SendNUIMessage({
        action = 'setReceiving',
        serverId = myServerId,
        name = myName,
        state = true
    })

    TriggerServerEvent('pd_radio:startTalking', currentChannel)
end, false)

RegisterCommand('-radioptt', function()
    if not isTransmitting then return end
    voice_StopRadioTalk()
    if Config.CustomPTTSounds then
        SendNUIMessage({ action = 'playPTTSound', sound = 'off', volume = Config.CustomPTTVolume or 0.55 })
    end
    voice_SetTransmitting(false)

    -- Remove only our own entry from RX; any other active receiver stays shown.
    SendNUIMessage({
        action = 'setReceiving',
        serverId = GetPlayerServerId(PlayerId()),
        state = false
    })

    TriggerServerEvent('pd_radio:stopTalking', currentChannel)
end, false)

RegisterKeyMapping('+radioptt', 'Radio Push-To-Talk', 'keyboard', Config.PTTKey)


-- RX is driven directly by pma-voice's own synchronized talking event.
-- This is more reliable than maintaining a second radio-member table in pd_radio.
RegisterNetEvent('pma-voice:setTalkingOnRadio', function(serverId, state)
    serverId = tonumber(serverId)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    if not radioPowered or not currentChannel then return end

    local displayName = ('UNIT %s'):format(serverId)
    local playerIndex = GetPlayerFromServerId(serverId)
    if playerIndex and playerIndex ~= -1 then
        local name = GetPlayerName(playerIndex)
        if name and name ~= '' then displayName = name end
    end

    SendNUIMessage({
        action = 'setReceiving',
        serverId = serverId,
        name = displayName,
        state = state == true
    })
end)

-- Legacy fallback for pd_radio's own server relay.
RegisterNetEvent('pd_radio:rxState', function(serverId, displayName, state)
    if not radioPowered or not currentChannel then return end
    SendNUIMessage({
        action = 'setReceiving',
        serverId = serverId,
        name = displayName or ('UNIT ' .. tostring(serverId)),
        state = state
    })
end)

-- Server tells nearby players (not on channel) that radio chatter is
-- bleeding out of someone's speaker, for the "hear it from their hip" effect
RegisterNetEvent('pd_radio:speakerBleed', function(sourcePed, state)
    local ent = NetworkGetEntityFromNetworkId(sourcePed)
    if not DoesEntityExist(ent) then return end
    -- Hook: lower this player's own voice / play a small radio-chirp sound
    -- via your voice resource's proximity audio if desired.
end)

-- ==================================================================
-- NUI CALLBACKS (from the HTML UI)
-- ==================================================================

RegisterNUICallback('close', function(_, cb)
    closeRadio()
    cb('ok')
end)

RegisterNUICallback('power', function(_, cb)
    if radioPowered then powerOff() else powerOn() end
    cb('ok')
end)

RegisterNUICallback('selectChannel', function(data, cb)
    if radioPowered then setChannel(tonumber(data.id)) end
    cb('ok')
end)

RegisterNUICallback('volume', function(data, cb)
    -- Wire this to your voice resource's radio volume export if supported
    cb('ok')
end)
