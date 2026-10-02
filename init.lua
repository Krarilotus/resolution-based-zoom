-- Resolution Based Zoom: display actions only. Custom Hotkeys owns input.

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

-- Video options menu-item handler: mov eax, [esp+4] / add eax, 0x14 (its switch bias).
local VIDEO_OPTIONS_HANDLER_AOB = "8B 44 24 04 83 C0 14 83 F8 26 0F 87 ? ? ? ? 0F B6 80 ? ? ? ? FF 24 85 ? ? ? ? A1"
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

-- `requestScreenChange(this, screenID, param)`, three bytes into the body, where the
-- requested screen id is already in EBP and nothing has been written yet:
--   cmp ebp, 0x17 / push esi / mov esi, ecx
local SCREEN_CHANGE_AOB = "83 FD 17 56 8B F1 75 05 BD 29 00 00 00 8B 44 24 10 53 57 89 6E 18"
local SIZE_SCREEN_CHANGE_HOOK = 6

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

---@class ResolutionState
---@field pendingSelection number address of the resolution the apply action reads
---@field supportedResolutions number base of the per-id supported flags
---@field windowWidth number address of the game window's client width
---@field windowHeight number address of the game window's client height
---@field appliedResolution number address of the resolution currently on screen
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
    local hotkeys=assert(modules['custom-hotkeys'], 'Resolution Based Zoom requires Custom Hotkeys 0.2.3')
    assert(type(hotkeys.registerActionHandler)=='function', 'Custom Hotkeys action API is unavailable')
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

    local state = {
      pendingSelection = core.readInteger(resolutionStateSite + OFFSET_PENDING_SELECTION),
      supportedResolutions = supportedResolutions,
      windowWidth = windowStruct + WINDOW_WIDTH_IN_STRUCT,
      windowHeight = windowStruct + WINDOW_HEIGHT_IN_STRUCT,
      appliedResolution = windowStruct + APPLIED_RESOLUTION_IN_STRUCT,
      menuZoomSetting = core.readInteger(zoomSyncSite + OFFSET_MENU_ZOOM_SETTING),
      liveZoomFlag = core.readInteger(zoomSyncSite + OFFSET_LIVE_ZOOM_FLAG),
    }

    hotkeys:registerActionHandler('view.resolution-zoom-in', function() zoom(state, applyResolution, ZOOM_IN) end)
    hotkeys:registerActionHandler('view.resolution-zoom-out', function() zoom(state, applyResolution, ZOOM_OUT) end)

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

    log(INFO, 'Resolution Based Zoom actions registered with Custom Hotkeys')
  end,

  disable = function(self, config) end,

}
