"""refstrat adapter: the shared PokeBot/PyBoy adapter plus a console POWER CYCLE that keeps the cartridge's
battery save, as the reference runner does on an emulator ("Reset r717" overlay, after an in-game SAVE).

Lua calls port_power_cycle(). The emulator is stopped with its cartridge RAM written to an in-memory buffer
(never to red.gb.ram on disk), and a fresh PyBoy is started from the same ROM with only that save. Everything
else (RAM, HRAM, timers, PPU) starts from power-on like a real console. The Lua controller keeps running (its
logic must handle the title screen / CONTINUE). Frame counting continues, so normal-speed elapsed time includes
the reset; in-game time resumes from the saved value (category real-time comparisons must use elapsed time).
No save states, no memory writes.
"""
import io, os, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from pyboy import PyBoy
from runtime_config import rom_path
import pokebot_pyboy as _pb
import pokebot_pyboy_fast as fast
# v77 (Sol V76): the inherited constructor (pokebot_pyboy.py:73) opens red.gb without a ram_file. Give it an empty
# 32 KiB cartridge RAM so PyBoy never loads or writes red.gb.ram next to the ROM; refuse to start if one exists.
_PyBoy = _pb.PyBoy
def _fresh_pyboy(*a, **k):
    if Path(str(rom_path()) + '.ram').exists():
        raise RuntimeError('A cartridge RAM sidecar exists next to the supplied ROM; refusing a fresh boot')
    k.setdefault('ram_file', io.BytesIO(bytes(0x8000)))
    return _PyBoy(*a, **k)
_pb.PyBoy = _fresh_pyboy
# refstrat-v9 (from v8): run on the candidate's PRIVATE engine copy (candidates/refstrat-v9/engine, a copy of
# reference/PokeBotBad with the documented fixes in ENGINE_CHANGES.md); the shared engine stays untouched.
ENGINE = Path(__file__).resolve().parent / 'engine'
_pb.SOURCE = ENGINE
fast.SOURCE = ENGINE


class Attempt(fast.Attempt):
    def __init__(self, *args, **kwargs):
        from retention import adapter_folder
        folder = Path(args[2] if len(args)>2 else kwargs['folder'])
        seed = args[0] if args else kwargs['seed']
        record = args[3] if len(args)>3 else kwargs.get('record', False)
        self._retention_direct = adapter_folder(folder, seed, record)
        try:
            super().__init__(*args, **kwargs)
            self.power_cycles = []
            self.lua.globals().port_power_cycle = self.power_cycle
            # v11 runner-style clock tracker input (user-approved 2026-10-12): the number of emulated frames on which the
            # LCD was switched ON (LCDC bit 7 = whether the screen is displayed at all; the IGT only advances in V-blank, so
            # it pauses while the LCD is off - pastebin VFM1Ggah). This is display state, not the play-time or RNG bytes;
            # the Lua tracker (strategies.lua refClock*) does the synchronisation and pause accounting.
            self.lcd_frames = 0
            self.lua.globals().port_lcd_frames = lambda: self.lcd_frames
            self._turn_hook()
        except BaseException as ex:
            from retention import failed
            failed(folder, ex)
            raise

    def run(self):
        from retention import adapter_finish, failed
        try:
            result = super().run()
            if self._retention_direct: adapter_finish(self.folder, result)
            return result
        except BaseException as ex:
            failed(self.folder, ex)
            raise

    # v18 edit S: passive evaluator hook - one 'TURNEVAL' bot.log line per execution of SelectEnemyMove (bank 0x0F,
    # 0x5564 in pokered.sym), i.e. once per committed battle turn. Logging only; nothing reaches the controller.
    def _turn_hook(self):
        # v18 edit T: opt-in diagnostic only (PyBoy installs the hook by patching the emulated ROM opcode, review 4)
        if os.environ.get('REFSTRAT_TURN_HOOK', '0') != '1':
            return
        def cb(ctx):
            m = self.gb.memory
            # diagnostic: multi-turn states that skip the action menu (Bide, Thrash, charging, trapping, recharge; enemy trapping)
            self.log(f'TURNEVAL select_enemy_move pbs1={m[0xD062]} pbs2={m[0xD063]} ebs1={m[0xD067]}')
        self.gb.hook_register(0x0F, 0x5564, cb, None)

    # v13 (impl review 11:30 MATERIAL): the inherited runner (pokebot_pyboy.py Attempt.advance) stops a full game at
    # 7,200 s by reading the play-time bytes (igtime). Inside advance() that limit check (and the passive progress
    # snapshot) now get the approved LCD-on tracker estimate (lua REFSTRAT_IGT_FRAMES; emulator frames before the overlays
    # load). Every other igtime() use - split observations, results, the final split's evaluator check - stays the
    # actual play time (passive evaluation, after the decision).
    def igtime(self):
        if getattr(self, '_tracker_igt', False):
            f = self.lua.globals().REFSTRAT_IGT_FRAMES
            return (f() if f else self.frames) / 60
        return super().igtime()

    def advance(self):
        self._tracker_igt = True
        try:
            r = super().advance()
        finally:
            self._tracker_igt = False
        if self.gb.memory[0xFF40] & 0x80:
            self.lcd_frames += 1
        # v18 edit V: read-only committed-turn observer after every emulated frame (logging only)
        obs = self.lua.globals().REFSTRAT_FRAME_OBSERVE
        if obs:
            self._invalidate_reads()
            obs()
        return r

    def power_cycle(self):
        buf = io.BytesIO()
        self.gb.stop(save=True, ram_file=buf)
        buf.seek(0)
        dump = os.environ.get('REFSTRAT_SRAM_DUMP')   # research only: copy of the battery save for offline manip search
        if dump:
            # v8: per-run file names ('{seed}', '{n}' = power-cycle index) so parallel research runs never collide
            target = Path(dump.format(seed=self.seed, n=len(self.power_cycles))).resolve()
            # never a file PyBoy would auto-load on later fresh boots (review finding 9)
            if target.suffix.lower() == '.ram' or target.parent == ROOT.resolve():
                raise ValueError(f'refusing SRAM dump to {target}')
            target.write_bytes(buf.getvalue())
        self.gb = PyBoy(str(rom_path()), window='null', sound_emulated=False, ram_file=buf)
        self.gb.set_emulation_speed(0)
        self._memory = self.gb.memory
        self._turn_hook()
        # Rebind the cached WRAM reader to the new emulator instance.
        install = self.lua.execute('''
          return function(get, fallback)
            local floor = math.floor
            local values, stamps = {}, {}
            local generation = 0
            memory.readbyte = function(address)
                if stamps[address] == generation then return values[address] end
                local value
                if type(address) == "number" and address >= 0 and address < 8192 and address == floor(address) then
                    value = get(49152 + address)
                else
                    value = fallback(address)
                end
                values[address] = value
                stamps[address] = generation
                return value
            end
            return function() generation = generation + 1 end
          end
        ''')
        self._invalidate_reads = install(self._memory.__getitem__, self.readbyte)
        self.held, self.pending = set(), set()
        self.power_cycles.append(dict(frame=self.frames, observation=None))
        self.log('POWER CYCLE (cartridge save kept)', self.frames)
        return True
