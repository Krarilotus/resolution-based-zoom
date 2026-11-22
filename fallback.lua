-- Original Zoom keyboard path for installations without the action API.
-- The display action and screen list are supplied by init.lua.
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

-- The prologue every in-game key handler shares, pinned to the game-speed-up one:
--   test ecx,0x40000000 / jne tail / mov ecx,screenObject / call isInGameScreen /
--   test eax,eax / je tail / cmp dword [menuGuard],-1 / jne tail
-- `menuGuard` is -1 exactly when the game is not capturing input for something else.
-- Stops at the menuGuard operand: ucp2-legacy's `o_gamespeed` rewrites the handler body
-- after it. This prefix matches five handler prologues and every one of them yields the
-- same two addresses.
local IN_GAME_GUARD_AOB = "F7 C1 00 00 00 40 0F 85 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 85 C0 "
    .. "0F 84 ? ? ? ? 83 3D ? ? ? ? FF"
local OFFSET_MENU_GUARD = 32
local MENU_GUARD_IDLE = -1

-- The same screen id read absolutely, inside a sibling of `isInGameScreen`:
--   cmp dword [screenID], 0x10 / je / xor eax,eax / ret / mov eax,[...] / cmp eax,4
local SCREEN_ID_AOB = "83 3D ? ? ? ? 10 74 03 33 C0 C3 A1 ? ? ? ? 83 F8 04"
local OFFSET_SCREEN_ID = 2

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

local function legacyKeysActive()
  if not modules['ucp2-legacy'] then return false end
  for _,extension in ipairs(allActiveExtensions or {}) do
    if extension.name=='ucp2-legacy' then
      local effective=configFinal and configFinal[extension.name..'-'..extension.version]
      return not effective or not effective.o_keys or effective.o_keys.enabled~=false
    end
  end
  return true
end

return function(config, inGameScreens, scanOptional, zoomIn, zoomOut)
  local screenIDSite = scanOptional(SCREEN_ID_AOB, "the current screen id")
  local guardSite = scanOptional(IN_GAME_GUARD_AOB, "the in-game input guard")
  if not screenIDSite or not guardSite or not next(inGameScreens) then return end
  local state = {
    screenID = core.readInteger(screenIDSite + OFFSET_SCREEN_ID),
    inGameScreens = inGameScreens,
    menuGuard = core.readInteger(guardSite + OFFSET_MENU_GUARD),
  }
  local hotkeyConfig = config.hotkey or {}
  local singleKeyMode = (hotkeyConfig.mode or "one_key") == "one_key"

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

  local dispatchSite = scanOptional(KEY_DISPATCH_AOB, "the keyboard dispatch")
  if dispatchSite == nil then return end

  -- Exactly the keys this module listens to, and no others: in one-key mode that is
  -- the zoom key alone, since the zoom out key is never read there.
  local boundKeys = { zoomInKey }
  if zoomOutKey ~= nil then
    boundKeys[#boundKeys + 1] = zoomOutKey
  end

  -- Optional: repoint those keys at the do-nothing case so they only zoom. Left alone
  -- by default, in which case a key keeps whatever the game does with it (E, for one,
  -- also sets selected troops to aggressive) and the zoom happens on top.
  if hotkeyConfig.suppress_vanilla == true and not legacyKeysActive() then
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
        if singleKeyMode and isKeyHeld(getAsyncKeyState, 0x11) then
          zoomOut()
        else
          zoomIn()
        end
      elseif registers.ESI == zoomOutKey then
        zoomOut()
      end
    end
    return registers
  end, dispatchSite + OFFSET_DISPATCH_JUMP, SIZE_DISPATCH_JUMP)
end
