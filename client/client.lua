local radioOpen        = false
local radioPowered     = false
local currentChannel   = nil
local isTransmitting   = false
local batteryPct       = 100
local batteryTimer     = nil
local ownRadioDisplayName = nil
local radioVolume      = tonumber(GetResourceKvpString('pd_radio_volume')) or (Config.DefaultRadioVolume or 60)
local radioMuted       = false
local preMuteVolume    = radioVolume > 0 and radioVolume or (Config.DefaultRadioVolume or 60)
local savedChannel     = tonumber(GetResourceKvpString('pd_radio_channel'))
local setChannel
local QBCore = exports['qb-core']:GetCoreObject()
local hasAllowedRadioJob = false

local function refreshRadioJobAccess()
    local data = QBCore.Functions.GetPlayerData()
    local jobName = data and data.job and data.job.name or nil
    hasAllowedRadioJob = jobName ~= nil and Config.AllowedJobs[jobName] == true
    return hasAllowedRadioJob
end

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


CreateThread(function()
    Wait(1500)
    TriggerServerEvent('pd_radio:requestRxName', GetPlayerServerId(PlayerId()), false)
end)

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
    SendNUIMessage({ action = 'setTransmitting', state = state, name = ownRadioDisplayName })
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

local function voice_SetRadioVolume(volume)
    volume = math.max(0, math.min(100, math.floor(tonumber(volume) or 0)))
    if Config.VoiceResource == 'pma-voice' and GetResourceState('pma-voice') == 'started' then
        exports['pma-voice']:setRadioVolume(volume)
    end
end

local function syncVolumeUI()
    SendNUIMessage({ action = 'setVolume', value = radioVolume, muted = radioMuted })
end

local function applyRadioVolume(volume, persist)
    radioVolume = math.max(0, math.min(100, math.floor(tonumber(volume) or 0)))
    if radioVolume > 0 then preMuteVolume = radioVolume end
    radioMuted = radioVolume == 0
    voice_SetRadioVolume(radioVolume)
    if persist ~= false then SetResourceKvp('pd_radio_volume', tostring(radioVolume)) end
    syncVolumeUI()
end

local function changeRadioVolume(delta)
    local base = radioMuted and preMuteVolume or radioVolume
    applyRadioVolume(base + delta, true)
end

local function toggleRadioMute()
    if radioMuted or radioVolume == 0 then
        applyRadioVolume(math.max(1, preMuteVolume), true)
    else
        preMuteVolume = radioVolume
        applyRadioVolume(0, true)
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
        applyRadioVolume(radioVolume, false)
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
    syncVolumeUI()
    startBatteryDrain()
    if savedChannel and getChannelById(savedChannel) then
        SetTimeout(100, function()
            if radioPowered and not currentChannel then setChannel(savedChannel) end
        end)
    end
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

-- Keep access synchronized with QBCore job changes. If an officer changes
-- away from an allowed radio job, immediately disconnect and close the radio.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshRadioJobAccess()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    local jobName = job and job.name or nil
    hasAllowedRadioJob = jobName ~= nil and Config.AllowedJobs[jobName] == true
    if not hasAllowedRadioJob then
        if isTransmitting then
            voice_StopRadioTalk()
            voice_SetTransmitting(false)
        end
        powerOff()
        if radioOpen then
            radioOpen = false
            SendNUIMessage({ action = 'close' })
        end
        notify('Emergency services radio access removed.')
    end
end)

CreateThread(function()
    Wait(1000)
    refreshRadioJobAccess()
end)

-- ==================================================================
-- CHANNEL MANAGEMENT
-- ==================================================================

setChannel = function(channelId)
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
    savedChannel = channelId
    SetResourceKvp('pd_radio_channel', tostring(channelId))
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
    if not refreshRadioJobAccess() then
        notify('Radio access is restricted to Police and EMS.')
        return
    end
    if radioOpen then return end
    radioOpen = true
    SetNuiFocus(false, false) -- keep game controls usable; this is a HUD-style radio, not a menu
    SendNUIMessage({
        action = 'open',
        channels = Config.Channels,
        battery = math.floor(batteryPct),
        powered = radioPowered,
        currentChannel = currentChannel,
        volume = radioVolume,
        muted = radioMuted
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
    if not refreshRadioJobAccess() then return end
    if not radioOpen then return end
    if radioPowered then powerOff() else powerOn() end
end, false)
RegisterKeyMapping('radiopower', 'Radio Power On/Off', 'keyboard', 'F6')

RegisterCommand('radiochanup', function() cycleChannel(1) end, false)
RegisterCommand('radiochandown', function() cycleChannel(-1) end, false)
RegisterKeyMapping('radiochanup', 'Radio Channel Up', 'keyboard', Config.ChannelUpKey)
RegisterKeyMapping('radiochandown', 'Radio Channel Down', 'keyboard', Config.ChannelDownKey)

-- ==================================================================
-- RADIO VOLUME / MUTE
-- Uses pma-voice's radio-only volume export; proximity voice is untouched.
-- ==================================================================

RegisterCommand('radiovoldown', function() changeRadioVolume(-(Config.RadioVolumeStep or 10)) end, false)
RegisterCommand('radiovolup', function() changeRadioVolume(Config.RadioVolumeStep or 10) end, false)
RegisterCommand('radiomute', toggleRadioMute, false)
RegisterKeyMapping('radiovoldown', 'Police Radio Volume Down', 'keyboard', Config.RadioVolumeDownKey or 'F7')
RegisterKeyMapping('radiovolup', 'Police Radio Volume Up', 'keyboard', Config.RadioVolumeUpKey or 'F8')
RegisterKeyMapping('radiomute', 'Police Radio Mute / Unmute', 'keyboard', Config.RadioMuteKey or 'F9')

-- ==================================================================
-- PUSH TO TALK
-- ==================================================================

-- Radio animation is intentionally separate from voice/PTT logic.
-- Failure to load/play the animation will never block transmission.
local radioAnimPlaying = false

local function startRadioAnimation()
    if Config.RadioAnimation == false or radioAnimPlaying then return end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end

    local dict = Config.RadioAnimDict or 'random@arrests'
    local anim = Config.RadioAnimName or 'generic_radio_chatter'

    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(10)
    end
    if not HasAnimDictLoaded(dict) then return end

    TaskPlayAnim(ped, dict, anim, 3.0, -3.0, -1, Config.RadioAnimFlag or 49, 0.0, false, false, false)
    radioAnimPlaying = true
end

local function stopRadioAnimation()
    if not radioAnimPlaying then return end
    local ped = PlayerPedId()
    local dict = Config.RadioAnimDict or 'random@arrests'
    local anim = Config.RadioAnimName or 'generic_radio_chatter'
    StopAnimTask(ped, dict, anim, 2.0)
    radioAnimPlaying = false
end

-- IMPORTANT: pma-voice owns the radio PTT keybind.
-- Do not register a second LMENU/+radioptt mapping here: two resources bound to
-- the same key can race each other and leave pma-voice's Mumble target in the
-- wrong state. We observe pma-voice:radioActive below for UI/animation only.

-- RX display names are resolved server-side from QBCore character data.
-- This observes pma-voice only; the working PTT/key-up path above is unchanged.
local rxNameCache = {}

local function updateRxWithCharacterName(serverId, state)
    serverId = tonumber(serverId)
    if not serverId then return end

    if state ~= true then
        SendNUIMessage({
            action = 'setReceiving',
            serverId = serverId,
            name = rxNameCache[serverId] or ('UNIT %s'):format(serverId),
            state = false
        })
        return
    end

    if rxNameCache[serverId] then
        SendNUIMessage({
            action = 'setReceiving',
            serverId = serverId,
            name = rxNameCache[serverId],
            state = true
        })
    else
        TriggerServerEvent('pd_radio:requestRxName', serverId, true)
    end
end

RegisterNetEvent('pd_radio:resolvedRxName', function(serverId, displayName, state)
    serverId = tonumber(serverId)
    if not serverId then return end
    if displayName and displayName ~= '' then
        rxNameCache[serverId] = displayName
        if serverId == GetPlayerServerId(PlayerId()) then ownRadioDisplayName = displayName end
    end
    if not radioPowered or not currentChannel then return end
    SendNUIMessage({
        action = 'setReceiving',
        serverId = serverId,
        name = rxNameCache[serverId] or ('UNIT %s'):format(serverId),
        state = state == true
    })
end)

-- pma-voice is the single owner of PTT. Mirror its confirmed transmission
-- state into this resource without starting/stopping voice ourselves.
AddEventHandler('pma-voice:radioActive', function(state)
    if not radioPowered or not currentChannel then return end

    local active = state == true
    voice_SetTransmitting(active)

    if active then
        startRadioAnimation()
        TriggerServerEvent('pd_radio:startTalking', currentChannel)
    else
        stopRadioAnimation()
        TriggerServerEvent('pd_radio:stopTalking', currentChannel)
    end

    updateRxWithCharacterName(GetPlayerServerId(PlayerId()), active)
end)

-- Show other transmitters using their QBCore character names.
RegisterNetEvent('pma-voice:setTalkingOnRadio', function(serverId, state)
    serverId = tonumber(serverId)
    if not serverId or serverId == GetPlayerServerId(PlayerId()) then return end
    if not radioPowered or not currentChannel then return end
    updateRxWithCharacterName(serverId, state == true)
end)

-- Legacy fallback for pd_radio's own server relay. Server now supplies character names too.
RegisterNetEvent('pd_radio:rxState', function(serverId, displayName, state)
    serverId = tonumber(serverId)
    if not serverId or not radioPowered or not currentChannel then return end
    if displayName and displayName ~= '' then rxNameCache[serverId] = displayName end
    SendNUIMessage({
        action = 'setReceiving',
        serverId = serverId,
        name = rxNameCache[serverId] or displayName or ('UNIT ' .. tostring(serverId)),
        state = state == true
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
    if data and data.mute == true then
        toggleRadioMute()
    elseif data and data.value ~= nil then
        applyRadioVolume(tonumber(data.value) or radioVolume, true)
    end
    cb({ ok = true, volume = radioVolume, muted = radioMuted })
end)

-- ==================================================================
-- EMERGENCY / PANIC
-- Does not modify the working PTT path.
-- ==================================================================
local panicCooldown = false

local function triggerPanic()
    if not refreshRadioJobAccess() then return end
    if panicCooldown or not radioPowered or not currentChannel then return end
    panicCooldown = true
    TriggerServerEvent('pd_radio:panic')
    SetTimeout(2500, function() panicCooldown = false end)
end

RegisterCommand('radiopanic', triggerPanic, false)
RegisterKeyMapping('radiopanic', 'Police Radio Emergency / Panic', 'keyboard', Config.EmergencyKey or 'F10')

RegisterNetEvent('pd_radio:panicAlert', function(serverId, displayName)
    if not radioPowered then return end
    PlaySoundFrontend(-1, Config.EmergencySoundName or 'TIMER_STOP', Config.EmergencySoundSet or 'HUD_MINI_GAME_SOUNDSET', true)
    SendNUIMessage({
        action = 'panicAlert',
        serverId = tonumber(serverId),
        name = displayName or ('UNIT ' .. tostring(serverId)),
        duration = Config.EmergencyDuration or 8000
    })
end)

RegisterNUICallback('panic', function(_, cb)
    triggerPanic()
    cb({ ok = true })
end)
