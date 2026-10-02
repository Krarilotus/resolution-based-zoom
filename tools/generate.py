"""Generate the module's init.lua, options.yml and locale/en.yml.

init.lua carries a ~170 entry virtual-key table and options.yml repeats that list once
per key drop-down, so these files are generated from the single key list below rather
than hand-maintained. Edit this script, never the generated files.

    python tools/generate.py                 # regenerate in place
    python tools/generate.py --install DIR   # also copy the module into DIR
"""

import argparse
import io
import os
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

parser = argparse.ArgumentParser(
    description="Regenerate the module's generated files.")
parser.add_argument('--install', metavar='DIR',
                    help="also copy the module into DIR (a UCP 'ucp/modules' folder); "
                         "the installed folder is named <name>-<version>")
args = parser.parse_args()

OUT = REPO
os.makedirs(os.path.join(OUT, 'locale'), exist_ok=True)

# Keys the game's keyboard dispatcher routes to the do-nothing case in BOTH executables,
# i.e. keys that have no vanilla function at all (verified against the case tables).
FREE = {0x14, 0x44, 0x46, 0x4A, 0x4B, 0x4F, 0x52, 0x55, 0x59, 0x6A, 0x6E, 0x6F}

keys = []
for c in range(ord('A'), ord('Z') + 1):
    keys.append(('letter_%s' % chr(c).lower(), c, chr(c)))
for i in range(1, 11):
    keys.append(('f%d' % i, 0x6F + i, 'F%d' % i))
keys.append(('numpad_add', 0x6B, 'Numpad +'))
keys.append(('numpad_subtract', 0x6D, 'Numpad -'))
keys.append(('numpad_multiply', 0x6A, 'Numpad *'))
keys.append(('numpad_divide', 0x6F, 'Numpad /'))
keys.append(('numpad_decimal', 0x6E, 'Numpad .'))
for i in range(10):
    keys.append(('numpad_%d' % i, 0x60 + i, 'Numpad %d' % i))
for i in range(10):
    keys.append(('digit_%d' % i, 0x30 + i, 'Number row %d' % i))
for n, vk, t in [('tab', 0x09, 'Tab'), ('backspace', 0x08, 'Backspace'), ('enter', 0x0D, 'Enter'),
                 ('space', 0x20, 'Space'), ('caps_lock', 0x14, 'Caps Lock'), ('escape', 0x1B, 'Escape'),
                 ('insert', 0x2D, 'Insert'), ('delete_key', 0x2E, 'Delete'), ('home', 0x24, 'Home'),
                 ('end_key', 0x23, 'End'), ('page_up', 0x21, 'Page Up'), ('page_down', 0x22, 'Page Down'),
                 ('arrow_left', 0x25, 'Arrow Left'), ('arrow_up', 0x26, 'Arrow Up'),
                 ('arrow_right', 0x27, 'Arrow Right'), ('arrow_down', 0x28, 'Arrow Down')]:
    keys.append((n, vk, t))

assert all(0x08 <= vk <= 0x79 for _, vk, _ in keys)
assert len({n for n, _, _ in keys}) == len(keys)
LUA_KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto',
                'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true',
                'until', 'while'}
assert not ({n for n, _, _ in keys} & LUA_KEYWORDS)

# Resolution id -> pixel size. Taken from graphicsApiReplacer's GameResolution enum /
# RESOLUTIONS table. Id 0x14 (640x480) is left out: it is outside the game's 16-entry
# supported-resolution array and outside its own cycle.
RESOLUTIONS = [
    (1, 800, 600), (2, 1024, 768), (3, 1280, 720), (4, 1280, 1024), (5, 1366, 768),
    (6, 1440, 900), (7, 1600, 900), (8, 1600, 1200), (9, 1680, 1050), (10, 1920, 1080),
    (11, 1920, 1200), (12, 2560, 1440), (13, 2560, 1600), (14, 1360, 768), (15, 1024, 600),
]


def label(vk, text):
    return text + ('' if vk in FREE else ' *')


definition = """name: resolution-based-zoom
display-name: Resolution Based Zoom
type: module
version: 0.1.0
author: gynt
meta:
  version: 1.0.0
"""

o = io.StringIO()
o.write("""meta:
  version: 1.0.0
options:
- display: GroupBox
  category: [Resolution Based Zoom]
  header: '{{hotkey_group}}'
  text: '{{hotkey_group_descr}}'
  hasHeader: true
  children:
""")
o.write("""  - url: resolution-based-zoom.hotkey.mode
    name: resolution-based-zoom-hotkey-mode
    text: '{{hotkey_mode}}'
    tooltip: '{{hotkey_mode_tooltip}}'
    display: RadioGroup
    contents:
      type: string
      value: one_key
      choices:
      - name: two_keys
        text: '{{hotkey_mode_two_keys}}'
      - name: one_key
        text: '{{hotkey_mode_one_key}}'
""")
for url, name, txt, tip, default, enabled in [
    ('resolution-based-zoom.hotkey.zoom_in', 'resolution-based-zoom-hotkey-zoom-in',
     'hotkey_zoom_in', 'hotkey_zoom_in_tooltip', 'letter_e', None),
    ('resolution-based-zoom.hotkey.zoom_out', 'resolution-based-zoom-hotkey-zoom-out',
     'hotkey_zoom_out', 'hotkey_zoom_out_tooltip', 'letter_r',
     'resolution-based-zoom.hotkey.mode == "two_keys"'),
]:
    o.write("""  - url: %s
    name: %s
    text: '{{%s}}'
    tooltip: '{{%s}}'
""" % (url, name, txt, tip))
    if enabled is not None:
        o.write("    enabled: %s\n" % enabled)
    o.write("""    display: Choice
    contents:
      type: string
      value: %s
      choices:
""" % default)
    for n, vk, _ in keys:
        o.write("      - name: %s\n        text: '{{key_%s}}'\n" % (n, n))

o.write("""  - url: resolution-based-zoom.hotkey.suppress_vanilla
    name: resolution-based-zoom-hotkey-suppress-vanilla
    text: '{{hotkey_suppress}}'
    tooltip: '{{hotkey_suppress_tooltip}}'
    display: Switch
    contents:
      type: boolean
      value: false
""")

o.write("""- display: GroupBox
  category: [Resolution Based Zoom]
  header: '{{reset_group}}'
  text: '{{reset_group_descr}}'
  hasHeader: true
  children:
  - url: resolution-based-zoom.reset.resolution
    name: resolution-based-zoom-reset-resolution
    text: '{{reset_resolution}}'
    tooltip: '{{reset_resolution_tooltip}}'
    display: Choice
    contents:
      type: string
      value: 'off'
      choices:
      - name: 'off'
        text: '{{reset_off}}'
""")
for i, w, h in sorted(RESOLUTIONS, key=lambda r: r[1] * r[2]):
    o.write("      - name: r%dx%d\n        text: '%d x %d'\n" % (w, h, w, h))
options = o.getvalue()

l = io.StringIO()
l.write("""hotkey_group: Zoom keys
hotkey_group_descr: |
  Pick the keys that zoom the view in and out. Either a single key that zooms in on
  its own and zooms out while Ctrl is held, or two separate keys. By default it is one
  key: E zooms in and Ctrl+E zooms out. Switch to two keys and E zooms in, R zooms out.

  Zooming only uses screen sizes with the same shape as your game window, so the
  picture always fills the window and you never get black bars at the sides. Zoom in
  always goes one step smaller and zoom out one step larger, in order, and it stops
  at the smallest and largest step instead of jumping back around.

  The zoom keys only work while you are on the game map. In the menus, and while you
  are typing, they are ignored.

  Keys marked with a * already do something in the game. By default such a key zooms
  as well as doing its normal job - E, for instance, also sets selected troops to
  aggressive. Either pick an unmarked key, or turn on the switch below to take the
  normal job away from the keys you picked.
hotkey_mode: How many keys
hotkey_mode_tooltip: A single key that zooms out while Ctrl is held (the default), or one key for each direction.
hotkey_mode_two_keys: Two keys - one zooms in, the other zooms out
hotkey_mode_one_key: One key - it zooms in, and zooms out while Ctrl is held
hotkey_zoom_in: Zoom key
hotkey_zoom_in_tooltip: Key that zooms one step in (smaller screen size, bigger picture). In one-key mode, Ctrl and this key zooms out. Default E.
hotkey_zoom_out: Zoom out key
hotkey_zoom_out_tooltip: Key that zooms one step out (larger screen size, more map on screen). Only used with two keys. Default R.
hotkey_suppress: Stop the zoom keys doing their normal job
hotkey_suppress_tooltip: Off by default. Turn it on and only the keys this module actually uses stop doing their normal job - in one-key mode that is just the zoom key. No other key is touched.
reset_group: Screen size outside the map
reset_group_descr: |
  The game can be put back to a screen size of your choice whenever you leave the map -
  to the main menu, the skirmish lobby, a briefing and so on - and on the way to the
  first menu when the game starts. That way the menus are always at the size you want,
  no matter how far you zoomed in during the game.
reset_resolution: Screen size to return to
reset_resolution_tooltip: The screen size the game goes back to whenever it leaves the map. Leave it off to keep whatever the zoom left behind.
reset_off: Off - keep whatever the zoom left behind
""")
for n, vk, t in keys:
    l.write("key_%s: '%s'\n" % (n, label(vk, t).replace("'", "''")))
locale = l.getvalue()

description = """# Resolution Based Zoom

**Author**: gynt

## What it does

Stronghold Crusader only lets you zoom in and out **two steps**, using the buttons in
the game. This module gives you more zoom steps and puts them on a key you can press
at any time during a game - by default **E** to zoom in and **Ctrl+E** to zoom out.

## How it works, in plain words

The game always draws the castle at the same size in pixels. So the smaller the screen
size the game runs at, the less of the map fits on screen - and everything looks
bigger. That is exactly what zooming in feels like. Make the screen size bigger again
and you see more of the map: that is zooming out.

Every time you press a zoom key the module quietly switches the game to the next screen
size and applies it straight away - no menu, no pause.

## Which zoom steps you get

Only screen sizes with the **same shape as your game window** are used. A 16:9 window
only zooms through 16:9 sizes, so the picture always fills the window and you never end
up with black bars down the sides. That also throws out the sizes that were barely any
different from each other, so every press is a zoom step you can actually see.

The steps are used strictly in order, smallest to largest. Zoom in always goes one step
smaller, zoom out one step larger, and it stops at the smallest and the largest step
rather than wrapping back around - so pressing the key twice and then the other key
twice always puts you back where you started.

How many steps you get depends on your monitor and on other modules that change the
list of available screen sizes (for example `graphicsApiReplacer`). You will usually
get four to six, instead of the two the game gives you.

## Settings

**How many keys.** By default a single key: on its own it zooms in, and held together
with **Ctrl** it zooms out. In this mode the second drop-down is ignored. Switch to two
keys and each direction gets its own key.

**The keys themselves.** Pick any key you like from the drop-downs.

**Stop the zoom keys doing their normal job.** Off by default, so a key you pick keeps
whatever the game already does with it and zooms on top of that. Turn it on and the game
stops reacting to those keys entirely - useful if you picked a key like E, which also
sets selected troops to aggressive.

Only the keys this module actually listens to are affected: in one-key mode that is the
zoom key on its own, since the zoom out key is not used there. Nothing else in the game's
keyboard is touched, and it all goes back to normal when the module is disabled.

**Screen size outside the map.** Off by default. Set it to one of your screen sizes and
the game goes back to that size whenever it leaves the map - to the main menu, the
skirmish lobby, a briefing - and on the way to the first menu when the game starts. The
menus are then always at the size you chose, however far you zoomed in during the game.
If the size you pick is one your display cannot do, the reset is skipped rather than
forced.

Keys marked with a `*` in the list already do something in the game. If you choose
one, it will zoom **as well as** doing its normal job - the module does not take keys
away from the game. **R**, the default zoom out key for two-key mode, is unmarked: the
game does not use it at all.

**E**, the default zoom key, is marked, and it is worth knowing what it does: Q, W and E
are the stance hotkeys for selected troops - stand ground, defensive and aggressive. They
only do anything while you actually have troops selected, which is why E looks dead most
of the time. But it does mean that zooming with E while troops are selected also sets
those troops to aggressive. If that bothers you, pick one of the unmarked keys instead -
R, D, F, U, Y, O, J, K and the numpad symbols are all completely unused by the game.

## Things to know

* The zoom keys only do anything while you are **on the actual game map**. In the main
  menu, the skirmish lobby, briefings, the save and load screens, the options screens -
  and while you are typing a chat message - they are ignored and the key does whatever
  it normally does. This is the same test the game's own in-game hotkeys use.
* Each press is a real screen mode change. It is quick, but expect a short flicker,
  and do not hammer the key.
* Holding the key down does nothing extra - only a fresh press counts.
* The game's own two-step zoom on the **Z** key keeps working and is left alone. If
  you are zoomed in with Z, zooming with these keys will not snap you back out.
* If the game is currently running at a screen size that does not fit your window
  shape, the first press snaps to the closest step that does, and normal zooming
  takes over from there.
* Works with both the normal and the Extreme executable.

## Changes in 0.1.0

* Zoom out added. Version 0.0.1 could only cycle forwards through the screen sizes.
* The zoom keys are now ignored outside the game map, so they no longer fire in the
  menus or while typing.
* Optional switch to stop the zoom keys doing their normal in-game job.
* Optional single-key mode: one key zooms in, Ctrl and that key zooms out.
* Optional screen size to return to whenever the game leaves the map.
* Zoom steps now follow a fixed small-to-large order instead of the game's own
  scattered cycle order, so zooming is predictable.
* Screen sizes that would leave black bars at the sides are skipped.
* Zooming no longer resets the game's own Z key zoom level.
* The keys are now settings instead of being fixed to Numpad +.
* The module no longer patches the game's key tables at all, so no key loses its
  vanilla behaviour.
* The default is now one key: E zooms in, Ctrl+E zooms out (R is the zoom out key if
  you switch to two keys). Version 0.0.1 used Numpad +, which also sped the game up.
"""

initlua = r'''-- Resolution Based Zoom
--
-- Steps the game through its screen resolutions on a hotkey. The map is always drawn at
-- a fixed pixel scale, so a smaller resolution shows less map at a larger apparent size
-- (zoom in) and a larger one shows more (zoom out).
--
-- Only resolutions with the same aspect ratio as the game window are used, so the
-- picture always fills the window, and they are walked in strict small-to-large order
-- rather than in the game's own cycle order, which is scattered (1, 15, 2, 3, 4, 14, ...).
--
-- Three patch points, all located by pattern scan, all valid for the plain and the
-- Extreme executable:
--
--   * The video options menu-item handler (cdecl, one item id). Item 0x12 applies the
--     currently selected resolution. The game has no "previous resolution" action and
--     its "next" action follows that scattered cycle, so neither is used: the target id
--     is written straight into the selection and only the apply item is called. Apply
--     also forces the live zoom level to the one stored in the video options menu, which
--     is what used to throw away the Z key's zoom; see the sync in `zoom` below.
--   * The window/graphics struct, reached from the "next resolution" case body: it holds
--     the client size of the game window, the applied resolution id and the per-id
--     supported flags.
--   * The keyboard dispatcher inside the window procedure: a jump-table lookup reached
--     once per key-down with ESI = virtual-key code and ECX = lParam. Detouring there
--     (instead of one key's handler) is what makes any dispatched key bindable.
--   * The in-game guard: the screen id, the ids that mean "on the map", and the flag
--     every vanilla in-game hotkey tests before it does anything. The zoom keys check
--     exactly what those handlers check, so they are inert in every menu the vanilla
--     hotkeys are inert in.
--   * `requestScreenChange`, three bytes in, where EBP already holds the screen the game
--     is about to move to. That is the hook for resetting to a default resolution when
--     the player leaves the map, and it fires on the way to the first menu at startup
--     too. Ctrl / Shift / Alt are not tracked by the game at all (they route to the
--     do-nothing case), so single-key mode reads Ctrl from GetAsyncKeyState through a
--     small cdecl-to-stdcall thunk.

-- Virtual-key code per choice name in options.yml.
local VIRTUAL_KEY_CODES = {
__VK_TABLE__
}

local DEFAULT_ZOOM_IN_KEY = "letter_e"
local DEFAULT_ZOOM_OUT_KEY = "letter_r"

-- Resolution id -> pixel size, matching the game's own hardcoded list. Id 0x14 (640x480)
-- is deliberately absent: it falls outside the 16-entry supported-resolution array.
local RESOLUTIONS = {
__RESOLUTION_TABLE__
}

-- Choice name in options.yml -> resolution id, for the "screen size outside the map"
-- setting. Absent (including the "off" choice) means the reset is disabled.
local RESET_RESOLUTION_IDS = {
__RESET_TABLE__
}

-- How far a resolution's aspect ratio may differ from the window's and still count as
-- filling it. 1% keeps 1366x768 and 1360x768 on a 16:9 window (a handful of pixels) but
-- drops 4:3, 5:4 and 16:10 sizes, which would letterbox.
local ASPECT_RATIO_TOLERANCE = 0.01

-- How much bigger a step has to be than the one below it to be worth having, in pixel
-- count. Without this, 1360x768 and 1366x768 would be two separate zoom steps six pixels
-- apart; 6% of area is about 3% in each direction, which is a change you can see.
local MINIMUM_STEP_RATIO = 1.06

local ZOOM_IN = -1  -- one step smaller
local ZOOM_OUT = 1  -- one step larger

local MODE_TWO_KEYS = "two_keys"
local MODE_ONE_KEY = "one_key"
local NO_DEFAULT_RESOLUTION = "off"

local VK_CONTROL = 0x11

-- Video options menu-item handler: mov eax, [esp+4] / add eax, 0x14 (its switch bias).
local VIDEO_OPTIONS_HANDLER_AOB = "8B 44 24 04 83 C0 14"
local MENU_ITEM_APPLY = 0x12

-- Body of the menu handler's "next resolution" case. Its first instruction loads the
-- pending resolution selection, and at +0x45 sits the operand of
-- `cmp dword [eax*4 + supportedResolutions], 0`.
local RESOLUTION_STATE_AOB = "A1 ? ? ? ? 83 F8 01 75 07 B8 0F 00 00 00 EB 31 83 F8 0F 75 07 "
    .. "B8 02 00 00 00 EB 25 83 F8 04 75 07 B8 0E 00 00 00 EB 19 83 F8 0E 75 07 B8 05 00 00 00 "
    .. "EB 0D 83 C0 01 83 F8 0E 75 05 B8 01 00 00 00 83 3C 85 ? ? ? ? 00"
local OFFSET_PENDING_SELECTION = 1
local OFFSET_SUPPORTED_RESOLUTIONS = 0x45

-- Tail of the apply action, where it forces the live zoom level to whatever the video
-- options menu has stored -- which is what otherwise throws away the Z key's zoom on
-- every resolution change:
--   mov eax, [menuZoomSetting] / cmp eax, [liveZoomFlag] / je skip / setZoom(mapView, eax)
local ZOOM_SYNC_AOB = "A1 ? ? ? ? 3B 05 ? ? ? ? 74 1F 50 B9 ? ? ? ? E8 ? ? ? ? "
    .. "C7 05 ? ? ? ? 02 00 00 00"
local OFFSET_MENU_ZOOM_SETTING = 1
local OFFSET_LIVE_ZOOM_FLAG = 7

-- Window/graphics struct, addressed from its supported-resolution array.
local SUPPORTED_RESOLUTIONS_IN_STRUCT = 0x68
local WINDOW_WIDTH_IN_STRUCT = 0x08  -- client width, kept up to date on WM_SIZE
local WINDOW_HEIGHT_IN_STRUCT = 0x0C
local APPLIED_RESOLUTION_IN_STRUCT = 0x5C

-- lea eax, [esi-8] / cmp eax, 0x71 / ja tail / movzx eax, byte [eax + keyCaseTable]
-- / jmp dword [eax*4 + caseAddressTable]
local KEY_DISPATCH_AOB = "8D 46 F8 83 F8 71 0F 87 ? ? ? ? 0F B6 80 ? ? ? ? FF 24 85 ? ? ? ?"
local OFFSET_TAIL_JUMP = 6       -- the `ja tail` for keys outside 0x08 - 0x79
local SIZE_TAIL_JUMP = 6
local OFFSET_KEY_CASE_TABLE = 15 -- operand of the movzx: byte table indexed by (vk - 8)
local OFFSET_CASE_ADDRESS_TABLE = 22
local KEY_CASE_TABLE_SIZE = 0x72 -- one byte per dispatched key, 0x08 through 0x79
local MAX_KEY_CASES = 256        -- sanity bound on the derived case count
local OFFSET_DISPATCH_JUMP = 19  -- the jmp itself
local SIZE_DISPATCH_JUMP = 7
local FIRST_DISPATCHED_KEY = 0x08
local LAST_DISPATCHED_KEY = 0x79

-- The game's only GetAsyncKeyState call site: push 0x28 / call dword [import].
local GET_ASYNC_KEY_STATE_AOB = "6A 28 FF 15 ? ? ? ? 66 85 C0"
local OFFSET_GET_ASYNC_KEY_STATE_IMPORT = 4

-- `requestScreenChange(this, screenID, param)`, three bytes into the body, where the
-- requested screen id is already in EBP and nothing has been written yet:
--   cmp ebp, 0x17 / push esi / mov esi, ecx
local SCREEN_CHANGE_AOB = "83 FD 17 56 8B F1 75 05 BD 29 00 00 00 8B 44 24 10 53 57 89 6E 18"
local SIZE_SCREEN_CHANGE_HOOK = 6

-- The prologue every in-game key handler shares, pinned to the game-speed-up one:
--   test ecx,0x40000000 / jne tail / mov ecx,screenObject / call isInGameScreen /
--   test eax,eax / je tail / cmp dword [menuGuard],-1 / jne tail
-- `menuGuard` is -1 exactly when the game is not capturing input for something else.
-- Deliberately stops at the menuGuard operand. An earlier version carried on into the
-- handler body to make the match unique, and ucp2-legacy's `o_gamespeed` rewrites
-- exactly those bytes (its own scan starts at the `cmp eax,0x5A` this used to end on),
-- so the scan failed whenever that option was on. This prefix matches five handler
-- prologues and every one of them yields the same two addresses.
local IN_GAME_GUARD_AOB = "F7 C1 00 00 00 40 0F 85 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 85 C0 "
    .. "0F 84 ? ? ? ? 83 3D ? ? ? ? FF"
local OFFSET_MENU_GUARD = 32
local MENU_GUARD_IDLE = -1

-- The same screen id read absolutely, inside a sibling of `isInGameScreen`:
--   cmp dword [screenID], 0x10 / je / xor eax,eax / ret / mov eax,[...] / cmp eax,4
local SCREEN_ID_AOB = "83 3D ? ? ? ? 10 74 03 33 C0 C3 A1 ? ? ? ? 83 F8 04"
local OFFSET_SCREEN_ID = 2

-- `isInGameScreen`: mov eax,[ecx+0xC] / cmp eax,0xC / cmp eax,0xE / cmp eax,0x10.
-- The three immediates are the screen ids that mean "on the map"; read them from here
-- rather than hardcoding them.
local IN_GAME_SCREEN_AOB = "8B 41 0C 83 F8 0C 74 0D 83 F8 0E 74 08 83 F8 10 74 03 33 C0 C3"
local OFFSETS_IN_GAME_SCREEN_IDS = { 5, 10, 15 }

---Scan for an AOB that the module can manage without. Other modules patch game code
---before this one runs (ucp2-legacy rewrites both the game-speed handlers and the key
---tables, for instance), so a pattern that has been overwritten must degrade the
---feature that needs it, never take the game down with it.
---@param pattern string
---@param purpose string what the address is for, for the log line
---@return number|nil address
local function scanOptional(pattern, purpose)
  local found, address = pcall(core.AOBScan, pattern)
  if not found or address == nil then
    log(WARNING, "resolution-based-zoom: could not find " .. purpose
      .. "; that part is disabled. Another module has probably patched it.")
    return nil
  end
  return address
end

---Bit 30 of lParam is set when a key-down message is a hold-down auto-repeat.
---@param lParam number the ECX value at the dispatch site
---@return boolean
local function isAutoRepeat(lParam)
  if lParam < 0 then
    lParam = lParam + 0x100000000
  end
  return math.floor(lParam / 0x40000000) % 2 == 1
end

---Build a cdecl wrapper around a stdcall import, so it can be called with exposeCode
---(which does not implement the stdcall convention). The wrapper forwards its single
---argument and lets the callee clean it up:
---  push dword [esp+4] / call dword [import] / ret
---@param importAddress number address of the import table slot
---@return number address of the wrapper
local function wrapStdcallImport(importAddress)
  local pointer = core.itob(importAddress)
  return core.allocateCode({
    0xFF, 0x74, 0x24, 0x04,
    0xFF, 0x15, pointer[1], pointer[2], pointer[3], pointer[4],
    0xC3,
  })
end

---GetAsyncKeyState reports the key as down in bit 15 of its (16-bit) result; the rest of
---EAX is not meaningful, so mask before testing.
---@param getAsyncKeyState function
---@param virtualKeyCode number
---@return boolean
local function isKeyHeld(getAsyncKeyState, virtualKeyCode)
  local result = getAsyncKeyState(virtualKeyCode)
  if result < 0 then
    result = result + 0x100000000
  end
  return math.floor(result % 0x10000 / 0x8000) == 1
end

---Resolve a configured choice name to a virtual-key code, falling back to a default.
---@param keyName string|nil the choice name stored in the config
---@param defaultKeyName string the choice name to fall back to
---@return number virtualKeyCode
local function resolveHotkey(keyName, defaultKeyName)
  local virtualKeyCode = VIRTUAL_KEY_CODES[keyName]

  if virtualKeyCode == nil
      or virtualKeyCode < FIRST_DISPATCHED_KEY
      or virtualKeyCode > LAST_DISPATCHED_KEY then
    if keyName ~= nil then
      log(WARNING, string.format(
        "resolution-based-zoom: unusable key '%s', falling back to '%s'.",
        tostring(keyName), defaultKeyName))
    end
    virtualKeyCode = VIRTUAL_KEY_CODES[defaultKeyName]
  end

  return virtualKeyCode
end

---@class ResolutionState
---@field pendingSelection number address of the resolution the apply action reads
---@field supportedResolutions number base of the per-id supported flags
---@field windowWidth number address of the game window's client width
---@field windowHeight number address of the game window's client height
---@field appliedResolution number address of the resolution currently on screen
---@field screenID number address of the screen the game is currently showing
---@field inGameScreens table<number, boolean> screen ids that mean "on the map"
---@field menuGuard number address of the flag that is -1 when nothing captures input
---@field menuZoomSetting number address of the video options menu's stored zoom level
---@field liveZoomFlag number address of the zoom level actually in effect (the Z key's)

---Pixel count of a resolution id, used as its size for ordering purposes.
---@param resolutionID number
---@return number
local function pixelCount(resolutionID)
  local resolution = RESOLUTIONS[resolutionID]
  return resolution.width * resolution.height
end

---Collect the resolutions to zoom through, smallest first.
---Only resolutions the display supports and that share the window's aspect ratio are
---used, so the picture fills the window. If that leaves fewer than two steps (an
---unusual window shape, or a window size not known yet) every supported resolution is
---used instead, so zooming still does something. Steps too close together to notice are
---then dropped, keeping the largest so zooming out always reaches the native size.
---@param state ResolutionState
---@return number[] ladder resolution ids, ascending by pixel count
local function buildZoomLadder(state)
  local supported = {}
  for resolutionID in pairs(RESOLUTIONS) do
    if core.readInteger(state.supportedResolutions + resolutionID * 4) ~= 0 then
      supported[#supported + 1] = resolutionID
    end
  end

  local windowWidth = core.readInteger(state.windowWidth)
  local windowHeight = core.readInteger(state.windowHeight)

  local ladder = supported
  if windowWidth > 0 and windowHeight > 0 then
    local windowAspectRatio = windowWidth / windowHeight
    local matching = {}
    for _, resolutionID in ipairs(supported) do
      local resolution = RESOLUTIONS[resolutionID]
      local aspectRatio = resolution.width / resolution.height
      if math.abs(aspectRatio - windowAspectRatio)
          <= windowAspectRatio * ASPECT_RATIO_TOLERANCE then
        matching[#matching + 1] = resolutionID
      end
    end
    if #matching >= 2 then
      ladder = matching
    end
  end

  table.sort(ladder, function(left, right)
    return pixelCount(left) < pixelCount(right)
  end)

  -- Walk from the largest down, so the native size is always a step, and skip anything
  -- that is barely smaller than the step above it.
  local stepped = {}
  for index = #ladder, 1, -1 do
    local resolutionID = ladder[index]
    local lastKept = stepped[#stepped]
    if lastKept == nil
        or pixelCount(resolutionID) * MINIMUM_STEP_RATIO <= pixelCount(lastKept) then
      stepped[#stepped + 1] = resolutionID
    end
  end

  -- `stepped` came out largest first; hand it back smallest first.
  local ascending = {}
  for index = #stepped, 1, -1 do
    ascending[#ascending + 1] = stepped[index]
  end

  return ascending
end

---Find where the resolution currently on screen sits on the ladder. If it is not on the
---ladder at all (a shape that does not fit the window), the closest step is returned so
---the first keypress snaps onto the ladder.
---@param ladder number[]
---@param appliedResolutionID number
---@return number|nil index, boolean onLadder
local function locateOnLadder(ladder, appliedResolutionID)
  if #ladder == 0 then
    return nil, false
  end

  local applied = RESOLUTIONS[appliedResolutionID]
  if applied == nil then
    -- An id outside the game's own list (640x480 is the one that exists); it is smaller
    -- than anything on the ladder, so snap to the smallest step.
    return 1, false
  end

  local appliedPixels = applied.width * applied.height
  local closestIndex, smallestDistance = nil, nil
  for index, resolutionID in ipairs(ladder) do
    if resolutionID == appliedResolutionID then
      return index, true
    end
    local resolution = RESOLUTIONS[resolutionID]
    local distance = math.abs(resolution.width * resolution.height - appliedPixels)
    if smallestDistance == nil or distance < smallestDistance then
      closestIndex, smallestDistance = index, distance
    end
  end

  return closestIndex, false
end

---Find the case index that means "do nothing": the one whose jump-table entry is the
---same tail the dispatcher jumps to for keys outside its range. Derived rather than
---hardcoded, because ucp2-legacy's `o_keys` (WASD) rebuilds these tables.
---@param dispatchSite number base of the key dispatcher
---@return number|nil caseIndex
local function findDoNothingCase(dispatchSite)
  local tailOffset = core.readInteger(dispatchSite + OFFSET_TAIL_JUMP + 2)
  local tail = dispatchSite + OFFSET_TAIL_JUMP + SIZE_TAIL_JUMP + tailOffset
  local keyCaseTable = core.readInteger(dispatchSite + OFFSET_KEY_CASE_TABLE)
  local caseAddressTable = core.readInteger(dispatchSite + OFFSET_CASE_ADDRESS_TABLE)

  -- How many cases there are. The byte table sits directly after the address table, so
  -- the gap between them gives the count exactly; if some module has moved one of them,
  -- fall back to the highest index any key actually uses. Do not bound the search by
  -- that highest index alone: if no key currently maps to the do-nothing case, it is the
  -- one index the scan would then never look at.
  local caseCount = 0
  if keyCaseTable > caseAddressTable then
    local span = math.floor((keyCaseTable - caseAddressTable) / 4)
    if span > 0 and span <= MAX_KEY_CASES then
      caseCount = span
    end
  end

  for index = 0, KEY_CASE_TABLE_SIZE - 1 do
    local caseIndex = core.readByte(keyCaseTable + index)
    if caseIndex + 1 > caseCount then
      caseCount = caseIndex + 1
    end
  end

  for caseIndex = 0, caseCount - 1 do
    if core.readInteger(caseAddressTable + caseIndex * 4) == tail then
      return caseIndex
    end
  end

  return nil
end

---Whether the player is on the actual game map, with nothing else capturing input.
---Both halves are what the game's own in-game key handlers test, so the zoom keys are
---inert wherever the vanilla in-game hotkeys are: the main menu, the skirmish lobby,
---briefings, and the save / load / options screens.
---@param state ResolutionState
---@return boolean
local function isOnGameMap(state)
  if state.screenID ~= nil and next(state.inGameScreens) ~= nil
      and state.inGameScreens[core.readInteger(state.screenID)] ~= true then
    return false
  end
  if state.menuGuard ~= nil
      and core.readInteger(state.menuGuard) ~= MENU_GUARD_IDLE then
    return false
  end
  return true
end

---Select a resolution and apply it, preserving the vanilla zoom level.
---@param state ResolutionState
---@param applyResolution fun() calls the video options apply action
---@param targetResolutionID number
local function switchResolution(state, applyResolution, targetResolutionID)
  if targetResolutionID == core.readInteger(state.appliedResolution) then
    return
  end

  -- Applying video options ends by forcing the live zoom level to the one the video
  -- options menu holds, which is stale as soon as the player has touched the Z key.
  -- Copying the live level into that setting first makes the forcing a no-op, so the
  -- vanilla zoom survives the resolution change.
  core.writeInteger(state.menuZoomSetting, core.readInteger(state.liveZoomFlag))

  core.writeInteger(state.pendingSelection, targetResolutionID)
  applyResolution()
end

---Move one step along the zoom ladder and apply the result.
---@param state ResolutionState
---@param applyResolution fun() calls the video options apply action
---@param direction number ZOOM_IN or ZOOM_OUT
local function zoom(state, applyResolution, direction)
  local ladder = buildZoomLadder(state)
  local appliedResolutionID = core.readInteger(state.appliedResolution)
  local index, onLadder = locateOnLadder(ladder, appliedResolutionID)
  if index == nil then
    return
  end

  -- Already on the ladder: step. Not on it yet: snap to the closest step instead.
  if onLadder then
    index = index + direction
    if index < 1 or index > #ladder then
      return -- at the smallest or largest step already; do not wrap around
    end
  end

  switchResolution(state, applyResolution, ladder[index])
end

---Put the game back on the configured resolution. Called when the game is about to
---leave the map, which includes the first menu it shows at startup.
---@param state ResolutionState
---@param applyResolution fun()
---@param resolutionID number
local function resetResolution(state, applyResolution, resolutionID)
  if core.readInteger(state.supportedResolutions + resolutionID * 4) == 0 then
    return -- the display cannot do it; leave the resolution alone rather than fail
  end
  switchResolution(state, applyResolution, resolutionID)
end

return {

  enable = function(self, config)
    config = config or {}
    local hotkeyConfig = config.hotkey or {}
    local singleKeyMode = (hotkeyConfig.mode or MODE_ONE_KEY) == MODE_ONE_KEY

    local zoomInKey = resolveHotkey(hotkeyConfig.zoom_in, DEFAULT_ZOOM_IN_KEY)
    local zoomOutKey = nil
    if not singleKeyMode then
      zoomOutKey = resolveHotkey(hotkeyConfig.zoom_out, DEFAULT_ZOOM_OUT_KEY)
      if zoomInKey == zoomOutKey then
        log(WARNING, "resolution-based-zoom: both zoom keys are the same key, "
          .. "only zooming in is bound.")
        zoomOutKey = nil
      end
    end

    local videoOptionsHandler = core.exposeCode(
      core.AOBScan(VIDEO_OPTIONS_HANDLER_AOB), 1, 0)
    local function applyResolution()
      videoOptionsHandler(MENU_ITEM_APPLY)
    end

    local resolutionStateSite = core.AOBScan(RESOLUTION_STATE_AOB)
    local supportedResolutions =
      core.readInteger(resolutionStateSite + OFFSET_SUPPORTED_RESOLUTIONS)
    local windowStruct = supportedResolutions - SUPPORTED_RESOLUTIONS_IN_STRUCT

    local zoomSyncSite = core.AOBScan(ZOOM_SYNC_AOB)

    local inGameScreens = {}
    local inGameScreenSite = scanOptional(IN_GAME_SCREEN_AOB, "the on-the-map screen ids")
    if inGameScreenSite ~= nil then
      for _, offset in ipairs(OFFSETS_IN_GAME_SCREEN_IDS) do
        inGameScreens[core.readByte(inGameScreenSite + offset)] = true
      end
    end

    local screenIDSite = scanOptional(SCREEN_ID_AOB, "the current screen id")
    local guardSite = scanOptional(IN_GAME_GUARD_AOB, "the in-game input guard")

    local state = {
      pendingSelection = core.readInteger(resolutionStateSite + OFFSET_PENDING_SELECTION),
      supportedResolutions = supportedResolutions,
      windowWidth = windowStruct + WINDOW_WIDTH_IN_STRUCT,
      windowHeight = windowStruct + WINDOW_HEIGHT_IN_STRUCT,
      appliedResolution = windowStruct + APPLIED_RESOLUTION_IN_STRUCT,
      screenID = screenIDSite ~= nil
        and core.readInteger(screenIDSite + OFFSET_SCREEN_ID) or nil,
      inGameScreens = inGameScreens,
      menuGuard = guardSite ~= nil
        and core.readInteger(guardSite + OFFSET_MENU_GUARD) or nil,
      menuZoomSetting = core.readInteger(zoomSyncSite + OFFSET_MENU_ZOOM_SETTING),
      liveZoomFlag = core.readInteger(zoomSyncSite + OFFSET_LIVE_ZOOM_FLAG),
    }

    -- Ctrl is only needed in single-key mode, and the game does not track it itself.
    local getAsyncKeyState = nil
    if singleKeyMode then
      local callSite = scanOptional(GET_ASYNC_KEY_STATE_AOB, "the GetAsyncKeyState import")
      if callSite ~= nil then
        getAsyncKeyState = core.exposeCode(
          wrapStdcallImport(
            core.readInteger(callSite + OFFSET_GET_ASYNC_KEY_STATE_IMPORT)), 1, 0)
      else
        singleKeyMode = false -- without Ctrl the key can only zoom in
      end
    end

    local dispatchSite = core.AOBScan(KEY_DISPATCH_AOB)

    -- Exactly the keys this module listens to, and no others: in one-key mode that is
    -- the zoom key alone, since the zoom out key is never read there.
    local boundKeys = { zoomInKey }
    if zoomOutKey ~= nil then
      boundKeys[#boundKeys + 1] = zoomOutKey
    end

    -- Optional: repoint those keys at the do-nothing case so they only zoom. Left alone
    -- by default, in which case a key keeps whatever the game does with it (E, for one,
    -- also sets selected troops to aggressive) and the zoom happens on top.
    if hotkeyConfig.suppress_vanilla == true then
      local doNothingCase = findDoNothingCase(dispatchSite)
      if doNothingCase == nil then
        log(WARNING, "resolution-based-zoom: could not find the do-nothing key case; "
          .. "the zoom keys keep their normal in-game job.")
      else
        local keyCaseTable = core.readInteger(dispatchSite + OFFSET_KEY_CASE_TABLE)
        for _, virtualKeyCode in ipairs(boundKeys) do
          core.writeCodeByte(
            keyCaseTable + (virtualKeyCode - FIRST_DISPATCHED_KEY), doNothingCase)
        end
      end
    end

    core.detourCode(function(registers)
      if not isAutoRepeat(registers.ECX) and isOnGameMap(state) then
        if registers.ESI == zoomInKey then
          if singleKeyMode and isKeyHeld(getAsyncKeyState, VK_CONTROL) then
            zoom(state, applyResolution, ZOOM_OUT)
          else
            zoom(state, applyResolution, ZOOM_IN)
          end
        elseif registers.ESI == zoomOutKey then
          zoom(state, applyResolution, ZOOM_OUT)
        end
      end
      return registers
    end, dispatchSite + OFFSET_DISPATCH_JUMP, SIZE_DISPATCH_JUMP)

    local resetResolutionID = RESET_RESOLUTION_IDS[(config.reset or {}).resolution]
    local screenChangeSite = nil
    if resetResolutionID ~= nil and next(inGameScreens) ~= nil then
      screenChangeSite = scanOptional(SCREEN_CHANGE_AOB, "the screen change function")
    end
    if screenChangeSite ~= nil then
      -- EBP already holds the screen the game is moving to, and nothing has been
      -- written yet, so this still runs in the context of the screen being left.
      core.detourCode(function(registers)
        if not inGameScreens[registers.EBP] then
          resetResolution(state, applyResolution, resetResolutionID)
        end
        return registers
      end, screenChangeSite, SIZE_SCREEN_CHANGE_HOOK)
    end

    log(INFO, string.format(
      "resolution-based-zoom: zoom key 0x%02X%s, zoom out key 0x%02X, reset id %s.",
      zoomInKey, singleKeyMode and " (Ctrl to zoom out)" or "",
      zoomOutKey or 0, tostring(resetResolutionID)))
  end,

  disable = function(self, config) end,

}
'''
initlua = initlua.replace("__VK_TABLE__",
                          "\n".join("  %s = 0x%02X," % (n, vk) for n, vk, _ in keys))
initlua = initlua.replace("__RESET_TABLE__",
                          "\n".join("  r%dx%d = %d," % (w, h, i)
                                    for i, w, h in sorted(RESOLUTIONS,
                                                          key=lambda r: r[1] * r[2])))
initlua = initlua.replace("__RESOLUTION_TABLE__",
                          "\n".join("  [%d] = { width = %d, height = %d },  -- %s"
                                    % (i, w, h, ('%.4f' % (w / h)).rstrip('0').rstrip('.'))
                                    for i, w, h in RESOLUTIONS))

GENERATED = [('definition.yml', definition), ('options.yml', options),
             ('init.lua', initlua), ('locale/en.yml', locale),
             ('locale/description-en.md', description)]


def field(key):
    for line in definition.splitlines():
        if line.startswith(key + ':'):
            return line.split(':', 1)[1].strip()
    raise KeyError(key)


for rel, content in GENERATED:
    path = os.path.join(OUT, rel.replace('/', os.sep))
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)
    print('wrote', rel, len(content))

if args.install:
    target = os.path.join(args.install, '%s-%s' % (field('name'), field('version')))
    os.makedirs(os.path.join(target, 'locale'), exist_ok=True)
    for rel, _ in GENERATED:
        shutil.copy2(os.path.join(OUT, rel.replace('/', os.sep)),
                     os.path.join(target, rel.replace('/', os.sep)))
    print('installed to', target)
