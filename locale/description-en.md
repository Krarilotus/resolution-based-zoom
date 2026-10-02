# Resolution Based Zoom

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
