# Resolution Based Zoom

A [UCP3](https://github.com/UnofficialCrusaderPatch/UnofficialCrusaderPatch3) module for
**Stronghold Crusader** that gives the game a proper zoom on a hotkey.

Crusader only zooms two steps, from the buttons in the interface. This module adds more
steps and puts them on keys you can press at any time during a game.

## How it works

The game draws the map at a fixed pixel scale, so the screen resolution decides how much
map fits on screen. A smaller resolution shows less map at the same scale — which reads
as zooming in; a larger one shows more. Pressing a zoom key selects the next resolution
and applies it immediately, with no menu and no pause.

Only resolutions **with the same aspect ratio as the game window** are used, so the
picture always fills the window instead of being letterboxed, and sizes less than 6%
apart in pixel count are skipped so every step is one you can actually see. The steps run
in strict small-to-large order and stop at both ends rather than wrapping, so the zoom is
predictable: two presses one way and two back always returns you to where you started.

On a 1920x1080 window the ladder typically comes out as
`1280x720 → 1366x768 → 1600x900 → 1920x1080`.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| How many keys | One key | One key that zooms in, and zooms out while **Ctrl** is held; or two keys, one per direction. |
| Zoom key | `E` | Zooms one step in. With one key, Ctrl and this key zooms out. |
| Zoom out key | `R` | Zooms one step out. Only used in two-key mode. |
| Stop the zoom keys doing their normal job | off | Takes the vanilla action away from the keys the module binds, and nothing else. |
| Screen size outside the map | off | A resolution the game returns to whenever it leaves the map, and on the way to the first menu at startup. |

Keys that already do something in the game are marked with a `*` in the drop-downs. By
default such a key zooms **as well as** doing its normal job — `E`, for instance, is also
the "aggressive stance" hotkey for selected troops. Either pick an unmarked key (`R`,
`D`, `F`, `U`, `Y`, `O`, `J`, `K`, Caps Lock and the numpad symbols are unused by the
game) or turn on the suppression switch.

## Behaviour worth knowing

- The zoom keys only work **on the actual game map**. In the main menu, the skirmish
  lobby, briefings, the save/load and options screens, and while you are typing a chat
  message, they are ignored and the key does whatever it normally does. This is the same
  condition the game's own in-game hotkeys use.
- The game's built-in **Z** zoom keeps working and is not reset by a resolution change.
- Each press is a real display mode change: quick, but expect a brief flicker.
- Holding a key down does nothing extra; only a fresh press counts.
- Which steps exist depends on your monitor and on other modules that change the
  resolution list, such as `graphicsApiReplacer`.

## Installing

Copy this folder into your UCP `ucp/modules` directory, named
`resolution-based-zoom-<version>` (unzipped folders load fine), then enable it in the UCP
GUI. From a checkout:

```
python tools/generate.py --install "<game>/ucp/modules"
```

## Compatibility

Works with both `Stronghold Crusader.exe` and `Stronghold_Crusader_Extreme.exe`. Every
address is found by pattern scan at load time; nothing is hardcoded.

Other modules patch the same code, and they load first. `ucp2-legacy`'s `o_gamespeed`
rewrites the game-speed handlers and its `o_keys` (WASD) rebuilds the keyboard case
tables, so the patterns here deliberately anchor on function prologues and small helpers
rather than on handler bodies or tunable constants, and the case index used for
suppression is derived at load time instead of hardcoded. Scans the module can work
without are non-fatal: if one fails, that feature logs a warning and switches itself off
rather than taking the game down.

## Development

`init.lua`, `options.yml`, `locale/en.yml` and `locale/description-en.md` are
**generated** — `init.lua` carries a ~170 entry virtual-key table and `options.yml`
repeats that list once per key drop-down. Edit `tools/generate.py`, not the output.

```
python tools/generate.py        # regenerate
python tools/test_module.py     # run the offline tests (needs: pip install lupa)
```

`tools/test_module.py` loads `init.lua` into a Lua runtime with a fake `core` table over
a dictionary standing in for game memory, then drives the detour callbacks the way the
window procedure would. It covers the ladder and its ordering, aspect filtering, one-key
and two-key modes, the map-only gate, the leave-map reset, suppression scope, vanilla
zoom preservation, and graceful degradation when a pattern has been overwritten. No game
launch required.

## Credits

Original module and the resolution-cycling idea by **gynt**. This version adds zoom out,
configurable keys, aspect-ratio filtering and ordering, the map-only gate, vanilla zoom
preservation, and the reset-outside-the-map option.

Resolution ids and the window struct layout come from
[`ucp_graphicsApiReplacer`](https://github.com/TheRedDaemon/ucp_graphicsApiReplacer)'s
`shcRelatedStructures.h`; function and global names come from
[OpenSHC](https://github.com/sourcehold/OpenSHC).

## License

[GPL-3.0](LICENSE), matching the UCP3 ecosystem.
