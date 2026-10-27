"""Run the MIT-licensed original Pokebot Lua controller on PyBoy.

Original Lua controller: Copyright (c) 2014 Kyle Coburn and Michael Jondahl,
MIT licensed; see LICENSE for the full retained notice.
Source commit: 2e882849cac6e9b6a6ce62dcd689c64160d1d51e (version 2.4.8).
The bot's gameplay modules remain untouched. This adapter exposes read-only
WRAM observations and one-frame controller overrides, with local evidence.
No save states, game-memory writes, or desktop input are used.
"""
import argparse
import io
import shutil
from runtime_config import rom_path
import hashlib
import json
import subprocess
import time
from pathlib import Path

from lupa.lua51 import LuaRuntime
from pyboy import PyBoy
from control import png

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'candidates' / 'refstrat-v94' / 'engine'
FPS = 4194304 / 70224


class AttemptDone(Exception):
    pass


class Attempt:
    def __init__(self, seed, max_frames, folder, record=False, goal='brock', finish_hold=0, variant='baseline'):
        self.seed, self.max_frames, self.folder = seed, max_frames, folder
        self.goal = goal
        self.variant = variant
        self.patch_file = ROOT / 'upgrades' / (variant + '.lua') if variant != 'baseline' else None
        self.patch_files = ([ROOT / 'upgrades/agatha-v1.lua'] if variant in ('elite-v2', 'pp-v3', 'agatha-v4', 'lance-v5', 'lance-v6', 'lance-v7', 'lance-v8', 'menu-v9', 'menu-v10', 'menu-v11', 'blue-v12', 'blue-v13', 'blue-v14', 'menu-v15', 'menu-v16', 'menu-v17', 'menu-v18', 'menu-v19', 'menu-v20', 'wr-blizzard-v21', 'wr-blizzard-v22', 'wr-route-v23', 'wr-route-v24', 'wr-route-v25', 'wr-route-v26', 'wr-route-v27', 'wr-route-v28', 'wr-route-v29', 'wr-route-v30', 'wr-route-v31', 'wr-route-v32', 'wr-route-v33', 'wr-route-v34', 'wr-route-v35', 'refine-v36', 'refine-v37', 'refine-v38') else []) + ([self.patch_file] if self.patch_file else [])
        self.finish_hold = finish_hold
        folder.mkdir(parents=True, exist_ok=True)
        self.frames = 0
        self.started = None
        self.wall_start = time.monotonic()
        self.pending, self.held = set(), set()
        self.last_input = None
        self.splits = []
        self.brock_split = None
        self.champion_split = None
        self.hall_of_fame_seen = False
        self.report = None
        self.outcome = 'incomplete'
        self.reason = None
        self.video = None
        self.record = record
        self.video_frames = 0
        if record:
            from PIL import Image, ImageDraw, ImageFont
            self.Image, self.ImageDraw = Image, ImageDraw
            self.font = ImageFont.load_default(size=13)
            self.title_font = ImageFont.load_default(size=16)
            self.video_log = (folder / 'video-encode.log').open('w')
            self.video = subprocess.Popen([
                shutil.which('ffmpeg') or 'ffmpeg',
                '-hide_banner', '-loglevel', 'warning', '-y', '-f', 'rawvideo',
                '-pixel_format', 'rgb24', '-video_size', '640x480',
                '-framerate', str(FPS / 2), '-i', 'pipe:0',
                '-vf', 'scale=1280:960:flags=neighbor', '-c:v', 'libx264',
                '-threads', '2', '-preset', 'veryfast', '-crf', '20',
                '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
                str(folder / 'pokebot-brock.mp4')], stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL, stderr=self.video_log)
        self.logs = (folder / 'bot.log').open('w', encoding='utf-8')
        self.actions = (folder / 'actions.jsonl').open('w', encoding='utf-8')
        self.strategy_events = (folder / 'strategy-events.jsonl').open('w', encoding='utf-8')
        self.gb = PyBoy(str(rom_path()), window='null', sound_emulated=False, ram_file=io.BytesIO(bytes(0x8000)))
        self.gb.set_emulation_speed(0)
        # Lua's original bootstrap explicitly expects frame 1 on initial load.
        self.gb.tick(1, True)
        self.frames = 1
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.memory = self.lua.table_from({
            'readbyte': self.readbyte,
            'getcurrentmemorydomainsize': lambda: 8192,
        })
        g.emu = self.lua.table_from({'framecount': lambda: self.frames,
                                     'frameadvance': self.advance})
        g.joypad = self.lua.table_from({'set': self.set_input})
        g.client = self.lua.table_from({k: self.noop for k in (
            'pause', 'unpause', 'speedmode', 'setscreenshotosd')})
        g.client.screenshot = lambda *args: self.snapshot('bot-screenshot.png')
        g.gui = self.lua.table_from({'text': self.noop, 'cleartext': self.noop})
        g.bit = self.lua.table_from({'band': lambda a, b: int(a) & int(b),
                                    'rshift': lambda a, b: int(a) >> int(b)})
        g.print = self.log
        g.port_start = self.start
        g.port_split = self.split
        g.port_report = self.on_report
        g.port_strategy = self.on_strategy
        self.lua.execute('package.path = ' + json.dumps(SOURCE.as_posix() + '/?.lua;') + ' .. package.path')
        self.lua.execute('package.preload["socket"] = function() return {connect=function() return nil end} end')

    @staticmethod
    def noop(*args):
        return None

    def readbyte(self, address):
        address = int(address)
        if not 0 <= address < 8192:
            raise ValueError(f'WRAM read outside domain: {address}')
        return self.gb.memory[0xC000 + address]

    def igtime(self):
        m = self.gb.memory
        return m[0xDA41] * 3600 + m[0xDA43] * 60 + m[0xDA44] + m[0xDA45] / 60

    def observation(self):
        m = self.gb.memory
        return dict(frame=self.frames, game_seconds=self.igtime(),
                    elapsed_seconds=None if self.started is None else (self.frames - self.started) / FPS,
                    map=m[0xD35E], x=m[0xD362], y=m[0xD361],
                    battle=m[0xD057], badges=m[0xD356],
                    party_count=m[0xD163], party_species=list(m[0xD164:0xD16B]),
                    hall_of_fame_teams=m[0xD5A2], hall_of_fame_script=m[0xD64B])

    def log(self, *args):
        self.logs.write(f'{self.frames}: ' + ' '.join(map(str, args)) + '\n')
        self.logs.flush()

    def snapshot(self, name):
        self.gb.tick(0, True)
        png(self.folder / name, self.gb.screen.ndarray[:, :, :3])

    @staticmethod
    def clock(seconds):
        if seconds is None:
            return '--:--'
        return f'{int(seconds // 60)}:{seconds % 60:05.2f}'

    def video_frame(self):
        im = self.Image.new('RGB', (640, 480), '#101a19')
        game = self.Image.fromarray(self.gb.screen.ndarray[:, :, :3]).resize(
            (480, 432), self.Image.Resampling.NEAREST)
        im.paste(game, (8, 24))
        d = self.ImageDraw.Draw(im)
        def line(y, s, color='#d8e9e1', bold=False):
            d.text((502, y), s, fill=color, font=self.title_font if bold else self.font)
        line(25, 'POKEBOT', '#77ddbd', True)
        line(48, 'Original Lua')
        line(65, 'v2.4.8')
        line(100, 'GAME TIMER')
        line(121, self.clock(self.igtime()), '#77ddbd', True)
        line(156, 'ELAPSED')
        elapsed = None if self.started is None else (self.frames - self.started) / FPS
        line(177, self.clock(elapsed), bold=True)
        line(220, 'Brock ref:')
        line(240, '10:32 game')
        if self.brock_split:
            line(270, 'Brock split:')
            line(291, self.clock(self.brock_split['game_seconds']), '#77ddbd', True)
        buttons = '+'.join(b.upper() for b in sorted(self.held)) or '--'
        line(335, 'INPUT')
        line(355, buttons)
        line(394, 'Badge: ' + str(self.gb.memory[0xD356] & 1))
        line(425, 'Seed:')
        line(445, str(self.seed))
        self.video.stdin.write(im.tobytes())
        self.video_frames += 1

    def set_input(self, table):
        buttons = {str(k).lower() for k, v in table.items() if v}
        if 'power' in buttons:
            self.reason = 'Original bot requested a hard reset'
            self.outcome = 'reset'
            raise AttemptDone(self.reason)
        allowed = {'up', 'down', 'left', 'right', 'a', 'b', 'start', 'select'}
        if not buttons <= allowed:
            raise ValueError(f'Unknown controller input: {buttons - allowed}')
        self.pending = buttons

    def advance(self):
        for button in self.held - self.pending:
            self.gb.button_release(button)
        for button in self.pending - self.held:
            self.gb.button_press(button)
        trace = tuple(sorted(self.pending))
        if trace != self.last_input:
            self.actions.write(json.dumps({'frame': self.frames, 'buttons': trace}) + '\n')
            self.last_input = trace
        self.held, self.pending = self.pending, set()
        self.gb.tick(1, self.record or getattr(self, 'render_all_frames', False) or self.frames % 120 == 0 or
                     (self.goal == 'full' and self.gb.memory[0xD35E] == 118))
        self.frames += 1
        if self.record and self.frames % 2 == 0:
            self.video_frame()
        if self.brock_split is not None and self.goal == 'brock':
            m = self.gb.memory
            # The original bot splits immediately after battle, before the badge
            # dialogue. Continue its inputs until the badge and clear overworld.
            bottom = list(m[0xC3A0 + 20 * 12:0xC3A0 + 20 * 18])
            has_text = any(0x80 <= v <= 0xB9 for v in bottom)
            if m[0xD356] & 1 and m[0xD057] == 0 and m[0xD35E] == 54 and not has_text:
                self.outcome = 'success'
                self.reason = 'Original Brock split recorded; Boulder Badge and closed post-battle dialogue verified'
                raise AttemptDone(self.reason)
        if self.goal == 'full':
            if self.gb.memory[0xD35E] == 118 and self.gb.memory[0xD5A2] > 0:
                self.hall_of_fame_seen = True
            if self.outcome == 'success' and self.champion_split is not None:
                if self.frames >= self.champion_split['frame'] + self.finish_hold:
                    raise AttemptDone(self.reason)
            elif self.started is not None and self.igtime() >= 7200:
                self.outcome, self.reason = 'over_limit', 'Two-hour game-time limit exceeded before verified completion'
                raise AttemptDone(self.reason)
        if self.frames % (30000 if self.goal == 'full' else 6000) == 0:
            self.snapshot('progress.png')
            state = self.observation()
            state['strategy'] = getattr(self, 'strategy', None)
            (self.folder / 'status.json').write_text(json.dumps(state, indent=2))
            print(json.dumps({'seed': self.seed, **state}), flush=True)
        if self.frames >= self.max_frames:
            self.outcome, self.reason = 'timeout', 'Emulated frame budget exceeded'
            raise AttemptDone(self.reason)

    def start(self):
        if self.started is None:
            self.started = self.frames
            self.log('New Game / original timer start', self.observation())

    def split(self, finished=None):
        state = self.observation()
        self.splits.append(state)
        self.snapshot(f'split-{len(self.splits)}.png')
        self.log('split', state)
        if getattr(self, 'strategy', None) == 'splitBrock' and state['battle'] == 0:
            self.brock_split = state
        if finished and self.goal == 'full':
            self.champion_split = state
            m = self.gb.memory
            if state['map'] == 118 and state['badges'] == 255 and state['battle'] == 0 and m[0xD5A2] > 0:
                self.hall_of_fame_seen = True
                self.outcome = 'success' if state['game_seconds'] < 7200 else 'over_limit'
                self.reason = 'Original final split verified: Hall of Fame, registered team, eight badges and no battle'
                if self.finish_hold == 0 or self.outcome != 'success':
                    raise AttemptDone(self.reason)
                return
            self.log('FINAL SPLIT FAILED INDEPENDENT VERIFICATION', state)

    def on_report(self, report):
        self.report = json.loads(report)
        self.log('report', report)

    def on_strategy(self, name):
        if getattr(self, 'strategy', None) != name:
            m = self.gb.memory
            double = lambda addr: m[addr] * 256 + m[addr + 1]
            self.strategy_events.write(json.dumps(dict(strategy=name,
                party_hp=double(0xD16C), party_speed=double(0xD193),
                battle_speed=double(0xD029), opponent_speed=double(0xCFFA),
                battle_hp=double(0xD015), opponent_hp=double(0xCFE6),
                party_pp=list(m[0xD188:0xD18C]),
                battle_pp=list(m[0xD02D:0xD031]), **self.observation())) + '\n')
            self.strategy_events.flush()
        self.strategy = name

    def run(self):
        source = (SOURCE / 'main.lua').read_text(encoding='utf-8')
        source = source.replace('local CUSTOM_SEED  = nil', f'local CUSTOM_SEED  = {self.seed}')
        source = source.replace('local PAINT_ON     = true', 'local PAINT_ON     = false')
        source = source.replace('"./wiki/red/resets.txt"', json.dumps((self.folder / 'resets.txt').as_posix()))
        source = source.replace('"./wiki/red/victories.txt"', json.dumps((self.folder / 'victories.txt').as_posix()))
        hooks = '''
local originalStart = Bridge.liveSplit
Bridge.liveSplit = function() port_start(); return originalStart() end
local originalSplit = Bridge.split
Bridge.split = function(finished) originalSplit(finished); port_split(finished) end
local originalReport = Bridge.report
Bridge.report = function(report) port_report(require("external.json").encode(report)); return originalReport(report) end
local originalExecute = Strategies.execute
Strategies.execute = function(data) port_strategy(data.s); return originalExecute(data) end
'''
        for patch in self.patch_files:
            hooks += '\n' + patch.read_text(encoding='utf-8') + '\n'
        source = source.replace('-- EXECUTE', hooks + '\n-- EXECUTE', 1)
        try:
            self.lua.execute(source)
        except AttemptDone:
            pass
        except Exception as exc:
            self.outcome, self.reason = 'error', str(exc)
            self.log('ERROR', self.reason)
        finally:
            self.snapshot('finish.png')
            if self.video is not None:
                # Hold the actual verified finish for three seconds in playback.
                for _ in range(round(3 * FPS / 2)):
                    self.video_frame()
                self.video.stdin.close()
                self.video.wait(timeout=60)
                self.video_log.close()
            result = dict(outcome=self.outcome, reason=self.reason, seed=self.seed,
                          goal=self.goal,
                          variant=self.variant,
                          upgrade_sha256=hashlib.sha256(b''.join(patch.read_bytes() for patch in self.patch_files)).hexdigest() if self.patch_files else None,
                          upgrade_files=[str(patch) for patch in self.patch_files],
                          finish_hold_frames=self.finish_hold,
                          bot_version='2.4.8', method='Pokebot Lua through PyBoy with separately recorded optional gameplay upgrade; fresh boot; controller only; read-only WRAM',
                          time_basis='Game timer at original bot split; elapsed emulator time also retained',
                          wall_seconds=time.monotonic() - self.wall_start,
                          source_main_sha256=hashlib.sha256((SOURCE / 'main.lua').read_bytes()).hexdigest(),
                          start_frame=self.started, splits=self.splits, report=self.report,
                          brock_split=self.brock_split,
                          champion_split=self.champion_split, hall_of_fame_seen=self.hall_of_fame_seen,
                          strategy=getattr(self, 'strategy', None), **self.observation())
            if self.champion_split is not None:
                result['completion_game_seconds'] = self.champion_split['game_seconds']
                result['completion_elapsed_seconds'] = self.champion_split['elapsed_seconds']
            if self.record:
                result['video'] = str(self.folder / 'pokebot-brock.mp4')
                result['video_encode_ok'] = self.video.returncode == 0
                result['video_frames'] = self.video_frames
            (self.folder / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
            self.actions.close()
            self.strategy_events.close()
            self.logs.close()
            self.gb.stop(save=False)
        return result


