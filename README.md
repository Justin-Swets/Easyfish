# EasyFish — fishing helper for World of Warcraft: Forever

Everything a fishing addon is allowed to do, and nothing it isn't. EasyFish never detects the bite or clicks the
bobber for you (the API doesn't expose it, and doing it externally is a ban). Every action is one hardware click or
key; everything else is information.

## Install
1. Find your Forever install: `World of Warcraft\_forever_\`.
2. Copy the `EasyFish` folder into `<that folder>\Interface\AddOns\` so you have `...\AddOns\EasyFish\EasyFish.toc`.
3. `/reload` or restart, enable it on the AddOns screen. `/fish` opens settings; there is also a minimap button.

## If your history stops loading
The live client keeps your history by itself, so most players need nothing here. Early Forever clients wrote
SavedVariables when you logged out but never read them back. If every login starts with no history,
`tools\Sync-EasyFish.ps1` works around it: it writes your saved data as a small
companion addon, `Interface\AddOns\EasyFish_History`, which EasyFish loads first. It has its own folder, so updating
EasyFish (by hand or through the CurseForge app) never touches it. **Restart the game once** after the first sync so
the client notices the new addon folder, and keep *EasyFish History* enabled in the AddOns list.

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
- **Double right-click** on the world casts, while a fishing pole is equipped. It never equips anything, never fires
  over a creature or NPC, and is off in combat. Right-drag (camera), right-click on the bobber / NPCs work normally.
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
- Bite sound boost, auto-loot, catch log, lure/log buttons on the status window, plus a Pole button that turns into
  a Weapons button while the pole is on, however you equipped it.
- The **status window** appears when you equip a fishing pole and hides when you take it off (Window tab →
  *Only while a fishing pole is equipped*; untick to keep it up). Right-click the minimap button or `/fish show` to
  show/hide it by hand until the pole next goes on or off.

### Recipes, rare fish and getting started
- **Starter guide** — `/fish start` shows your next step and a route from skill 1 to 300 for your faction, with waypoints. Your place on it follows your skill.
- **Recipes and vendors** — the Recipes tab lists what your fish make, sorted into what's ready to cook, what you know and what you can learn. Click a recipe for a waypoint to its nearest vendor.
- **Recipe vendors on the minimap** — gold food icons mark vendors in your zone who sell fish cooking recipes. Hover one to see what they sell.
- **Richer fish tooltips** — any fish shows its auction or vendor price and what you can make with it, including how many from your bags.
- **Rare and trophy fish** — see what's worth watching for in your zone, get an alert when you catch one, and hover the Top Fish rows to see each fish's rarity.

## Commands
```
/fish                open settings        /fish status      what was detected
/fish where          zones for your skill /fish spots       best recorded spots
/fish want [name]    wanted list          /fish keyboard    soft-target interact on/off
/fish pole           swap weapon/pole     /fish stats       catch log
/fish start [go]     starter guide        /fish rare [all]  rare and trophy fish
/fish recipes [all|fish]  what fish make  /fish make        what your bags can make
/fish toggle|sound|loot|show|minimap      /fish spell <name> override spell name
/fish reset [all]    clear catch log      /fish clearspots  forget spot history
```

## Notes
- Zone skill values are Classic Era numbers. Forever is Classic+ and may differ; unknown zones say "no data".
  Corrections welcome — they live in `Data.lua`.
- Recipe and fish data is Classic; Forever has reworked some recipes. Corrections live in `RecipeData.lua`,
  `RarityData.lua` and `StarterData.lua`. NPC positions come from Questie's Classic NPC database.
- Gold/hour counts everything you fish up, including what's inside chests and trunks (items and coins) once you
  open them. The chest itself counts as nothing, since its value is what's inside.

## Development
The addon lives in `EasyFish/`. Symlink or copy that folder into `Interface\AddOns\`.
Modules load in the order listed in `EasyFish.toc`; each module only depends on `EasyFish.lua` (the core) and `Data.lua`.

### Tests
The addon can be run outside the game against a simulated WoW API (`tests/wow_stub.lua`), with Python and
`pip install lupa`:

- `python tests/check_syntax.py`: compiles every addon file with real Lua 5.1 (the compiler WoW uses)
- `python tests/test_core.py`: behaviour tests (double right-click safety, dashboard caching, fishing spots)
- `python tests/smoke.py`: runs every `/fish` command, settings tab and event handler and reports any error the
  addon's protective `pcall`s would otherwise hide in game
- `python tests/perf.py`: time and memory per status-window and minimap update, for a small and a large history
