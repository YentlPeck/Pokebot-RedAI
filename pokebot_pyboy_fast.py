"""Faster read-only adapter, retaining the original Attempt lifecycle.

Gameplay, Lua 5.1 RNG, inputs, rendering, timer and finish checks are inherited
from pokebot_pyboy. WRAM cannot change between emulator ticks, so repeat Lua
reads within a frame can reuse a value without crossing the Python boundary.
"""
from pokebot_pyboy import Attempt as OriginalAttempt, AttemptDone, FPS, ROOT, SOURCE


class Attempt(OriginalAttempt):
    def __init__(self, seed, max_frames, folder, record=False, goal='brock',
                 finish_hold=0, variant='baseline'):
        super().__init__(seed, max_frames, folder, record, goal, finish_hold, variant)
        self._memory = self.gb.memory
        # The common integer case calls PyBoy's compiled read method directly;
        # unusual arguments retain the original callback and its validation.
        # Pass only a reader, never a writable memory object, into Lua.
        # Generation stamps avoid allocating a new table per tick.
        install = self.lua.execute('''
          return function(get, fallback)
            local floor = math.floor
            local values, stamps = {}, {}
            local generation = 0
            memory.readbyte = function(address)
                if stamps[address] == generation then
                    return values[address]
                end
                local value
                if type(address) == "number" and address >= 0 and
                   address < 8192 and address == floor(address) then
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

    def readbyte(self, address):
        address = int(address)
        if not 0 <= address < 8192:
            raise ValueError(f'WRAM read outside domain: {address}')
        return self._memory[0xC000 + address]

    def advance(self):
        self._invalidate_reads()
        return super().advance()

    def snapshot(self, name):
        # Preserve tick(0, True) and every evidence image. Invalidate as well,
        # so callers never depend on zero-tick implementation details.
        self._invalidate_reads()
        return super().snapshot(name)
