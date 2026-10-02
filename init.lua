-- Resolution Based Zoom
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
  letter_a = 0x41,
  letter_b = 0x42,
  letter_c = 0x43,
  letter_d = 0x44,
  letter_e = 0x45,
  letter_f = 0x46,
  letter_g = 0x47,
  letter_h = 0x48,
  letter_i = 0x49,
  letter_j = 0x4A,
  letter_k = 0x4B,
  letter_l = 0x4C,
  letter_m = 0x4D,
  letter_n = 0x4E,
  letter_o = 0x4F,
  letter_p = 0x50,
  letter_q = 0x51,
  letter_r = 0x52,
  letter_s = 0x53,
  letter_t = 0x54,
  letter_u = 0x55,
  letter_v = 0x56,
  letter_w = 0x57,
  letter_x = 0x58,
  letter_y = 0x59,
  letter_z = 0x5A,
  f1 = 0x70,
  f2 = 0x71,
  f3 = 0x72,
  f4 = 0x73,
  f5 = 0x74,
  f6 = 0x75,
  f7 = 0x76,
  f8 = 0x77,
  f9 = 0x78,
  f10 = 0x79,
  numpad_add = 0x6B,
  numpad_subtract = 0x6D,
  numpad_multiply = 0x6A,
  numpad_divide = 0x6F,
  numpad_decimal = 0x6E,
  numpad_0 = 0x60,
  numpad_1 = 0x61,
  numpad_2 = 0x62,
  numpad_3 = 0x63,
  numpad_4 = 0x64,
  numpad_5 = 0x65,
  numpad_6 = 0x66,
  numpad_7 = 0x67,
  numpad_8 = 0x68,
  numpad_9 = 0x69,
  digit_0 = 0x30,
  digit_1 = 0x31,
  digit_2 = 0x32,
  digit_3 = 0x33,
  digit_4 = 0x34,
  digit_5 = 0x35,
  digit_6 = 0x36,
  digit_7 = 0x37,
  digit_8 = 0x38,
  digit_9 = 0x39,
  tab = 0x09,
  backspace = 0x08,
  enter = 0x0D,
  space = 0x20,
  caps_lock = 0x14,
  escape = 0x1B,
  insert = 0x2D,
  delete_key = 0x2E,
  home = 0x24,
  end_key = 0x23,
  page_up = 0x21,
  page_down = 0x22,
  arrow_left = 0x25,
  arrow_up = 0x26,
  arrow_right = 0x27,
  arrow_down = 0x28,
}

local DEFAULT_ZOOM_IN_KEY = "letter_e"
local DEFAULT_ZOOM_OUT_KEY = "letter_r"

-- Resolution id -> pixel size, matching the game's own hardcoded list. Id 0x14 (640x480)
-- is deliberately absent: it falls outside the 16-entry supported-resolution array.
local RESOLUTIONS = {
  [1] = { width = 800, height = 600 },  -- 1.3333
  [2] = { width = 1024, height = 768 },  -- 1.3333
  [3] = { width = 1280, height = 720 },  -- 1.7778
  [4] = { width = 1280, height = 1024 },  -- 1.25
  [5] = { width = 1366, height = 768 },  -- 1.7786
  [6] = { width = 1440, height = 900 },  -- 1.6
  [7] = { width = 1600, height = 900 },  -- 1.7778
  [8] = { width = 1600, height = 1200 },  -- 1.3333
  [9] = { width = 1680, height = 1050 },  -- 1.6
  [10] = { width = 1920, height = 1080 },  -- 1.7778
  [11] = { width = 1920, height = 1200 },  -- 1.6
  [12] = { width = 2560, height = 1440 },  -- 1.7778
  [13] = { width = 2560, height = 1600 },  -- 1.6
  [14] = { width = 1360, height = 768 },  -- 1.7708
  [15] = { width = 1024, height = 600 },  -- 1.7067
}

-- Choice name in options.yml -> resolution id, for the "screen size outside the map"
-- setting. Absent (including the "off" choice) means the reset is disabled.
local RESET_RESOLUTION_IDS = {
  r800x600 = 1,
  r1024x600 = 15,
  r1024x768 = 2,
  r1280x720 = 3,
  r1360x768 = 14,
  r1366x768 = 5,
  r1440x900 = 6,
  r1280x1024 = 4,
  r1600x900 = 7,
  r1680x1050 = 9,
  r1600x1200 = 8,
  r1920x1080 = 10,
  r1920x1200 = 11,
  r2560x1440 = 12,
  r2560x1600 = 13,
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
