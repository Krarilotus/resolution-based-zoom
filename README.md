# Resolution Based Zoom

Adds zoom steps by switching between supported display resolutions. The native Z
zoom stays available. Each step changes display mode and can briefly flicker.

With the generic action API enabled in Custom Hotkeys, Ctrl+wheel up zooms in
and Ctrl+wheel down zooms out. Ordinary scrolling keeps its normal action.
Change or clear either binding in **Options > Custom Hotkeys**. The bindings
apply in live matches while the game has focus. A successful change uses the
game's ordinary confirmation sound.

Without Custom Hotkeys, the original E / Ctrl+E controls apply. Older
`hotkey.mode`, `hotkey.zoom_in`, `hotkey.zoom_out`, and
`hotkey.suppress_vanilla` configuration values still apply in standalone mode. With Legacy WASD active,
its native key table takes precedence over Zoom suppression.
The earlier Custom Hotkeys wheel preview also works when its
`registerActionHandler` API is available.

The optional menu-resolution setting returns to a chosen resolution after leaving
the map. It is off by default. See [ownership and remaining acceptance](docs/ownership.md).

Run `python tools/test_module.py` for component checks. The eight non-English
action labels and description edits are machine translations pending human review.
