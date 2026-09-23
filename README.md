# EasyFish — fishing helper for World of Warcraft: Forever

Everything a fishing addon is allowed to do, and nothing it isn't. EasyFish never detects the bite or clicks the
bobber for you (the API doesn't expose it, and doing it externally is a ban). Every action is one hardware click or
key; everything else is information.

## Install
1. Find your Forever install. During the beta it is `World of Warcraft\_classic_beta_\`.
2. Copy the `EasyFish` folder into `<that folder>\Interface\AddOns\` so you have `...\AddOns\EasyFish\EasyFish.toc`.
3. `/reload` or restart, enable it on the AddOns screen. `/fish` opens settings; there is also a minimap button.
4. **Keep your history (Forever beta):** run `tools\Install-EasyFishSync.ps1` once. See below.

## Keeping history on the Forever beta
The Forever beta client writes SavedVariables when you log out but never reads them back, so without help every
login starts with no history. `tools\Sync-EasyFish.ps1` works around it: it copies your saved file into the addon
folder as `EasyFish_Saved.lua`, which the addon loads on login.

- **Install once:** right-click `tools\Install-EasyFishSync.ps1` → *Run with PowerShell*. It runs the sync in the
  background from Windows logon (per-user scheduled task, no admin rights). `-Uninstall` removes it.
- **Or by hand:** run `tools\Sync-EasyFish.ps1` after you log out and before you log back in.
- Sessions played while history failed to load are not lost: they are kept and merged back in on the next login.
- Every save is backed up to `WTF\Account\<account>\SavedVariables\EasyFish-sync\backups` (last 40).
- Avoid `/reload` while fishing: the client saves and reloads faster than the sync can react, so the session before
  the reload can be lost from history (it is still in the backups).
- If Blizzard fixes the bug, nothing needs to change; the addon uses whichever copy is newer.

## Features

### Casting
- **Double right-click** on the world casts. Right-drag (camera), right-click on the bobber / NPCs work normally.
- **Hotkey**: Key Bindings → EasyFish → *Cast fishing line*. Most reliable option.
- **Keyboard fishing** (Extras tab): turns on Blizzard's soft-target interact so after a cast the bobber becomes your
  interact target and the *Interact With Target* key grabs it. It's a game setting, not automation.
- Auto-equips your best fishing pole if you cast without one.

### Guide (skill-aware)
- Status window shows the zone's minimum skill, the junk-free threshold (min + 95), your effective skill and the
  estimated junk %.
- **Smart lure**: picks the *weakest* lure in your bags that still gets this zone junk-free instead of burning your
  best one. **Auto-lure**: if a cast would give junk, that click applies the lure first.
- `/fish where` — zones you can fish cleanly at your skill and level, and where the next tier opens.

### Personal heatmap (Map tab)
- Every cast and catch is recorded with your position and server hour. No bundled database — it learns your server.
- Pins on the **world map** and **minimap**, coloured green/yellow/red by how well the spot has fished for you.
  Hover for casts, fish/hr, junk %, top fish and the hour you usually fish it. `/fish spots` lists the best ones.
- Time-gated fish (Nightfin / Sunscale) show as active or inactive in the status window once you've caught them.

### Extras
- **Cast timer bar** — countdown so you recast before the bobber sinks.
- **Wanted list** — reads fish objectives from your quest log and alerts (raid-warning style) when you catch one;
  `/fish want <name>` adds your own; rare (blue+) catches always alert.
- **Junk selling** — grey items you've fished up are sold at any vendor.
- **Danger swap** — the instant you target something hostile, your real weapon goes back on (gear can't change once
  combat starts, so this is the last legal moment).
- **Gold/hour** — vendor value of the session; uses Auctionator / TSM prices if you have them.
- Bite sound boost, auto-loot, catch log, pole/lure/log buttons on the status window.

## Commands
```
/fish                open settings        /fish status      what was detected
/fish where          zones for your skill /fish spots       best recorded spots
/fish want [name]    wanted list          /fish keyboard    soft-target interact on/off
/fish pole           swap weapon/pole     /fish stats       catch log
/fish toggle|sound|loot|show|minimap      /fish spell <name> override spell name
/fish reset [all]    clear catch log      /fish clearspots  forget spot history
```

## Notes
- Zone skill values are Classic Era numbers. Forever is Classic+ and may differ; unknown zones say "no data".
  Corrections welcome — they live in `Data.lua`.
- Forever beta quirk: SavedVariables don't load back; see *Keeping history on the Forever beta* above.
- Gold/hour counts everything you fish up, including what's inside chests and trunks (items and coins) once you
  open them. The chest itself counts as nothing, since its value is what's inside.

## Development
The addon lives in `EasyFish/`. Symlink or copy that folder into `Interface\AddOns\`.
Modules load in the order listed in `EasyFish.toc`; each module only depends on `EasyFish.lua` (the core) and `Data.lua`.
