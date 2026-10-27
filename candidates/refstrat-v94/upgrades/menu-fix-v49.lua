-- v49 MENU_FIX (default off; unset = nothing installed, v47 behaviour). experiments/build-2026-10-16/menu/REPORT.md
-- Phase-aligned menu presses (Sol review T2), only after the Surge trash-can chain (the last timed RNG chain) finished.
-- Game facts (pokered home/window.asm HandleMenuInput_ + PlaceMenuCursor, home/joypad2.asm, engine/joypad.asm _Joypad;
-- measured frame by frame with experiments/build-2026-10-16/menu/exp_timing.py):
--  * PlaceMenuCursor writes the cursor tile (0xED) at wMenuCursorLocation ($CC30), then Delay3: the joypad is NOT read
--    on the next frame, it is first read on the 2nd frame after the bot sees the new cursor (party menu: 3rd frame,
--    wPartyMenuAnimMonEnabled $D09B set), then on every frame until a button is accepted.
--  * A press counts only as an EDGE against hJoyLast = the buttons held at the game's previous sample. After an accepted
--    press that press stays "held in" until a release is sampled, so the next menu needs: released on its first sampled
--    frame, pressed on the next one. The engine instead pressed blind (1-frame A, then 3-frame retries), so the release
--    often fell inside Delay3 (not sampled) and the A was held over the first samples: 1-3 frames lost per menu.
-- Rule (Menu.select confirms and Menu.balance/sidle cursor moves only; everything else untouched):
--  * placement seen at frame o (cursor tile appears / moves) -> first sampled frame S0 = o+2 (party menu o+3);
--  * model of hJoyLast = buttons the bot held on the first frame >= S0 on which it held anything (or nothing, if it
--    released there) - i.e. the press the game accepted - or on a frame on which the text box printed one letter or
--    showed its prompt arrow (text reads the joypad every frame); unchanged on other frames;
--  * requested button X: if X is "held in" -> released up to S0, pressed on S0+1; if fresh -> pressed from the request
--    through S0 (a hold, no new edge); later frames (or no fresh placement seen) -> 1-frame toggles (press / release).
--  * also the engine's own 1-frame A / cursor presses on the battle main menu (FIGHT/PKMN/ITEM/RUN, wIsInBattle and
--    battle menu byte 94 without battle text), unless MENU_FIX_NOBATTLE.
--  The button is only ever pressed on frames on which the engine requested it (same menu row as before), never held
--  > 5 frames (game auto-repeat needs 30), stall guard: a press at least every 7th requested frame.
-- Reads WRAM only ($CC30/31, the tile behind it, $D09B); no play-time / RNG reads; no memory writes.
if MENU_FIX then
	local Input = require "util.input"
	local Menu = require "util.menu"
	local CURSOR = 0xED
	local armed = false
	local inMenu = 0
	local request, setAfterReq = nil, false
	local sentNow, sentPrev = {}, {}
	local lastLoc, lastTile = nil, nil
	local S0, open = -100, false
	local jl = {}
	local waitFrames = 0
	local TEXT_MODEL = MENU_FIX_TEXTMODEL ~= false
	local lastLetters, lastArrow = 0, false
	local nPlace, nPress, nForced = 0, 0, 0
	local LOG = MENU_FIX_LOG

	local origSet = joypad.set
	joypad.set = function(t)
		local s = {}
		for k, v in pairs(t) do if v then s[k] = true end end
		sentNow = s
		if request then setAfterReq = true end
		return origSet(t)
	end

	local engineUpdate = Input.update
	Input.update = function()
		local f = emu.framecount()
		sentPrev, sentNow = sentNow, {}
		request, setAfterReq = nil, false
		if not armed then
			local c = REFSTRAT_CHAIN
			if c and c.name == "surge" and c.finished then
				armed = true
				print("refstrat MENU_FIX: armed after the surge chain at frame " .. f)
			end
		end
		if armed then
			-- frame f-1 was sampled if it lies in the current placement's polling phase
			local printed = false
			if TEXT_MODEL then
				-- ... or if the text box printed exactly one more letter during it (PrintLetterDelay reads the joypad after
				-- every letter), or the prompt arrow was up (WaitForTextScrollButtonPress reads it every frame).
				-- Text box lines (1..18,14) and (1..17,16) of wTileMap; the arrow sits at (18,16).
				-- (blank 0x7F, cursor tiles 0xEC / 0xED and the arrow 0xEE are not letters)
				local letters = 0
				for a = 0x04B9, 0x04CA do local t = memory.readbyte(a); if t ~= 0x7F and (t < 0xEC or t > 0xEE) then letters = letters + 1 end end
				for a = 0x04E1, 0x04F1 do local t = memory.readbyte(a); if t ~= 0x7F and (t < 0xEC or t > 0xEE) then letters = letters + 1 end end
				printed = letters == lastLetters + 1 or lastArrow
				lastLetters, lastArrow = letters, memory.readbyte(0x04F2) == 0xEE
			end
			if open and f - 1 >= S0 then
				jl = sentPrev
				if next(sentPrev) ~= nil then open = false end
			elseif printed and not (open and f - 1 < S0) then
				jl = sentPrev
			end
			local loc = memory.readbyte(0x0C30) + 256 * memory.readbyte(0x0C31)
			local tile = nil
			if loc >= 0xC3A0 and loc < 0xC508 then tile = memory.readbyte(loc - 0xC000) end
			if tile == CURSOR and (loc ~= lastLoc or lastTile ~= CURSOR) then
				S0 = f + ((memory.readbyte(0x109B) ~= 0) and 3 or 2)
				open = true
				nPlace = nPlace + 1
			end
			lastLoc, lastTile = loc, tile
		end
		return engineUpdate()
	end

	-- battle main menu (FIGHT/PKMN/ITEM/RUN, HandleMenuInput): the engine's own 1-frame A / cursor presses there
	-- (action/battle.lua openBattleMenu, Battle.run, storage/inventory.lua Inventory.use midfight) are menu presses too
	local BATTLE_KEYS = {A = true, Up = true, Down = true, Left = true, Right = true}
	local function battleMainMenu(button, frames)
		return not MENU_FIX_NOBATTLE and BATTLE_KEYS[button] and (frames == nil or frames == 1)
			and memory.readbyte(0x1057) ~= 0 and memory.readbyte(0x0C50) == 94 and memory.readbyte(0x1125) ~= 1
	end

	local enginePress = Input.press
	Input.press = function(button, frames, walk)
		if armed then
			if request then   -- the engine refuses a second press in one frame (util/input.lua setForFrame)
				print("ERR: Reassigning " .. request .. " to " .. tostring(button))
				return
			end
			if (inMenu > 0 or battleMainMenu(button, frames)) and not walk and next(sentNow) == nil then
				request = button
				return
			end
		end
		return enginePress(button, frames, walk)
	end

	local function decide(X, f)
		if waitFrames >= 6 then nForced = nForced + 1; return true end
		if f <= S0 then return not jl[X] end      -- held in: release up to the first sample; fresh: hold into it
		return not sentPrev[X]                     -- afterwards: 1-frame toggles (held in: the edge right after S0)
	end

	local engineAdvance = Input.advance
	Input.advance = function()
		if request then
			local f = emu.framecount()
			if not setAfterReq and decide(request, f) then
				origSet({[request] = true})
				sentNow = {[request] = true}
				waitFrames = 0
				nPress = nPress + 1
				if LOG then print("MFX " .. f .. " press " .. request .. " S0=" .. S0) end
				if nPress % 500 == 0 then
					print("refstrat MENU_FIX: " .. nPress .. " presses, " .. nPlace .. " placements, " .. nForced .. " stall-guard presses")
				end
			else
				waitFrames = waitFrames + 1
				if LOG then print("MFX " .. f .. " wait " .. request .. " S0=" .. S0 .. (setAfterReq and " (engine set)" or "")) end
			end
		end
		return engineAdvance()
	end

	local function wrap(name)
		local fn = Menu[name]
		Menu[name] = function(...)
			inMenu = inMenu + 1
			local ok, r = pcall(fn, ...)
			inMenu = inMenu - 1
			if not ok then error(r, 0) end
			return r
		end
	end
	wrap("select"); wrap("balance"); wrap("sidle")
	-- MENU_FIX2_CLOSE (experiments/target-policy-2026-10-17/menus, default off): the B presses of Menu.close (bag list
	-- and START menu closes) take the same phase-aligned request path as the confirms (same stall guard)
	if MENU_FIX2_CLOSE then wrap("close") end
	print("Upgrade loaded: v49 MENU_FIX (phase-aligned menu confirms and cursor moves after the surge chain)")
end
