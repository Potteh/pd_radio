-- ==================================================================
-- FRAMEWORK HOOK
-- Replace the body of this function to match your framework.
-- It must return a job name string (e.g. 'police') for the given
-- server id, or nil if the player has no job / isn't in a framework.
-- ==================================================================
local QBCore = exports['qb-core']:GetCoreObject()

local function GetPlayerJob(src)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
end

local function hasRadioAccess(src)
    local job = GetPlayerJob(src)
    return job ~= nil and Config.AllowedJobs[job] == true, job
end

local function getChannelById(id)
    for _, c in ipairs(Config.Channels) do
        if c.id == id then return c end
    end
    return nil
end

-- playersOnChannel[channelId] = { [src] = true, ... }
local playersOnChannel = {}

local function removeFromAllChannels(src)
    for chanId, list in pairs(playersOnChannel) do
        list[src] = nil
    end
end

RegisterNetEvent('pd_radio:requestChannel', function(channelId)
    local src = source
    local ok, job = hasRadioAccess(src)
    if not ok then
        TriggerClientEvent('pd_radio:channelDenied', src, 'no radio access')
        return
    end

    local chan = getChannelById(tonumber(channelId))
    if not chan then
        TriggerClientEvent('pd_radio:channelDenied', src, 'unknown channel')
        return
    end

    if chan.job and chan.job ~= job then
        TriggerClientEvent('pd_radio:channelDenied', src, 'restricted channel')
        return
    end

    removeFromAllChannels(src)
    playersOnChannel[chan.id] = playersOnChannel[chan.id] or {}
    playersOnChannel[chan.id][src] = true

    TriggerClientEvent('pd_radio:channelGranted', src, chan.id)
end)

AddEventHandler('playerDropped', function()
    removeFromAllChannels(source)
end)
RegisterNetEvent('pd_radio:leaveChannel', function()
    local src = source
    removeFromAllChannels(src)
end)



-- Resolve a QBCore character name for the RX display.
-- Falls back to the FiveM name only if QBCore/character data is unavailable.
local function GetCharacterDisplayName(src)
    local ok, QBCore = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)
    if ok and QBCore then
        local Player = QBCore.Functions.GetPlayer(tonumber(src))
        local pdata = Player and Player.PlayerData
        local charinfo = pdata and pdata.charinfo
        if charinfo then
            local first = tostring(charinfo.firstname or '')
            local last = tostring(charinfo.lastname or '')
            local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
            local metadata = pdata.metadata or {}
            local callsign = tostring(metadata.callsign or ''):gsub('^%s+', ''):gsub('%s+$', '')
            -- Some QBCore/MDT setups store a placeholder instead of an empty callsign.
            -- Treat those placeholders as unset so the radio only shows the character name.
            local normalizedCallsign = callsign:lower():gsub('[%s%-%_]+', '')
            if normalizedCallsign == 'nocallsign' or normalizedCallsign == 'none' or normalizedCallsign == 'n/a' then
                callsign = ''
            end
            if full ~= '' and callsign ~= '' then return callsign .. ' | ' .. full end
            if full ~= '' then return full end
            if callsign ~= '' then return callsign end
        end
    end
    return GetPlayerName(tonumber(src)) or ('UNIT ' .. tostring(src))
end

RegisterNetEvent('pd_radio:requestRxName', function(talkingServerId, state)
    local requester = source
    talkingServerId = tonumber(talkingServerId)
    if not talkingServerId then return end
    TriggerClientEvent('pd_radio:resolvedRxName', requester, talkingServerId, GetCharacterDisplayName(talkingServerId), state == true)
end)

-- ==================================================================
-- SPEAKER BLEED (optional flavor: nearby non-channel players hear
-- radio chatter faintly coming from the speaker on someone's belt)
-- ==================================================================

RegisterNetEvent('pd_radio:startTalking', function(channelId)
    local src = source
    local list = playersOnChannel[tonumber(channelId)]
    if not list then return end

    local srcNet = NetworkGetNetworkIdFromEntity(GetPlayerPed(src))
    local displayName = GetCharacterDisplayName(src)
    for target, _ in pairs(list) do
        if target ~= src then
            TriggerClientEvent('pd_radio:rxState', target, src, displayName, true)
            -- The actual "am I close enough" distance check should be
            -- done client-side (or here with player coords) before
            -- playing any bleed audio; this just relays the event.
            if Config.SpeakerBleedRange > 0 then
                TriggerClientEvent('pd_radio:speakerBleed', target, srcNet, true)
            end
        end
    end
end)

RegisterNetEvent('pd_radio:stopTalking', function(channelId)
    local src = source
    local list = playersOnChannel[tonumber(channelId)]
    if not list then return end

    local srcNet = NetworkGetNetworkIdFromEntity(GetPlayerPed(src))
    local displayName = GetCharacterDisplayName(src)
    for target, _ in pairs(list) do
        if target ~= src then
            TriggerClientEvent('pd_radio:rxState', target, src, displayName, false)
            if Config.SpeakerBleedRange > 0 then
                TriggerClientEvent('pd_radio:speakerBleed', target, srcNet, false)
            end
        end
    end
end)

-- ==================================================================
-- EMERGENCY / PANIC ALERT
-- Broadcasts to every player currently registered on a pd_radio channel.
-- ==================================================================
RegisterNetEvent('pd_radio:panic', function()
    local src = source
    local ok = hasRadioAccess(src)
    if not ok then return end

    local senderOnRadio = false
    for _, list in pairs(playersOnChannel) do
        if list[src] then senderOnRadio = true break end
    end
    if not senderOnRadio then return end

    local displayName = GetCharacterDisplayName(src)
    local sent = {}
    for _, list in pairs(playersOnChannel) do
        for target, _ in pairs(list) do
            if not sent[target] then
                sent[target] = true
                TriggerClientEvent('pd_radio:panicAlert', target, src, displayName)
            end
        end
    end
end)
