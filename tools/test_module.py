"""Run init.lua against a fake game, without launching Stronghold Crusader.

The module is pure Lua over a handful of `core.*` calls, so it can be exercised offline:
this script loads init.lua into a Lua runtime, hands it a `core` table backed by a
dictionary standing in for game memory, calls `enable`, and then invokes the registered display actions. Input routing is tested by Custom Hotkeys.

    pip install lupa
    python tools/test_module.py

Every check prints what it did and the script exits non-zero if any assertion fails.
"""

import os
import sys

import lupa

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = open(os.path.join(REPO, 'init.lua'), encoding='utf-8').read()

# Resolution id -> size, mirroring the table in init.lua.
RESOLUTIONS = {1: (800, 600), 2: (1024, 768), 3: (1280, 720), 4: (1280, 1024),
               5: (1366, 768), 6: (1440, 900), 7: (1600, 900), 8: (1600, 1200),
               9: (1680, 1050), 10: (1920, 1080), 11: (1920, 1200), 12: (2560, 1440),
               13: (2560, 1600), 14: (1360, 768), 15: (1024, 600)}

# Addresses for the fake game. Arbitrary, but distinct.
STATE_SITE, PENDING, WINDOW, DISPATCH = 0x1000, 0x2000, 0x3000, 0x4000
ZOOM_SITE, MENU_ZOOM, LIVE_ZOOM = 0x6000, 0x7000, 0x7004
SCREEN_SITE, INGAME_SITE, SCREENID_SITE, GUARD_SITE = 0x8200, 0x8300, 0x8400, 0x8500
SCREEN_ID, MENU_GUARD = 0x8600, 0x8604
CASE_TARGETS, TAIL = 0xC000, 0xD000
CASE_COUNT = 41
NO_ACTION_CASE = 40
KEY_CASES = CASE_TARGETS + CASE_COUNT * 4     # the byte table sits right after, as in game
SUPPORTED = WINDOW + 0x68

ON_MAP, IN_MENU = 0x10, 0x31
GUARD_IDLE = -1

# A display that can do 4:3, 5:4, 16:10 and 16:9 sizes, but not 2560-wide ones.
DISPLAY = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 15}

failures = []


def check(label, got, want):
    ok = got == want
    print('  %-46s %s' % (label, got if ok else '%s  (expected %s)' % (got, want)))
    if not ok:
        failures.append('%s: got %r, expected %r' % (label, got, want))


def pattern_site(pattern):
    """Stand in for core.AOBScan: map each of the module's patterns to a fake address."""
    for prefix, address in (('A1 ? ? ? ? 83 F8 01', STATE_SITE),
                            ('8D 46 F8', DISPATCH),
                            ('A1 ? ? ? ? 3B 05', ZOOM_SITE),
                            ('83 FD 17', SCREEN_SITE),
                            ('8B 41 0C', INGAME_SITE),
                            ('83 3D', SCREENID_SITE),
                            ('F7 C1', GUARD_SITE)):
        if pattern.startswith(prefix):
            return address
    return 0x9000                                    # video options menu handler


class Game(object):
    """A fake Stronghold Crusader: just enough memory for the module to work on."""

    def __init__(self, resolution=10, screen=ON_MAP, guard=GUARD_IDLE,
                 live_zoom=0, menu_zoom=0, display=DISPLAY, window=(1920, 1080),
                 missing=()):
        self.words = {
            STATE_SITE + 1: PENDING, STATE_SITE + 0x45: SUPPORTED,
            ZOOM_SITE + 1: MENU_ZOOM, ZOOM_SITE + 7: LIVE_ZOOM,
            SCREENID_SITE + 2: SCREEN_ID, GUARD_SITE + 32: MENU_GUARD,
            DISPATCH + 8: TAIL - (DISPATCH + 12),     # rel32 of `ja tail`
            DISPATCH + 15: KEY_CASES, DISPATCH + 22: CASE_TARGETS,
            SCREEN_ID: screen, MENU_GUARD: guard,
            MENU_ZOOM: menu_zoom, LIVE_ZOOM: live_zoom,
            WINDOW + 0x08: window[0], WINDOW + 0x0C: window[1],
            WINDOW + 0x5C: resolution, PENDING: resolution,
        }
        for index in range(16):
            self.words[SUPPORTED + index * 4] = 1 if index in display else 0
        for index in range(CASE_COUNT):
            self.words[CASE_TARGETS + index * 4] = TAIL if index == NO_ACTION_CASE \
                else 0x400000 + index

        self.bytes = {INGAME_SITE + 5: 0x0C, INGAME_SITE + 10: 0x0E,
                      INGAME_SITE + 15: 0x10}
        for index in range(0x72):                     # plausible vanilla-ish case table
            self.bytes[KEY_CASES + index] = NO_ACTION_CASE if index % 9 == 0 else index % 39

        self.missing = set(missing)
        self.key_writes = {}
        self.hooks = {}

    # --- the core.* surface the module uses ---------------------------------------
    def scan(self, pattern):
        address = pattern_site(pattern)
        if address in self.missing:
            raise lupa.LuaError('AOB could not be found: ' + pattern)
        return address

    def apply_video_options(self, item):
        assert item == 0x12, 'only the apply item should be called, got %#x' % item
        self.words[WINDOW + 0x5C] = self.words[PENDING]
        # The game forces the live zoom to the menu's copy at the end of apply.
        if self.words[MENU_ZOOM] != self.words[LIVE_ZOOM]:
            self.words[LIVE_ZOOM] = self.words[MENU_ZOOM]

    def expose(self, address, argc, convention):
        if address == 0x9000:
            return self.apply_video_options
        raise AssertionError("unexpected native action binding")

    def detour(self, callback, address, size):
        self.hooks['screen' if address == SCREEN_SITE else 'key'] = callback

    # --- driving it ----------------------------------------------------------------
    def start(self, config):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        globals_ = self.lua.globals()
        globals_.core = self.lua.table_from({
            'AOBScan': self.scan,
            'readInteger': lambda a: self.words.get(a, 0),
            'readByte': lambda a: self.bytes.get(a, 0),
            'writeInteger': lambda a, v: self.words.__setitem__(a, v),
            'writeCodeByte': lambda a, v: self.key_writes.__setitem__(a, v),
            'itob': lambda v: self.lua.table_from(
                [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]),
            'allocateCode': lambda data: 0xA000,
            'exposeCode': self.expose,
            'detourCode': self.detour,
        })
        globals_.log = lambda level, message: None
        globals_.WARNING, globals_.INFO = -1, 0

        self.actions = {}
        def register(_, action, callback):
            assert action not in self.actions
            self.actions[action] = callback
        globals_.register_external = register
        api = self.lua.eval('function(self, id, callback) return register_external(self,id,callback) end')
        globals_.modules = self.lua.table_from({'custom-hotkeys': self.lua.table_from({'registerActionHandler': api})})
        module = self.lua.eval('load')(SOURCE, 'init.lua')()
        module.enable(module, self.lua.table_from(
            {k: self.lua.table_from(v) for k, v in config.items()}))
        return self

    def zoom(self, action):
        assert action in ('in', 'out')
        self.actions['view.resolution-zoom-' + action]()
        return self

    def change_screen(self, screen):
        self.words[SCREEN_ID] = screen
        if 'screen' in self.hooks:
            self.hooks['screen'](self.lua.table_from({'EBP': screen}))
        return self

    # --- readouts ------------------------------------------------------------------
    @property
    def resolution(self):
        return '%dx%d' % RESOLUTIONS[self.words[WINDOW + 0x5C]]

    @property
    def vanilla_zoom(self):
        return self.words[LIVE_ZOOM]

    @property
    def suppressed_keys(self):
        return sorted(address - KEY_CASES + 8 for address in self.key_writes)




def main():
    print('zoom ladder: only window-shaped sizes, smallest to largest, no wrap')
    game = Game().start({})
    check('zoom in', game.zoom('in').resolution, '1600x900')
    check('zoom in', game.zoom('in').resolution, '1366x768')
    check('zoom in', game.zoom('in').resolution, '1280x720')
    check('zoom in at the smallest step stays put', game.zoom('in').resolution, '1280x720')
    check('zoom out', game.zoom('out').resolution, '1366x768')
    check('zoom out', game.zoom('out').resolution, '1600x900')
    check('zoom out', game.zoom('out').resolution, '1920x1080')
    check('zoom out at the largest step stays put', game.zoom('out').resolution, '1920x1080')

    print('\n1360x768 is dropped: too close to 1366x768 to be a real step')
    check('ladder never lands on it',
          '1360x768' not in [Game().start({}).zoom('in').resolution], True)

    print('\na 4:3 window zooms through 4:3 sizes only')
    game = Game(window=(1024, 768), resolution=2).start({})
    check('zoom in', game.zoom('in').resolution, '800x600')
    check('zoom out', game.zoom('out').resolution, '1024x768')
    check('zoom out', game.zoom('out').resolution, '1600x1200')

    print('\nstarting off-ladder (5:4 on a 16:9 window) snaps onto it')
    game = Game(resolution=4).start({})
    check('first action snaps to the nearest step', game.zoom('in').resolution, '1600x900')

    print('\nthe two provider actions select opposite directions')
    game = Game().start({})
    check('zoom in', game.zoom('in').resolution, '1600x900')
    check('zoom out', game.zoom('out').resolution, '1920x1080')
    check('zoom out stops at the largest supported step', game.zoom('out').resolution, '1920x1080')

    print('\nthe vanilla Z zoom survives a resolution change')
    for live in (0, 1):
        for menu in (0, 1):
            game = Game(live_zoom=live, menu_zoom=menu).start({})
            game.zoom('in').zoom('in').zoom('out')
            check('live=%d menu=%d' % (live, menu), game.vanilla_zoom, live)

    # Focus, modal/text eligibility, keyboard/wheel capture and suppression are
    # tested in Custom Hotkeys. This module installs no input hook.

    print('\nleaving the map restores the configured size')
    config = dict({}, reset={'resolution': 'r1920x1080'})
    game = Game().start(config).zoom('in').zoom('in')
    check('zoomed in', game.resolution, '1366x768')
    check('still on the map', game.change_screen(0x0E).resolution, '1366x768')
    check('left to a menu', game.change_screen(IN_MENU).resolution, '1920x1080')

    game = Game().start(dict({}, reset={'resolution': 'r2560x1440'}))
    game.zoom('in').change_screen(IN_MENU)
    check('a size the display cannot do is skipped', game.resolution, '1600x900')

    check('no keyboard dispatcher hook', 'key' in Game().start({}).hooks, False)
    check('no keyboard table writes', Game().start({}).suppressed_keys, [])

    print()
    if failures:
        print('FAILED (%d):' % len(failures))
        for failure in failures:
            print('  ' + failure)
        return 1
    print('all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
