Config = {}

-- =========================================================
-- VOICE INTEGRATION
-- =========================================================
-- This script talks to pma-voice by default (the most common
-- FiveM voice plugin with built-in radio support). If you run
-- a different voice resource (saltychat, tokovoip, mumble-voip)
-- swap the calls inside client/client.lua under the
-- "VOICE INTEGRATION" section — every call is isolated there.
Config.VoiceResource = 'pma-voice'

-- =========================================================
-- KEYBINDS
-- =========================================================
Config.OpenRadioKey   = 'M'          -- toggle the radio UI
Config.PTTKey         = 'LMENU'      -- push-to-talk (default: left alt)

-- pma-voice's built-in radio mic click / squelch volume (0-100).
-- These sounds play when radio transmission starts and stops.
Config.RadioClickOnVolume  = 60
Config.RadioClickOffVolume = 60

-- Custom Motorola-style PTT tones generated for this resource.
-- Set false to go back to pma-voice's built-in mic clicks.
Config.CustomPTTSounds = false
Config.CustomPTTVolume = 0.55
Config.ChannelUpKey   = 'PAGEUP'
Config.ChannelDownKey = 'PAGEDOWN'

-- =========================================================
-- JOBS ALLOWED TO USE THE RADIO
-- =========================================================
-- Framework-agnostic: implement GetPlayerJob() server-side
-- (server/server.lua) to match your framework (ESX/QBCore/custom).
Config.AllowedJobs = {
    ['police']    = true,
    ['sheriff']   = true,
    ['ambulance'] = true,
    ['dispatch']  = true,
}

-- =========================================================
-- CHANNELS
-- job = nil means anyone with radio access can join
-- encrypted = true just flags it visually + can be gated by job
-- =========================================================
Config.Channels = {
    { id = 1,  name = 'DISPATCH',   freq = '155.475', job = nil,          encrypted = false },
    { id = 2,  name = 'CHAN 2',     freq = '155.610', job = nil,          encrypted = false },
    { id = 3,  name = 'CHAN 3',     freq = '155.730', job = nil,          encrypted = false },
    { id = 4,  name = 'SWAT',       freq = '156.045', job = 'police',     encrypted = true  },
    { id = 5,  name = 'EMS-1',      freq = '155.340', job = 'ambulance',  encrypted = false },
    { id = 6,  name = 'FED',        freq = '159.810', job = 'police',     encrypted = true  },
    { id = 7,  name = 'SUPERVISOR', freq = '154.920', job = 'police',     encrypted = true  },
    { id = 8,  name = 'TAC-1',      freq = '158.730', job = 'police',     encrypted = false },
}

-- Radio battery drains over real time while powered on (minutes).
-- Set to 0 to disable battery drain entirely.
Config.BatteryLifeMinutes = 90

-- Range (in game units) other players must be within to hear you
-- WITHOUT being on the radio channel (i.e. face-to-face radio chatter
-- bleeding out of the speaker). Set to 0 to disable.
Config.SpeakerBleedRange = 3.0
