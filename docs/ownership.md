# Input and display ownership

Custom Hotkeys 0.2.3 owns the zoom bindings, Ctrl+wheel routing, conflict checks,
profile storage and editing. This module registers two callbacks through its
public `registerActionHandler` API. It no longer scans the keyboard dispatcher,
reads Ctrl through a private Win32 thunk, modifies key tables or duplicates a
binding editor. Existing Zoom key settings are superseded by Hotkeys profiles;
they are not copied over native stance keys. Existing Hotkeys choices take
precedence during schema migration. No game save/map extension is introduced.

The inspected Custom Hotkeys parent is `844d54d`; its matching provider/wheel PR
is a prerequisite. `code/messages.lua`, `code/router.lua`, `code/profiles.lua`
and `code/native/chain.lua` retain their native context and Windows-chain owners.
The callback is registered during module enable, before Hotkeys starts in
`afterInit`. Missing, duplicate or late registration fails explicitly.

For display actions, inspected `ui` 1.0.1 (`ui/game.lua`, `init.lua`, header and
manager) exposes menu/render primitives, not a resolution-step/apply API.
`graphicsApiReplacer` at `473774d` exposes enable/disable and owns display
handling; it does not export this action. The existing native video-options
action remains the smallest available boundary, resolved using framework
`core.AOBScan`/`exposeCode`, cdecl with one item argument (apply item 0x12).
Its signature now includes its switch context. No numeric executable address
is used as a runtime binding.

The existing optional menu-resolution reset is preserved and defaults OFF. Its
screen-change hook can conflict with Grid Overlay; this PR does not claim that
shared observer ownership is solved. Both projects need a common screen-lifecycle
owner rather than silently letting the first hook win.

Offline tests check resolution order, supported sizes, aspect-ratio filtering,
end stops, native Z zoom preservation and reset behavior. Hotkeys tests cover
modifier/wheel consumption, fractional turns, cancellation, unavailable providers,
profile migration and binding conflicts in Lua 5.4 and LuaJIT. These are component
tests, not gameplay/graphics/Recorder acceptance. SHC/Extreme native acceptance
and installed launcher layouts remain pending; multiplayer testing is player-owned.
