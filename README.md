# Resolution Based Zoom

Adds zoom steps by switching between supported screen resolutions. The native Z
zoom stays available. Each step changes display mode, so a brief flicker is possible.

Enable Custom Hotkeys 0.2.3 and this module. Ctrl+wheel up zooms in; Ctrl+wheel down
zooms out. Ordinary scrolling keeps its normal action. Change or clear either
binding in **Options > Custom Hotkeys**. Zoom input is inactive in menus, text entry
and unfocused windows.

The optional menu-resolution setting returns to a chosen resolution after leaving
the map. It remains off by default. Settings from the old Zoom key dropdowns are
superseded by Hotkeys profiles; explicit Hotkeys choices are preserved.

The module owns the resolution ladder and native display action. Custom Hotkeys
owns input, conflict checks and profiles. See [ownership and remaining acceptance](docs/ownership.md).
Runtime source and option files are maintained directly; there is no generated
duplicate of the module code. Tools and tests are excluded by `files.xml`.

Run `python tools/test_module.py` for offline component checks. These do not replace
normal Crusader/Extreme gameplay, graphics or Recorder validation.
