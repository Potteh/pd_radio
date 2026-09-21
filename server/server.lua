-- ==================================================================
-- FRAMEWORK HOOK
-- Replace the body of this function to match your framework.
-- It must return a job name string (e.g. 'police') for the given
-- server id, or nil if the player has no job / isn't in a framework.
-- ==================================================================
local function GetPlayerJob(src)
    -- ---- QBCore example ----
    -- local QBCore = exports['qb-core']:GetCoreObject()
    -- local Player = QBCore.Functions.GetPlayer(src)
    -- return Player and Player.PlayerData.job.name or nil

    -- ---- ESX example ----
    -- local ESX = exports['es_extended']:getSharedObject()
    -- local xPlayer = ESX.GetPlayerFromId(src)
    -- return xPlayer and xPlayer.job.name or nil

    -- Default fallback: everyone can use the radio (no job gating).
    -- Swap this out before going live with a real framework check.
    return 'police'
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

-- ==================================================================
-- SPEAKER BLEED (optional flavor: nearby non-channel players hear
-- radio chatter faintly coming from the speaker on someone's belt)
-- ==================================================================

RegisterNetEvent('pd_radio:startTalking', function(channelId)
    local src = source
    if Config.SpeakerBleedRange <= 0 then return end

    local list = playersOnChannel[tonumber(channelId)]
    if not list then return end

    local srcNet = NetworkGetNetworkIdFromEntity(GetPlayerPed(src))
    local displayName = GetPlayerName(src) or ('UNIT ' .. tostring(src))
    for target, _ in pairs(list) do
        if target ~= src then
            TriggerClientEvent('pd_radio:rxState', target, src, displayName, true)
            -- The actual "am I close enough" distance check should be
            -- done client-side (or here with player coords) before
            -- playing any bleed audio; this just relays the event.
            TriggerClientEvent('pd_radio:speakerBleed', target, srcNet, true)
        end
    end
end)

RegisterNetEvent('pd_radio:stopTalking', function(channelId)
    local src = source
    local list = playersOnChannel[tonumber(channelId)]
    if not list then return end

    local srcNet = NetworkGetNetworkIdFromEntity(GetPlayerPed(src))
    local displayName = GetPlayerName(src) or ('UNIT ' .. tostring(src))
    for target, _ in pairs(list) do
        if target ~= src then
            TriggerClientEvent('pd_radio:speakerBleed', target, srcNet, false)
        end
    end
end)
