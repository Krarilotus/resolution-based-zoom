# Input and display ownership

When Custom Hotkeys exposes `registerAction`, it owns zoom input, profiles and
the binding editor. Zoom registers two local world actions during module
enable and suggests Ctrl+wheel. The earlier `registerActionHandler` provider
remains supported. Without either API, Zoom uses the original keyboard route
from `619e426` with its saved options. It leaves Legacy's key table alone while
Legacy WASD is active. The generic registration path uses the existing Hotkeys
catalog, context, message chain and profile store.

For display actions, inspected `ui` 1.0.1 (`ui/game.lua`, `init.lua`, header and
manager) exposes menu/render primitives, not a resolution-step/apply API.
`graphicsApiReplacer` at `473774d` exposes enable/disable and owns display
handling; it does not export this action. The existing native video-options
action remains the smallest available boundary, resolved using framework
`core.AOBScan`/`exposeCode`, cdecl with one item argument (apply item 0x12).
Its signature now includes its switch context. No numeric executable address
is used as a runtime binding.

The optional menu-resolution reset defaults OFF. With Grid Overlay active,
Zoom leaves the shared screen-transition hook to the overlay and logs why
automatic reset is unavailable. Zoom's manual controls remain active.
Supporting both features together requires a common screen-lifecycle owner.

Offline tests check resolution order, supported sizes, aspect-ratio filtering,
end stops, native Z zoom preservation and reset behavior. Hotkeys tests cover
modifier/wheel consumption, fractional turns, cancellation, unavailable providers,
profile migration and binding conflicts in Lua 5.4 and LuaJIT. These are component
tests, not gameplay/graphics/Recorder acceptance. SHC/Extreme native acceptance
and installed launcher layouts remain pending; multiplayer testing is player-owned.
