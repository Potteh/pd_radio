# pd_radio — Motorola-style FiveM Police Radio

A HUD-style radio (visually based on a Motorola APX-series portable) with
channel selection, push-to-talk, battery drain, and job-gated encrypted
channels. It integrates with **pma-voice** for actual in-game voice-over-radio
by default.

## Install

1. Drop the `pd_radio` folder into your server's `resources` directory.
2. Add `ensure pd_radio` to your `server.cfg`, **after** your voice resource.
3. Edit `config.lua`:
   - `Config.AllowedJobs` — which jobs can use a radio at all.
   - `Config.Channels` — channel list, frequencies, and per-channel job locks.
   - Keybinds (`OpenRadioKey`, `PTTKey`, channel up/down).
4. Edit `server/server.lua` → `GetPlayerJob(src)` to pull the job from your
   framework (QBCore/ESX examples are commented inline). It defaults to
   always returning `'police'` so it works out of the box for testing —
   **swap this before going live.**

## Voice integration

This script is written against **pma-voice**'s radio channel API
(`setRadioChannel`). If you're on a different version of pma-voice, or a
different voice resource entirely (saltychat, tokovoip, mumble-voip), open
`client/client.lua` and look for the `VOICE INTEGRATION` block near the top —
every actual voice-plugin call is isolated there, so that's the only place
you need to touch. Check your voice resource's own documentation for its
current export names, since these change between versions.

## Controls (default)

| Key | Action |
|---|---|
| `M` | Toggle radio HUD |
| `F6` | Power radio on/off |
| `Left Alt` (hold) | Push to talk |
| `Page Up` / `Page Down` | Cycle channel |
| Click a channel tile | Jump directly to that channel |
| `Esc` or the ✕ button | Close the HUD |

## Notes

- The radio is a HUD overlay, not a menu — `SetNuiFocus` is left off so
  players keep full mouse/keyboard control of their character while it's
  open, same as real radio HUDs (e.g. holding it up doesn't freeze you).
- Encrypted channels show a lock icon and are gated by `chan.job` in
  `config.lua`; access is also enforced server-side in `requestChannel`, so
  a modified client can't just request a channel it isn't allowed on.
- Battery drain is a real-time countdown (`Config.BatteryLifeMinutes`);
  set it to `0` to disable it entirely for infinite battery.
- `Config.SpeakerBleedRange` is a stub for the "other players nearby can
  faintly hear your radio" effect — the event relay exists in
  `server.lua`/`client.lua`, but the actual proximity check and audio
  playback is left for you to wire into your voice resource's positional
  audio, since that API differs by resource.
