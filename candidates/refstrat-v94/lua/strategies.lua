-- refstrat candidate decision logic (REFERENCE_STRATEGY.md). Installed by loader.lua.
REFSTRAT_STRATEGIES = REFSTRAT_STRATEGIES or {}
REFSTRAT_CONTROLS = REFSTRAT_CONTROLS or {}
do
	local Input = require "util.input"
	local Memory = require "util.memory"
	local Menu = require "util.menu"
	local Textbox = require "action.textbox"
	local Settings = require "util.settings"
	local Utils = require "util.utils"
	local Player = require "util.player"
	local Battle = require "action.battle"
	local Inventory = require "storage.inventory"
	local S = REFSTRAT_STRATEGIES

	---------------------------------------------------------------------------------------------
	-- RNG manipulation by in-game SAVE + console power cycle (reference 5:52, 17:11, 41:41).
	-- The cartridge save survives the power cycle (refstrat_adapter.port_power_cycle). After power-on
	-- the game state and RNG depend only on the saved data and the frame timing of the inputs, so a
	-- fixed boot/CONTINUE schedule and a fixed walk reproduce the same outcome on every seed.
	---------------------------------------------------------------------------------------------
	REFSTRAT_MANIP = nil
	-- Default boot schedule (frames after power-on): Start on title, A on CONTINUE, A on the save summary.

	local function bootInputs()
		-- Deterministic boot driver: press A every `period` frames from `first` on (title -> CONTINUE ->
		-- save summary -> game). The same schedule on every seed gives the same RNG state at load.
		local m = REFSTRAT_MANIP
		local dt = emu.framecount() - m.bootFrame
		if dt >= m.boot.first and dt < m.boot.untilFrame and (dt - m.boot.first) % m.boot.period == 0 then
			Input.press("A", 1)
		end
	end
	local function booting()
		return REFSTRAT_MANIP and REFSTRAT_MANIP.stage == "boot"
	end
	local originalResetAll = resetAll
	resetAll = function()
		if booting() then return bootInputs() end
		return originalResetAll()
	end
	local originalStart, originalNames = Settings.startNewAdventure, Settings.choosePlayerNames
	Settings.startNewAdventure = function()
		if booting() then return bootInputs() end
		return originalStart()
	end
	Settings.choosePlayerNames = function()
		if booting() then return bootInputs() end
		return originalNames()
	end


	-- Manipulated Nidoran: first encounter in the Route 22 grass, caught with Poke Balls (reference: 3 bought,
	-- 1 used here), nickname "A". Same battle handling as the original catchNidoran (ai/red/strategies.lua:280)
	-- minus its 4-5 ball reset rule; outside battle a fixed two-tile pace keeps the walk identical on all seeds.
	local Pokemon = require "storage.pokemon"
	local Walk = require "action.walk"
	S.catchNidoranManip = function(data)
		if Battle.isActive() then
			local catchable = Battle.opponent() == "nidoran" and Memory.value("battle", "opponent_level") > 2
			if Memory.value("menu", "text_input") == 240 then
				Textbox.name()
			elseif Menu.canCloseMessage() then
				if catchable then Input.press("A") else Input.cancel() end
			else
				Battle.handle()
			end
			return false
		end
		if Pokemon.inParty("nidoran") then
			-- As the original catchNidoran (ai/red/strategies.lua:361): record level for the later stat check.
			Strategies.stats.nidoran = {level4 = Pokemon.info("nidoran", "level") == 4}
			return true
		end
		local px, py = Player.position()
		local a, b = data.pace[1], data.pace[2]
		if px == a[1] and py == a[2] then
			Walk.step(b[1], b[2])
		else
			Walk.step(a[1], a[2])
		end
	end


	-- v19 edit D: Route 6 path independent of the Ball count once a Cut learner is caught (see edit_c1_d.py)
	do
		local engineCatchOddish = Strategies.functions.catchOddish
		S.catchOddish = function(data)
			local CtlD = require "ai.control"
			if Pokemon.inParty("paras", "oddish") and Inventory.count("pokeball") == 0 then
				local cc = CtlD.canCatch
				CtlD.canCatch = function() return true end
				local ok, r = pcall(engineCatchOddish, data)
				CtlD.canCatch = cc
				if not ok then error(r) end
				return r
			end
			return engineCatchOddish(data)
		end
	end

	---------------------------------------------------------------------------------------------
	-- Encounter controls. The engine keeps its catch list in a local of ai/control.lua; refCatch sets it
	-- (Lua upvalue of the controller, not game memory). Reference catches: Nidoran (Route 22), Pidgey
	-- (Route 2), Paras (Mt. Moon), one Poke Ball each (3 bought in Viridian).
	---------------------------------------------------------------------------------------------
	local Control = require "ai.control"
	local originalShouldCatch = Control.shouldCatch
	local function setControlLocal(name, value)
		for _, f in ipairs({originalShouldCatch, Control.shouldFight}) do
			local i = 1
			while true do
				local n = debug.getupvalue(f, i)
				if not n then break end
				if n == name then debug.setupvalue(f, i, value); return end
				i = i + 1
			end
		end
		error("refstrat: control local "..name.." not found")
	end
	REFSTRAT_CONTROLS.refCatch = function(data)
		setControlLocal("shouldCatch", data.catch)
	end
	-- Ball budget (reference: 3 balls, one per catch). A missed manip must not end the run: only a missing Nidoran
	-- with no ball left is fatal; otherwise the bot simply stops catching, and the Pewter Mart rebuys what is missing
	-- (refShopPewter) so the Route 3 flier fallback / Paras can still be caught.
	Control.canCatch = function()
		if Inventory.count("pokeball") == 0 then
			if not Pokemon.inParty("nidoran", "nidorino", "nidoking") then
				Strategies.reset("pokeballs", "Ran out of Pokeballs before Nidoran", 0)
			end
			return false
		end
		return true
	end
	Control.shouldCatch = function(partySize)
		if Inventory.count("pokeball") == 0 and Pokemon.inParty("nidoran", "nidorino", "nidoking") then
			return false
		end
		return originalShouldCatch(partySize)
	end
	local function flierMissing()
		return not Pokemon.inParty("pidgey", "spearow", "pidgeotto")
	end
	REFSTRAT_CONTROLS.refCatchFlierIfMissing = function()
		setControlLocal("shouldCatch", flierMissing() and {{name="spearow",alt="pidgey",requireHit=true}, {name="pidgey",alt="spearow",requireHit=true}} or nil)
	end
	-- Squirtle must reach L8 (Bubble) before Brock: 314 EXP; the forest Weedle trainer gives 99. The reference's
	-- Squirtle had the extra from a Route 1 fight; on seeds where ours is short, fight forest wild Pokemon until 216.
	-- v8: Route 1 EXP target 215 (engine viridianExp / viridianBackupExp: 210). With the reference forest (no wild
	-- battles) the Weedle's 99 EXP must complete L8 (314): the reference had 217 from its Route 1 Pidgey (EARLY_ROUTE 2.1);
	-- t5 seeds 1797000053/55 reset at 301 EXP ("Did not reach level 8 before Brock").
	REFSTRAT_CONTROLS.refViridianExp = function(data)
		setControlLocal("minExp", 215)
		setControlLocal("shouldFight", data and data.backup and {{name="rattata",levels={2,3}}, {name="pidgey",levels={2,3}}}
			or {{name="rattata",levels={2,3}}, {name="pidgey",levels={2}}})
	end
	REFSTRAT_CONTROLS.refForestExp = function()
		setControlLocal("minExp", 216)
		setControlLocal("shouldFight", {{name="caterpie"}, {name="weedle"}, {name="metapod"}, {name="kakuna"}, {name="pidgey"}, {name="pikachu"}})
	end

	---------------------------------------------------------------------------------------------
	-- v8: post-reset manipulation CHAIN (reference "triple extended" Nidoran -> Route 2 Pidgey -> Viridian Forest ->
	-- Weedle String Shot). Program data and builder: lua/chain.lua. The offline simulator
	-- (experiments/refstrat-v8-2026-10-11/tools/chainprog.py) applies exactly these rules to the same data:
	--   t = frames since the power cycle; a finished segment hands over in the same frame;
	--   walk: hold toward the next waypoint (x first, then y); on another map hold the waypoint's direction hint or the
	--   last direction; a press tile plays its mini-script once on first arrival; battle flag = game.battle;
	--   battle: plays its script; checks opponent id/level (idAt), capture result shown on screen (capAt) and party
	--   size (partyAt).
	-- Inputs depend only on the program, the frame count since power-on, map/position and the battle flag, so they are
	-- identical on every seed until a checkpoint fails. A failed checkpoint BREAKS the chain (logged "refstrat RECOVERY
	-- chain ..."); the strategy then continues the same reference path in FREE mode with the engine's normal handling
	-- (catch the stage's target if it appears, run from others; Nidoran: the v7 grass pacing) - as the reference ran
	-- from the Kakuna after its own extension ended. Segments after the tuned part (p.stage) also run in free mode.
	---------------------------------------------------------------------------------------------
	REFSTRAT_CHAIN = nil
	local function chainParse(text)
		local out = {}
		local function add(part)
			for button, frames in part:gmatch("([%a%+]*):(%d+)") do
				for _ = 1, tonumber(frames) do out[#out + 1] = button end
			end
		end
		local pos = 1
		while pos <= #text do
			local a, b, count, group = text:find("%*(%d+)%((.-)%)", pos)
			if a then
				add(text:sub(pos, a - 1))
				for _ = 1, tonumber(count) do add(group) end
				pos = b + 1
			else
				add(text:sub(pos))
				break
			end
		end
		return out
	end
	local function chainPath(text)
		local out = {}
		for item in text:gmatch("[^;]+") do
			local f = {}
			for v in item:gmatch("[^,]+") do f[#f + 1] = v end
			out[#out + 1] = {tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), f[4]}
		end
		return out
	end
	local function chainSend(button)
		if button and button ~= "" then
			local t = {}
			for b in button:gmatch("[^%+]+") do t[b] = true end
			joypad.set(t)
		end
	end
	local CHAIN_STAGE_CONTROLS = {
		nidoran = function() setControlLocal("shouldCatch", {{name="nidoran", levels={3,4}}}) end,
		pidgey = function() setControlLocal("shouldCatch", {{name="pidgey"}}) end,
		forest = function() setControlLocal("shouldCatch", nil); REFSTRAT_CONTROLS.refForestExp() end,
		moon = function() setControlLocal("shouldCatch", {{name="paras"}}); Control.set({c="potion", b=true}) end,
	}
	local function chainPrepare(name)
		local prog = REFSTRAT_CHAIN_BUILD(name)
		local nstage = 0
		local order = {}
		for _, seg in ipairs(prog) do
			if seg.path then seg.points = chainPath(seg.path) end
			if seg.freePath then seg.freePoints = chainPath(seg.freePath) end
			if seg.s then seg.frames = chainParse(seg.s) end
			if seg.press then
				local pr = {}
				for k, v in pairs(seg.press) do pr[k] = chainParse(v) end
				seg.mini = pr
			end
			if seg.stage and not order[seg.stage] then nstage = nstage + 1; order[seg.stage] = nstage end
			seg.stageIndex = seg.stage and order[seg.stage] or nstage
		end
		return prog
	end
	-- as the inherited catchNidoran (ai/red/strategies.lua:361): level recorded for the later stat check at Brock
	local function chainNidoranStats()
		if Pokemon.inParty("nidoran") and not Strategies.stats.nidoran then
			Strategies.stats.nidoran = {level4 = Pokemon.info("nidoran", "level") == 4}
		end
	end
	local function chainBreak(c, why)
		local seg = c.prog[c.i]
		c.free, c.ok = true, false
		print("refstrat RECOVERY chain "..c.name.." broken at segment "..c.i.." ("..seg.k..", "..tostring(seg.stage).."), t="
			..(emu.framecount() - c.bootFrame)..": "..why)
	end
	-- v9: bag fingerprint (number of item kinds and all quantities, wNumBagItems D31D + pairs) for free-mode pickups
	local function chainBagSum()
		local n = memory.readbyte(0x131D)
		local s = n * 1000
		for k = 0, n - 1 do s = s + memory.readbyte(0x131F + 2 * k) + memory.readbyte(0x131E + 2 * k) * 7 end
		return s
	end
	-- Timed (frame-exact) step: returns "done" when the program is finished, "free" when the chain broke, nil otherwise.
	local function chainTimed(c)
		local t = emu.framecount() - c.bootFrame
		while true do
			local seg = c.prog[c.i]
			if not seg then return "done" end
			if seg.stageIndex > c.timedStages then
				c.free = true
				print("refstrat chain "..c.name..": timed part complete at segment "..c.i..", t="..t.."; free continuation")
				return "free"
			end
			local tr = t - c.start
			local flag = Memory.value("game", "battle") ~= 0
			local st = c.st
			local cur, done = nil, false
			if seg.k == "boot" then
				if tr >= seg.upto then
					done = true
				elseif tr >= seg.first and (tr - seg.first) % seg.period == 0 then
					cur = "a"
				end
			elseif seg.k == "wait" then
				done = tr >= seg.n
			elseif seg.k == "until" then
				done = t >= seg.at
			elseif seg.k == "await" then
				if flag then
					done = true
				elseif tr >= seg.n then
					chainBreak(c, "no encounter within "..seg.n.." frames")
					return "free"
				end
			elseif seg.k == "split" then
				done = true
				chainNidoranStats()
				Strategies.functions.split()
			elseif seg.k == "script" then
				done = tr >= #seg.frames or (seg.endOnBattle and flag) or false
				if not done then cur = seg.frames[tr + 1] end
			elseif seg.k == "battle" then
				if tr == 0 then st.party0 = Memory.value("player", "party_size") end
				if tr == (seg.idAt or 0) and (not flag or Memory.value("battle", "opponent_id") ~= seg.id
						or (seg.level and Memory.value("battle", "opponent_level") ~= seg.level)) then
					chainBreak(c, "expected id "..seg.id.." L"..tostring(seg.level)..", got "..Memory.value("battle", "opponent_id")
						.." L"..Memory.value("battle", "opponent_level"))
					return "free"
				-- capAt: wCapturedMonSpecies is assigned only after the ball/shake animation (pokered engine/items/
				-- item_effects.asm ItemUseBall), i.e. when the "caught" / "broke free" text follows; capAt (+905) lies
				-- after that assignment (+874 in the recording) and before the engine's first post-capture A (+909)
				elseif seg.capAt and tr == seg.capAt and memory.readbyte(0x111C) == 0 then
					chainBreak(c, "not caught with the first ball")
					return "free"
				elseif seg.partyAt and tr == seg.partyAt and Memory.value("player", "party_size") ~= (seg.party or (st.party0 + seg.partyGrow)) then
					chainBreak(c, "party size "..Memory.value("player", "party_size").." not as expected (catch failed)")
					return "free"
				elseif tr >= #seg.frames then
					done = true
					-- v11 evidence log only (the move is shown on screen as "WEEDLE used ...!"; no decision uses it):
					-- the Bug Catcher's Weedle turn-1 move (81 = STRING SHOT) for the forest criterion
					if seg.id == 112 then print("refstrat chain forest: Weedle turn-1 move "..memory.readbyte(0x0CDD).." (81 = String Shot; log only)") end
				else
					cur = seg.frames[tr + 1]
				end
			elseif seg.k == "walk" then
				if st.mini then
					cur = st.mini[st.mi]
					st.mi = st.mi + 1
					if st.mi > #st.mini then st.mini = nil; if not flag then c.pendingItem = nil end end   -- mini-script ended without a battle
				elseif flag then
					done = true
					if not seg.expect then
						chainBreak(c, "unexpected battle (opponent "..Memory.value("battle", "opponent_id").." L"
							..Memory.value("battle", "opponent_level")..")")
						return "free"
					end
				else
					local mp = Memory.value("game", "map")
					local px, py = Player.position()
					local idx = st.idx or 1
					local pts = seg.points
					while idx <= #pts and pts[idx][1] == mp and pts[idx][2] == px and pts[idx][3] == py do idx = idx + 1 end
					st.idx = idx
					st.pressed = st.pressed or {}
					local key = mp..","..px..","..py
					if seg.mini and seg.mini[key] and not st.pressed[key] then
						-- press tiles first (also the last waypoint: item pickups end their segment)
						st.pressed[key] = true
						-- review 1 #3: a pickup mini-script interrupted by a battle is handed to free mode (bag fingerprint)
						if seg.items and seg.items[key] then c.pendingItem = {key = key} end
						local mini = seg.mini[key]
						cur = mini[1]
						if #mini > 1 then st.mini, st.mi = mini, 2 end
					elseif idx > #pts then
						done = true
					else
						do
							local wp = pts[idx]
							local d
							if mp ~= wp[1] then
								d = wp[4] or c.lastDir
							elseif px ~= wp[2] then
								d = px < wp[2] and "right" or "left"
							else
								d = py < wp[3] and "down" or "up"
							end
							c.lastDir = d
							cur = d
						end
					end
				end
			end
			if done then
				c.i, c.start, c.st, c.pendingItem = c.i + 1, t, {}, nil
				local nxt = c.prog[c.i]
				if nxt and nxt.stage and nxt.stage ~= c.stage then
					c.stage = nxt.stage
					if CHAIN_STAGE_CONTROLS[c.stage] then CHAIN_STAGE_CONTROLS[c.stage]() end
				end
			else
				chainSend(cur)
				return nil
			end
		end
	end
	local function freeDir(wp, mp, px, py, c)
		local d
		if mp ~= wp[1] then
			d = wp[4] or c.lastDir
		elseif px ~= wp[2] then
			d = px < wp[2] and "right" or "left"
		else
			d = py < wp[3] and "down" or "up"
		end
		c.lastDir = d
		return d
	end
	-- Free (engine-handled) continuation of the remaining segments.
	local function chainFree(c)
		local seg = c.prog[c.i]
		if not seg then return "done" end
		if seg.stage and seg.stage ~= c.stage then
			c.stage = seg.stage
			if CHAIN_STAGE_CONTROLS[c.stage] then CHAIN_STAGE_CONTROLS[c.stage]() end
		end
		local function nextSeg() c.i, c.st = c.i + 1, {} end
		local st = c.st
		if seg.k == "split" then
			chainNidoranStats()
			Strategies.functions.split()
			nextSeg()
			return chainFree(c)
		elseif seg.k == "boot" or seg.k == "wait" or seg.k == "until" or (seg.k == "script" and seg.skipFree) then
			-- v9: timed-only scripts (Surge can presses) are skipped in free mode; refSurgeVerify then searches visibly
			nextSeg()
			return chainFree(c)
		elseif seg.stage == "nidoran" and not Pokemon.inParty("nidoran") and (seg.k == "battle" or seg.k == "await") then
			-- v7 behaviour: catch a Nidoran (L3/L4) in the Route 22 grass, run from anything else
			if S.catchNidoranManip({pace = {{33,11},{32,11}}}) then nextSeg() end
			return nil
		elseif seg.k == "battle" or seg.k == "await" or (seg.k == "script" and Memory.value("game", "battle") ~= 0 and not seg.final) then
			-- wild battle: engine handling (catch the stage target / run). A trainer battle hands over only in the final
			-- Weedle segment (the route's fightWeedle takes over); any other trainer battle is fought by the engine and the
			-- segment is kept (review 1 #3: Battle.handleWild returns true for trainer battles)
			local flag = Memory.value("game", "battle")
			if flag == 1 then
				Battle.handleWild()
				return nil
			elseif flag == 2 and not (seg.stage == "forest" and seg.k == "battle") then
				Battle.automate()
				return nil
			end
			nextSeg()
			return chainFree(c)
		elseif seg.k == "script" then
			-- final talk to the Bug Catcher from below; the engine fights him (fightWeedle)
			if Memory.value("game", "battle") ~= 0 then nextSeg(); return chainFree(c) end
			if Textbox.handle() then Player.interact("Up") end
			return nil
		elseif seg.k == "walk" then
			local flag = Memory.value("game", "battle")
			if flag ~= 0 then st.bagAtPress = nil end   -- v9: a ball thrown in this battle is not an item pickup
			if flag == 1 then
				Battle.handleWild()
				return nil
			elseif flag == 2 then
				Battle.automate()                 -- unexpected trainer battle: fight it, keep the segment (review 1 #3)
				return nil
			end
			if not Textbox.handle() then return nil end
			local mp = Memory.value("game", "map")
			local px, py = Player.position()
			-- the grass-avoiding free path only when the chain broke before the forest; a break inside the forest resumes
			-- on the reference path (v1 seeds 1797000102/109 stalled resuming the free path from the reference path)
			if st.pts == nil then
				st.pts = (seg.freePoints and mp ~= 51) and seg.freePoints or seg.points
			end
			local pts = st.pts
			if not st.idx then
				-- resume at the nearest following waypoint on this map (the timed part may have broken mid-path)
				st.idx = 1
				for k = #pts, 1, -1 do
					if pts[k][1] == mp and pts[k][2] == px and pts[k][3] == py then st.idx = k break end
				end
				if st.idx == 1 then
					for k = 1, #pts - 1 do
						local a, b = pts[k], pts[k + 1]
						if a[1] == mp and b[1] == mp and ((a[2] == b[2] and px == a[2] and py >= math.min(a[3], b[3]) and py <= math.max(a[3], b[3]))
								or (a[3] == b[3] and py == a[3] and px >= math.min(a[2], b[2]) and px <= math.max(a[2], b[2]))) then
							st.idx = k + 1
						end
					end
				end
			end
			local pend = c.pendingItem
			if pend then
				c.pendingItem = nil
				local here = mp..","..px..","..py
				-- review 2 #1: no bag-equality condition (a ball or Potion used in the interrupting battle changes the bag);
				-- the free-mode pickup below is bag-verified per press and bounded (6 presses, logged give-up)
				if here ~= pend.key then
					print("refstrat RECOVERY: timed pickup at "..pend.key.." interrupted, player now at "..here.." - not retried")
				elseif seg.items and seg.items[here] and not st[here] then
					print("refstrat RECOVERY: timed pickup at "..here.." interrupted - retried in free mode")
					st[here] = true
					st.item, st.itemKey = seg.items[here], here
					if here == "51,1,19" then st.potionsBefore = Inventory.count("potion") end
				end
			end
			while st.idx <= #pts and pts[st.idx][1] == mp and pts[st.idx][2] == px and pts[st.idx][3] == py do
				local key = mp..","..px..","..py
				if seg.items and seg.items[key] and not st[key] then
					-- item pickups of the reference path are also taken in free mode
					st[key] = true
					st.item, st.itemKey = seg.items[key], key
					if key == "51,1,19" then
						st.potionsBefore = Inventory.count("potion")
						print("refstrat RECOVERY: forest hidden Potion pickup attempted on the free-mode forest path")
					end
				end
				st.idx = st.idx + 1
			end
			if st.item then
				-- v9 (v8 vf-1797000305, offline replay): a wild battle started on the Rare Candy tile (34,31); the two A
				-- presses counted as pickup tries went into the battle text and the candy was left behind. A pickup now
				-- counts only when the bag changes; presses only while standing still, facing the item, 21 frames apart
				-- (odd: the overworld reads the pad on alternate frames); at most 6 presses, then a logged give-up.
				if Player.isMoving() then return nil end
				local bag = chainBagSum()
				local picked = st.bagAtPress ~= nil and bag ~= st.bagAtPress
				if picked or (st.itemTries or 0) >= 6 then
					if not picked then print("refstrat RECOVERY: free-mode item at "..st.itemKey.." not picked after 6 presses") end
					if st.potionsBefore then
						-- review 1 #6: the flag is set only when the Potion count rose (else refForestPotionIf may still try)
						local got = Inventory.count("potion") > st.potionsBefore
						if got then REFSTRAT_FOREST_POTION_PICKED = true end
						print("refstrat forest hidden Potion (free mode): "..(got and "picked" or "NOT picked"))
						st.potionsBefore = nil
					end
					st.item, st.itemTries, st.itemAt, st.bagAtPress = nil, nil, nil, nil
					return nil
				end
				local now = emu.framecount()
				if not st.itemAt or now - st.itemAt >= 21 then
					st.itemAt = now
					st.bagAtPress = bag                -- snapshot right before this press (cleared by any battle)
					if Player.interact(st.item) then st.itemTries = (st.itemTries or 0) + 1 end
				end
				return nil
			end
			if st.idx > #pts then
				nextSeg()                         -- (Nidoran stage: the following await applies the catch rule)
				return chainFree(c)
			end
			local d = freeDir(pts[st.idx], mp, px, py, c)
			if d then Input.press(d:sub(1, 1):upper()..d:sub(2), 0) end
			return nil
		end
		nextSeg()
		return chainFree(c)
	end
	-- v11 RUNNER-STYLE CLOCK TRACKER (user-approved 2026-10-12; method: pastebin VFM1Ggah + commentary 0:02:16 "we track
	-- which frame the current IGT is at"). The in-game clock advances once per V-blank while the game-timer flag is set
	-- (pokered engine/play_time.asm, home/vblank.asm) and therefore pauses whenever the LCD is off (building doors, battle
	-- transitions, potions; the pastebin's pause list). The timer starts in SpecialEnterMap (engine/menus/main_menu.asm)
	-- after Oak's speech; from there to the first controllable frame in Red's room no input matters, so the sync at that
	-- frame has a constant offset CLOCK_K. The tracker counts LCD-on frames (port_lcd_frames, adapter) from the sync.
	-- It never reads the play-time or RNG bytes; CLOCK_K / CLOCK_SAVE_LAG are calibration constants measured offline
	-- (experiments/refstrat-v11-2026-10-12/FINDINGS.md), like the runners' emulator-measured pause costs.
	REFSTRAT_CLOCK = REFSTRAT_CLOCK or {}
	-- Calibration (FINDINGS C1-C2; development batch c1, 5 real Nidoran saves compared offline with their saved clocks):
	-- saved clock - tracked clock at the moment the save menu opens = 12-16 frames when opened while still walking (c1),
	-- 7-10 (median 9) after standing still (c2) -> the gate always stands >= 2 frames and uses lag 9. Favourable
	-- frame (offline grid on a real save, 6 seconds x 60 frames, outcomes second-independent): saved frame 1 sits in the
	-- Pidgey-good run 59..10 and the forest-good run 59..2. (v11 text; v12 gates the Mt. Moon save too, FINDINGS M1-M4) The Mt. Moon save was NOT gated: its offset spread over
	-- 10 frames (lag events between the two saves), wider than any Moon-good frame run (the runner's pastebin also
	-- tracks only to the Viridian save).
	-- c3: the menu-open lag still varied (5-10); the offset at the moment YES is pressed was stable in every batch (saved -
	-- tracked = -99..-103, median -102, 14 saves) -> the gate sits at the YES/NO prompt; target frame 0 (actual 59..3).
	REFSTRAT_CLOCK_LAG = REFSTRAT_CLOCK_LAG or {}
	-- v12: offsets re-based for the LCD-edge sync (initial values predicted from the v11 data, calibrated in development
	-- batch m1); moon gate added (v12 FINDINGS M2): target saved frame 6 in the Moon-good run 4..7
	REFSTRAT_CLOCK_YES = REFSTRAT_CLOCK_YES or {early = 16, moon = -894}   -- m1: early 16 (4/4), moon -894/-895
	-- v14 (FINDINGS F1-F3): the early save lands on the predicted frame (YES->save latency 16) or one frame later (17,
	-- 18 of 67 v13 real saves; no visible predictor). With target 1 the late saves hit frame 2, where the Weedle uses
	-- Poison Sting (17/18 real) - the measured cause of the Forest String Shot failures. Target 0 -> saved 0 or 1, both in
	-- the reference outcome class (offline full 60-second maps on real v13 saves), skipping the saved seconds where frame
	-- 0 or 1 fails: 6, 7, 40, 43, 44, 57.
	REFSTRAT_CLOCK_GOOD = REFSTRAT_CLOCK_GOOD or {early = {[0] = true}, moon = {[6] = true}}   -- moon window 4..7, error -1..0
	-- v12 FINDINGS M4: Moon outcome also depends on the saved second at frames 4..7 (3 real saves, identical): failing
	-- seconds 7, 17, 18, 28, 38 (union) -> the gate waits into the next second
	REFSTRAT_CLOCK_BADSEC = REFSTRAT_CLOCK_BADSEC or {moon = {[7] = true, [17] = true, [18] = true, [28] = true, [38] = true},
		early = {[6] = true, [7] = true, [40] = true, [43] = true, [44] = true, [57] = true}}   -- v14 F3
	-- v56 MANIP_FAST: a chain with the fast parameter set uses its own favourable saved frame / skipped seconds
	for n, g in pairs(REFSTRAT_CHAIN_GATES_FAST or {}) do
		if V56_FAST_ON and V56_FAST_ON(n) then
			if g.good then REFSTRAT_CLOCK_GOOD[n] = g.good end
			if g.badsec then REFSTRAT_CLOCK_BADSEC[n] = g.badsec end
			if g.cap then REFSTRAT_GATE_CAP = REFSTRAT_GATE_CAP or {}; REFSTRAT_GATE_CAP[n] = g.cap end
			print("refstrat v56 MANIP_FAST: save gate " .. n .. " uses the fast target frames")
		end
	end
	local function clockNow()
		local c = REFSTRAT_CLOCK
		if not c.lcd0 then return nil end
		return c.base + (port_lcd_frames() - c.lcd0)
	end
	local function clockFmt(n)
		if not n then return "unsynced" end
		return string.format("%d:%02d:%02d.%02d (total %d)", math.floor(n / 216000), math.floor(n / 3600) % 60, math.floor(n / 60) % 60, n % 60, n)
	end
	REFSTRAT_CLOCK_NOW, REFSTRAT_CLOCK_FMT = clockNow, clockFmt
	-- v13 (v12 final review MATERIAL 2; user decision 2026-10-12): NO controller decision may read the live play-time bytes.
	-- The engine's time helpers (Utils.igt for the loader watchdog, Strategies.overMinute / resetTime / setYolo, the
	-- D-sum toggle and grabTreePotion; Utils.frames; Utils.timeSince / timeToSplit / elapsedTime for logs and reset
	-- messages) are redirected to the approved LCD-on tracker. IGT estimate = continuous tracker minus 910 frames per
	-- console power cycle the bot itself performed (calibrated offline: across the Nidoran reset the continuous tracker
	-- gains ~910 LCD-on frames the clock does not count - title/CONTINUE and the post-save frames; FINDINGS T1). Before
	-- the tracker is synchronised (title, Oak's speech) or if it stays unsynchronised, the estimate is the emulator frame
	-- count since power-on / 60 (external, monotonic, never smaller than the in-game clock -> conservative for limits).
	-- The save gates keep using REFSTRAT_CLOCK_NOW (continuous tracker, calibrated offsets) unchanged.
	REFSTRAT_CLOCK_RESET_COST = 910
	-- v54 SAVE_FAST (default off = v52; experiments/build-2026-10-16/overhead/REPORT_v54.md): power cycle
	-- REFSTRAT_SAVE_FAST_M frames after "Now saving..." appears in the WRAM tilemap (read only). pokered SaveMenu runs
	-- SaveGameData (whole battery save incl. play time and checksums, SRAM disabled again) before placing that string,
	-- so the battery save is byte-identical to v52's (measured: final at YES + 30/33/35, string at YES + 30/34/35 for
	-- early/moon/surge). v52 then waited REFSTRAT_SAVE_POST = 236 more LCD-on frames (modal; 237 on ~10% of saves: a
	-- CPU-timing race in the closing redraw, not visible in advance). The tracker no longer counts the cut part (236 - M),
	-- so every calibrated constant that
	-- contains it is shifted by exactly the frames cut: the YES / menu-lag gate offsets of every later save (moon: -894 +
	-- early cut) and the per-reset IGT-estimate cost (910 - cut). REFSTRAT_CLOCK.cut = frames cut so far. Safety: no
	-- string by YES + 120 frames -> the v52 tail (no cut).
	REFSTRAT_SAVE_FAST_M = REFSTRAT_SAVE_FAST_M or 2
	REFSTRAT_SAVE_POST = REFSTRAT_SAVE_POST or 236
	local function clockCut() return SAVE_FAST and (REFSTRAT_CLOCK.cut or 0) or 0 end
	local function igtFrames()
		local n = clockNow()
		if not n then return emu.framecount() end
		return math.max(0, n - (REFSTRAT_CLOCK.resets or 0) * REFSTRAT_CLOCK_RESET_COST + clockCut())   -- v54: cost 910 - cut per reset
	end
	REFSTRAT_IGT_FRAMES = igtFrames
	local function seg(u) return u < 10 and ("0"..u) or tostring(u) end
	-- the stream-clock message (Bridge.time, called every frame from engine main.lua) read the play-time bytes; it is
	-- output only (no client connected) and is disabled so no play-time read stays reachable
	do local Bridge = require "util.bridge"; Bridge.time = function() end end
	Utils.igt = function() return math.floor(igtFrames() / 60) end
	Utils.frames = function() return igtFrames() end
	Utils.elapsedTime = function()
		local t = Utils.igt()
		return math.floor(t / 3600)..":"..seg(math.floor(t / 60) % 60)..":"..seg(t % 60)
	end
	Utils.timeSince = function(prevTime)
		local currTime = Utils.igt()
		local diff = currTime - prevTime
		local timeString
		if diff > 0 then timeString = seg(math.floor(diff / 60))..":"..seg(diff % 60) end
		return currTime, timeString
	end
	-- v12 (FINDINGS M1): the v11 sync fired while Oak's speech was still ending (the engine already reports Red's room at
	-- (3,6)); the clock started 119-123 frames later, depending on the bot's text-press timing - the whole v11 tracking
	-- error. The new sync waits for the first LCD off->on edge in Red's room: the clock starts (SpecialEnterMap) 48 frames
	-- after the fade to white begins, the LCD goes off 19 frames later and comes back on with the clock at exactly 21
	-- (offline replays of three real runs, identical). Visible display state only; bounded wait.
	S.refClockSync = function()
		local c = REFSTRAT_CLOCK
		local st = Strategies.status
		if c.lcd0 then return true end
		local n = port_lcd_frames()
		st.waited = (st.waited or 0) + 1
		if st.last and n == st.last then st.sawOff = true end           -- an LCD-off frame (no LCD-on increment)
		if st.sawOff and st.last and n == st.last + 1 then              -- first LCD-on frame after the off period
			c.lcd0, c.base = n, REFSTRAT_CLOCK_K or 21          -- clock 21 at this frame (offline replays)
			print("refstrat clock: synced at the LCD on-edge in Red's room (LCD-on frames "..c.lcd0..", clock "..c.base
				..", waited "..st.waited.." frames)")
			return true
		end
		st.last = n
		if st.waited > 600 then
			-- impl review: an unsynchronised tracker must not drive the save gates -> leave it unsynced (gates skip)
			c.unreliable = true
			print("refstrat clock: RECOVERY no LCD edge within 600 frames - tracker left UNSYNCED, save gates disabled")
			return true
		end
		return false
	end

	-- v11 BIKE SHOP INSTANT TEXT (user-approved 2026-10-12; reference 24:16-24:21 and 33:36-33:41 [O, SEG_C]; guide "get
	-- Instant Text" [G]; commentary 0:30:14 [C]). pokered scripts/BikeShop.asm [M]: without the Bike Voucher the clerk
	-- sets BIT_NO_TEXT_DELAY (wStatusFlags5) for the BICYCLE/CANCEL menu; leaving that menu with B skips the reset, so text
	-- stays instant until a START menu, list menu or Pokemon menu resets it. The bot talks to the clerk across the counter
	-- from (4,2) facing Right (as the inherited procureBicycle), then presses ONLY B (B advances the text and cancels the menu). It never writes memory. The flag is read
	-- once afterwards for the log only (evidence; no decision uses it).
	-- v11 evidence log only: is instant text still on at a later point (it is lost on START / list / Pokemon menus)?
	S.refInstantTextLog = function(data)
		print("refstrat instant text at "..tostring(data.at)..": "..tostring(bit.band(memory.readbyte(0x1730), 0x40) ~= 0).." (log only)")
		return true
	end
	S.refBikeClerk = function()
		local st = Strategies.status
		local px, py = Player.position()
		if not st.talked then
			if px ~= 4 or py ~= 2 then
				if not Textbox.handle() then return false end
				if py == 4 or py == 3 then
					if px ~= 4 then Walk.step(4, py) else Walk.step(4, py - 1) end
				else
					Walk.step(px, py - 1)
				end
				return false
			end
			if Textbox.isActive() then
				st.talked, st.start = true, emu.framecount()
				return false
			end
			Player.interact("Right")
			return false
		end
		if Textbox.isActive() or Menu.isOpened() then
			st.idle = 0
			if emu.framecount() - st.start > 1800 then
				return Strategies.reset("error", "Bike Shop clerk text did not close", nil, true)
			end
			Input.press("B", 2)
			return false
		end
		st.idle = (st.idle or 0) + 1
		if st.idle < 8 then return false end
		local on = bit.band(memory.readbyte(0x1730), 0x40) ~= 0
		print("refstrat Bike Shop clerk: talked, menu left with B; instant-text flag (log only) "..tostring(on)
			.." after "..(emu.framecount() - st.start).." frames")
		return true
	end

	-- {s="refChain", name=..., boot=...}: in-game SAVE on the current tile, console power cycle (battery save kept),
	-- then the program. Returns true when the program has finished (timed or free).
	S.refChain = function(data)
		local st = Strategies.status
		local c = REFSTRAT_CHAIN
		if not c or c.name ~= data.name or c.finished then
			if not st.saved then
				if SAVE_FAST and st.answered and st.yesFrame and not st.slow then   -- v54
					if not st.nowSaving and Memory.raw(0x04B9) == 0x8D and Memory.raw(0x04BA) == 0xAE and Memory.raw(0x04BB) == 0xB6 then
						st.nowSaving, st.nowLcd = emu.framecount(), port_lcd_frames()   -- "Now" at (1,14): save data complete
					end
					if st.nowSaving and emu.framecount() - st.nowSaving >= REFSTRAT_SAVE_FAST_M - 1 then
						st.saved, st.fast = true, true   -- power cycle on the next frame = "Now saving..." + M
						return false
					end
					if not st.nowSaving and emu.framecount() - st.yesFrame > 120 then
						st.slow = true
						print("refstrat SAVE_FAST: RECOVERY no 'Now saving...' by YES + 120 frames - full v52 tail, no cut")
					end
				end
				-- v8 fix (v1 seeds 1797000107/110): the Route 3 save tile is a grass tile; a wild battle started by the step
				-- onto it is handled first (engine: catch the target / run), then the game is saved on the same tile
				if not st.choseSave and Memory.value("game", "battle") ~= 0 then
					Battle.handleWild()
					return false
				end
				if st.choseSave and Textbox.isActive() and Memory.value("battle", "text") == 20 then
					-- v11 favourable save frame at the YES/NO prompt (runner: wait before saving on a bad frame): predicted saved
					-- frame = tracked clock + REFSTRAT_CLOCK_YES offset; wait (>= 2; <= 62 frames, 200 with bad seconds) until it is a target frame
					local now = REFSTRAT_CLOCK_NOW()
					local good, off = REFSTRAT_CLOCK_GOOD and REFSTRAT_CLOCK_GOOD[data.name], REFSTRAT_CLOCK_YES and REFSTRAT_CLOCK_YES[data.name]
					if off then off = off + clockCut() end   -- v54 SAVE_FAST: moon -894 + early cut
					if not st.answered and now and good and off then
						st.yesWait = st.yesWait or 0
						-- v12: optional bad saved seconds (Moon: FINDINGS M4) - wait into the next second; cap 200 frames
						local badsec = REFSTRAT_CLOCK_BADSEC and REFSTRAT_CLOCK_BADSEC[data.name]
						local psec = math.floor((now + off) / 60) % 60
						local cap = badsec and (REFSTRAT_GATE_CAP and REFSTRAT_GATE_CAP[data.name] or 200) or 62   -- impl review: adjacent bad seconds 17-18 need up to 181 frames
						if (st.yesWait < 2 or not good[(now + off) % 60] or (badsec and badsec[psec])) and st.yesWait < cap then
							st.yesWait = st.yesWait + 1
							return false
						end
						if not st.yesLogged then
							st.yesLogged = true
							print("refstrat clock: "..data.name.." waited "..st.yesWait.." frames at YES; predicted saved second "..(math.floor((now + off) / 60) % 60).." frame "..((now + off) % 60))
						end
					end
					Input.press("A")
					if not st.answered then
						st.yesFrame, st.yesLcd = emu.framecount(), port_lcd_frames()   -- v54 SAVE_FAST
						print("refstrat clock: "..data.name.." save YES pressed at tracked IGT "..REFSTRAT_CLOCK_FMT(REFSTRAT_CLOCK_NOW()).." | v13 IGT estimate frames "..tostring(REFSTRAT_IGT_FRAMES and REFSTRAT_IGT_FRAMES()))
					end
					st.answered = true
					return false
				end
				-- v11: runner-style favourable save frame (pastebin VFM1Ggah: "if the save frame is bad, wait ... before
				-- saving"). Before opening the START menu, the tracked clock plus the calibrated menu->save lag predicts the
				-- saved frame; while it is in the chain's known-bad set, wait (at most 60 frames). Only the approved tracker
				-- feeds this decision.
				if not st.menuAt and not st.choseSave then
					local now = REFSTRAT_CLOCK_NOW()
					local good, lag = REFSTRAT_CLOCK_GOOD and REFSTRAT_CLOCK_GOOD[data.name], REFSTRAT_CLOCK_LAG and REFSTRAT_CLOCK_LAG[data.name]
					if lag then lag = lag + clockCut() end   -- v54 SAVE_FAST
					if now and good and lag and Textbox.handle() then
						st.waited = st.waited or 0
						if (st.waited < 2 or not good[(now + lag) % 60]) and st.waited < 62 then
							st.waited = st.waited + 1
							return false
						end
					end
					st.menuAt = true
					print("refstrat clock: "..data.name.." save menu opened at tracked IGT "..REFSTRAT_CLOCK_FMT(now)
						..(st.waited and (" after waiting "..st.waited.." frames for a favourable save frame (predicted saved frame "..tostring(now and lag and (now + lag) % 60)..")") or ""))
				end
				if st.answered then
					if Menu.isOpened() or Textbox.isActive() then
						if Menu.canCloseMessage() then Input.press("B") end
						st.idle = 0
						return false
					end
					st.idle = (st.idle or 0) + 1
					if st.idle >= 4 then st.saved = true end
					return false
				end
				if Menu.isOpened() and Memory.value("menu", "main") == 128 and Menu.getCol() == 11 then
					if Menu.select(4, true) then st.choseSave = true end
				else
					Menu.pause()
				end
				return false
			end
			local prog = chainPrepare(data.name)
			local boot = prog[1]
			math.randomseed(data.rng or 1)
			REFSTRAT_MANIP = {name = data.name, stage = "boot", boot = {first = boot.first, period = boot.period, untilFrame = boot.upto}}
			REFSTRAT_RISK_LIVE = false   -- v21: no risky move choice inside a timed chain
			print("refstrat chain "..data.name..": saved, power cycle at frame "..emu.framecount())
			REFSTRAT_CLOCK.resets = (REFSTRAT_CLOCK.resets or 0) + 1   -- v13: tracker IGT estimate
			if st.fast then
				local post = port_lcd_frames() - st.nowLcd
				local cut = REFSTRAT_SAVE_POST - post
				REFSTRAT_CLOCK.cut = (REFSTRAT_CLOCK.cut or 0) + cut
				print("refstrat SAVE_FAST: "..data.name.." power cycle "..(emu.framecount() - st.yesFrame).." frames after YES, "
					..post.." LCD-on frames after 'Now saving...' (string at YES + "..(st.nowSaving - st.yesFrame).."), cut "..cut
					.." frames, total cut "..REFSTRAT_CLOCK.cut)
			end
			port_power_cycle()
			REFSTRAT_MANIP.bootFrame = emu.framecount()
			local params = REFSTRAT_CHAIN_PARAMS[data.name] or {}
			REFSTRAT_CHAIN = {name = data.name, prog = prog, bootFrame = REFSTRAT_MANIP.bootFrame, i = 1, start = 0, st = {},
				ok = true, free = false, timedStages = params.stage or 1}
			Input.clear()
			return false
		end
		if c.i > 1 and REFSTRAT_MANIP and REFSTRAT_MANIP.stage == "boot" then REFSTRAT_MANIP = nil end
		local r
		if c.free then
			r = chainFree(c)
		else
			r = chainTimed(c)
			if r == "free" then r = chainFree(c) end
		end
		if r == "done" then
			c.finished = true
			if c.name == "moon" or c.name == "surge" then REFSTRAT_RISK_LIVE = true end   -- v21
			REFSTRAT_MANIP = nil
			print("refstrat chain "..c.name..": finished ("..(c.ok and "timed chain intact" or "after RECOVERY")
				..") at frame "..emu.framecount().." t="..(emu.framecount() - c.bootFrame))
			return true
		end
		return false
	end

	-- v8: the reference skips the forest hidden Potion (1,18); taken only as a logged recovery when Squirtle is at
	-- <= 12 HP after the Weedle fight (the v2-v7 survival rule of grabForestPotion).
	S.refForestPotionIf = function()
		local st = Strategies.status
		if Strategies.initialize("checked") then
			-- v8 (after t4: 3/6 forest and 2/6 Brock deaths without any Potion): the hidden Potion is always taken after the
			-- Weedle fight and kept for Brock (the engine's fightBrock heals with it); used at once only at <= 12 HP.
			-- In free mode it was already taken on the grass-avoiding path.
			st.go = not Inventory.contains("potion") and not REFSTRAT_FOREST_POTION_PICKED
			st.deadline = emu.framecount() + 900      -- never stall here (v2 seeds 1797000123/129)
			print(st.go and ("refstrat RECOVERY: forest hidden Potion taken (Squirtle "..Pokemon.info("squirtle", "hp").." HP)")
				or "refstrat: forest hidden Potion already in the bag")
			if not st.go and Pokemon.info("squirtle", "hp") <= 12 then st.useNow = true end
		end
		if st.useNow then
			return Strategies.functions.potion({hp = 13})     -- the route's tested potion strategy (one Potion)
		end
		if not st.go then return true end
		if emu.framecount() > st.deadline and not Battle.isActive() then
			print("refstrat forest hidden Potion: given up after 900 frames")
			return Menu.close()
		end
		-- the hidden Potion (1,18) is taken from (1,19) facing Up: arrive from (1,20) (the reference path reaches (1,19)
		-- moving Left, as the v2-v7 route did not)
		if not st.facingUp then
			if not Battle.handleWild() then return false end
			local px, py = Player.position()
			if not st.below then
				if px == 1 and py == 20 then st.below = true else Walk.step(1, 20) end
				return false
			end
			if px == 1 and py == 19 then st.facingUp = true else Walk.step(1, 19) end
			return false
		end
		return Strategies.functions.grabForestPotion()
	end

	-- v8: Route 3 Horn Attack conservation (reference 12:00-17:10, sources/EARLY_ROUTE.md 3.2: Horn Attack used 4/3/6/6,
	-- 6/25 left for the Mt. Moon Rocket; [C] CT 0:18:06 "we want to save one horn attack ... for moon rockets"). On Route 3,
	-- once Nidoran's Horn Attack PP is at the reserve, a Horn Attack chosen by the damage model is replaced by Tackle.
	REFSTRAT_HA_RESERVE = REFSTRAT_HA_RESERVE or 6
	do
		local fightBeforeConserve = Battle.fight
		local function nidoHA()
			local idx = Pokemon.indexOf("nidoran")
			if idx == -1 or not Pokemon.moveIndex("horn_attack", "nidoran") then return nil end
			return Pokemon.pp(idx, "horn_attack")
		end
		Battle.fight = function(move, ...)
			if Memory.value("game", "map") == 14 and Memory.value("battle", "our_id") == Pokemon.getID("nidoran") then
				-- the damage model's move tables carry the move id (30 = Horn Attack); their names are display names
				local isHA = move == "horn_attack" or (type(move) == "table" and move.id == 30)
				if move == nil then
					local best = Combat.bestMove()
					isHA = best ~= nil and best.id == 30
				end
				local pp = nidoHA()
				local reserve = REFSTRAT_HA_RESERVE
				if isHA and pp and pp <= reserve and Pokemon.battleMove("tackle") then
					if not Strategies.status.refHALogged then
						Strategies.status.refHALogged = true
						print("refstrat: Route 3 Horn Attack conserved (PP "..pp.."), Tackle instead")
					end
					return fightBeforeConserve("tackle", ...)
				end
			end
			return fightBeforeConserve(move, ...)
		end
	end

	-- v8: Mt. Moon menu state log (moon-exp): the reference reaches the B2F menu after the Rocket with Nidoran L15 + 20 EXP
	-- (2055; sources/EARLY_ROUTE.md 4) and uses the Rare Candy there. Logs the intended path or the recovery case.
	S.refMoonPotionMark = function()
		REFSTRAT_MOON_POTIONS = Inventory.count("potion")
		return true
	end
	S.refMoonMenuCheck = function()
		if REFSTRAT_MOON_POTIONS and Inventory.count("potion") < REFSTRAT_MOON_POTIONS then
			print("refstrat RECOVERY: "..(REFSTRAT_MOON_POTIONS - Inventory.count("potion")).." in-battle Potion(s) in the Mt. Moon Rocket fight")
		end
		local nido = Pokemon.inParty("nidoran", "nidorino", "nidoking")
		local lvl = nido and Pokemon.info(nido, "level") or -1
		local exp = Pokemon.getExp() or -1
		if Pokemon.inParty("nidoran") and lvl == 15 and Inventory.contains("rare_candy") then
			print("refstrat moon menu: reference state (Nidoran L15, EXP "..tostring(exp)..", after the Rocket)")
		else
			print("refstrat RECOVERY moon menu: "..tostring(nido).." level "..tostring(lvl).." EXP "..tostring(exp)..
				" candy "..tostring(Inventory.contains("rare_candy") and true or false).." - candy/evolution deferred to the post-Nerd repeat")
		end
		return true
	end

	-- v8 stall fixes (dev full games d2diag): (1) the chain can end at (2,19) before the Bug Catcher's battle has started
	-- (seed 1796000011): fightWeedle only reacts to a running battle, so it now talks to him (facing Up) first;
	-- (2) the inherited pre-Brock party swap (equipForBrock -> swapNidoran) has no wild-battle handling and pressed
	-- START inside a forest encounter until the time limit (seed 1796000013): wild battles are handled first.
	do
		local engineFightWeedle = Strategies.functions.fightWeedle
		S.fightWeedle = function(data)
			if Memory.value("game", "battle") == 0 and not Strategies.status.foughtTrainer then
				if Textbox.handle() then Player.interact("Up") end
				return false
			end
			return engineFightWeedle(data)
		end
		local engineEquip = Strategies.functions.equipForBrock
		S.equipForBrock = function(data)
			local flag = Memory.value("game", "battle")
			if flag == 1 then
				Battle.handleWild()
				return false
			elseif flag == 2 then                 -- review 2 #2
				Battle.automate()
				return false
			end
			return engineEquip(data)
		end
	end

	local Shop = require "action.shop"

	-- Move ids missing from the engine's move-name table (storage/pokemon.lua local moveList).
	do
		local i = 1
		while true do
			local name, value = debug.getupvalue(Pokemon.moveIndex, i)
			if not name then error("refstrat: moveList not found") end
			if name == "moveList" then
				value.mega_punch = 5
				value.blizzard = 59
				break
			end
			i = i + 1
		end
	end

	-- Pewter Mart (reference 11:53: 8 Potions). We buy 10 (baseline amount): without the Mt. Moon manip the bot meets
	-- wild battles the reference avoided and ran out before the Cerulean Rocket (seed 1700000001).
	-- v19 edit A (S2, reference 11:50-11:59, HEAL_SHOP_BIRD 2.1): after OPTIONS (battleModeSet, unchanged) buy exactly 8
	-- Potions - a purchase quantity (bag +8; a kept Forest Potion stays on top). Shop.transaction amounts are bag
	-- targets, so the target is fixed once from the bag at entry. RB1 (shopping RECOVERY, after the reference list):
	-- Poke Balls below the Balls still needed for the 1-ball catches (Paras 1, + flier 1 if missing) - a failed catch
	-- (v8); the reference had exactly one Ball for the Paras. REFSTRAT_PEWTER_BAG = Potions in the bag after the
	-- purchase (the Shorts Kid rule counts Potions used since Pewter, edit B).
	S.refShopPewter = function()
		local st = Strategies.status
		if st.potTarget == nil then
			local p0, b0 = Inventory.count("potion"), Inventory.count("pokeball")
			st.potTarget = p0 + 8
			local need = (flierMissing() and 1 or 0) + (Pokemon.inParty("paras") and 0 or 1)
			st.balls = math.max(0, need - b0)
			st.ballTarget = b0 + st.balls
			print(string.format("refstrat SHOP S2 Pewter: reference list POTION x8 (bag %d -> %d), money %d", p0, st.potTarget, REFSTRAT_MONEY()))
			print(string.format("refstrat SHOP RB1 Pewter ball check: Poke Balls %d, needed %d (flier %s, Paras %s) -> %s", b0, need,
				flierMissing() and "missing" or "in party", Pokemon.inParty("paras") and "in party" or "to catch",
				st.balls > 0 and ("RECOVERY: buy POKE_BALL x"..st.balls) or "no purchase (reference branch)"))
		end
		local buy = {{name = "potion", index = 1, amount = st.potTarget}}
		if st.balls > 0 then buy[#buy + 1] = {name = "pokeball", index = 0, amount = st.ballTarget} end
		local done = Shop.transaction {buy = buy}
		if done and not st.confirmed then
			-- v19 edit J1: the Shorts Kid baseline is the confirmed bag after the completed purchase
			st.confirmed = true
			REFSTRAT_PEWTER_BAG = Inventory.count("potion")
			print("refstrat SHOP S2 Pewter: completed, Potions in the bag "..REFSTRAT_PEWTER_BAG.." (Shorts Kid baseline)")
		end
		return done
	end

	-- Mt. Moon move plan (reference 21:13-22:10, after the B2F Rocket): Rare Candy (Nidoran L15 -> 16 evolves),
	-- TM12 WATER GUN over TACKLE, MOON STONE -> Nidoking, TM01 MEGA PUNCH over LEER. Separate route steps, each a
	-- no-op when not possible yet (our Nidoran starts at L3, the reference's at L4); repeated after the Super Nerd.
	local function lead()
		return Pokemon.inParty("nidoking", "nidorino", "nidoran")
	end
	S.refCandyEvolve = function(data)
		local st = Strategies.status
		if not Battle.handleWild() then return false end
		if Strategies.initialize("checked") then
			st.go = lead() == "nidoran" and Inventory.contains("rare_candy") and Pokemon.info("nidoran", "level") == 15
			st.start = Inventory.count("rare_candy")
		end
		if not st.go then return true end
		if Inventory.count("rare_candy") == st.start then
			if Menu.pause() then Inventory.use("rare_candy", "nidoran") end
			return false
		end
		if not Pokemon.inParty("nidorino") then
			-- level-up text and evolution: confirm with A only (B cancels an evolution)
			if Textbox.isActive() or Menu.isOpened() then Input.press("A") end
			return false
		end
		-- MENU_FIX2_MOON (experiments/target-policy-2026-10-17/menus): chain=true is set only by that switch's route
		-- block. pokered: Rare Candy is a party-menu item -> after the level-up / evolution the bag list is redisplayed
		-- (StartMenu_Item); stay in it for the chained TM12 step instead of closing and reopening START.
		if data and data.chain then return Strategies.closeMenuFor(data) end
		return Menu.close()
	end
	S.refTeach = function(data)
		local mon = data.poke or lead()
		if not Battle.handleWild() then return false end
		if Strategies.initialize("checked") then
			Strategies.status.go = not Pokemon.hasMove(data.move) and Inventory.contains(data.move)
				and (not data.poke or Pokemon.inParty(data.poke))
				-- v8: the reference teaches TM12 after the evolution; an unevolved Nidoran (recovery case: free-mode L3
				-- Nidoran reaches the menu at L14) is taught after the Super Nerd instead (v3b seed 1797000170 hung here)
				and (data.move ~= "water_gun" or Pokemon.inParty("nidorino", "nidoking"))
		end
		if not Strategies.status.go then return true end
		-- MENU_FIX2: chain is nil on every refTeach step unless a MENU_FIX2 route block set it
		return Strategies.functions.teach({move = data.move, poke = mon, replace = data.replace, chain = data.chain})
	end
	S.refMoonStone = function(data)
		if Strategies.initialize("checked") then
			Strategies.status.go = lead() == "nidorino" and Inventory.contains("moon_stone")
		end
		if not Strategies.status.go then return true end
		-- MENU_FIX2_MOON: {chain = nil} == {} unless that switch's route block set chain on this step
		return Strategies.functions.evolveNidoking({chain = data and data.chain})
	end


	-- Move replacements of the reference moveset (MEGA PUNCH / WATER GUN / HORN ATTACK / POISON STING after Mt. Moon):
	-- THRASH replaces WATER GUN (reference 32:22; the engine's default is LEER, which we no longer have), BUBBLEBEAM
	-- replaces POISON STING (reference S.S. Anne/Vermilion; engine default TACKLE), ROCK SLIDE replaces MEGA PUNCH,
	-- HORN DRILL replaces THRASH (53:3x), EARTHQUAKE replaces ROCK SLIDE (Safari), BLIZZARD replaces BUBBLEBEAM (Mansion).
	local function refReplacement(move, default)
		if move == "thrash" and not Pokemon.moveIndex("leer", "nidoking") and Pokemon.moveIndex("water_gun", "nidoking") then
			return "water_gun"
		end
		local plan = {bubblebeam = "poison_sting", rock_slide = "mega_punch", horn_drill = "thrash",
			earthquake = "rock_slide", blizzard = "bubblebeam"}
		if plan[move] and Pokemon.moveIndex(plan[move], "nidoking") then
			return plan[move]
		end
		return default
	end
	REFSTRAT_REPLACEMENT = refReplacement
	local engineTeach = Strategies.functions.teach
	Strategies.functions.teach = function(data)
		-- TM13 Ice Beam is not obtained on the reference route (Soda Pop -> TM48 only; Blizzard from the Mansion).
		if data.move == "ice_beam" and not Inventory.contains("ice_beam") then
			return Strategies.closeMenuFor(data)
		end
		-- No eligible learner (e.g. no Paras/Oddish for CUT): fail fast instead of stalling in the TM menu.
		if data.poke and not Pokemon.hasMove(data.move) then
			local list = type(data.poke) == "table" and data.poke or {data.poke}
			if not Pokemon.inParty(unpack(list)) then
				return Strategies.reset("error", "No Pokemon able to learn "..data.move, nil, true)
			end
		end
		local replace = refReplacement(data.move, data.replace)
		if replace ~= data.replace then
			local copy = {}
			for k, v in pairs(data) do copy[k] = v end
			copy.replace = replace
			return engineTeach(copy)
		end
		return engineTeach(data)
	end
	-- teachThrash spends every Rare Candy at L21 to reach L23; it assumes two candies. With fewer it would stall in the
	-- bag, so then skip it (Thrash comes from the L23 level-up in battle, as in the reference at 32:22).
	local engineTeachThrash = Strategies.functions.teachThrash
	Strategies.functions.teachThrash = function(data)
		if Strategies.initialize("refChecked") then
			Strategies.status.refSkip = Pokemon.info("nidoking", "level") + Inventory.count("rare_candy") < 23
		end
		if Strategies.status.refSkip then return true end
		return engineTeachThrash(data)
	end
	-- The L23 THRASH level-up prompt can appear in any battle (the engine only handles it in learnThrash on the
	-- bridge). Answer it everywhere with the reference replacement (WATER GUN).
	local function thrashPrompt()
		if Memory.value("menu", "settings_row") == 8 and Pokemon.inParty("nidoking")
			and Pokemon.info("nidoking", "level") == 23 and not Pokemon.moveIndex("thrash", "nidoking") then
			local column = Memory.value("menu", "column")
			if column == 15 then
				Input.press("A")
				return true
			end
			if column == 5 then
				local replaceIndex = Pokemon.moveIndex(refReplacement("thrash", "leer"), "nidoking")
				if replaceIndex then Menu.select(replaceIndex - 1, true) else Input.cancel() end
				return true
			end
		end
	end
	local engineAutomate = Battle.automate
	Battle.automate = function(...)
		if thrashPrompt() then return end
		return engineAutomate(...)
	end
	local engineHandle = Battle.handle
	Battle.handle = function(...)
		if thrashPrompt() then return end
		return engineHandle(...)
	end
	-- Engine nidokingStats() refreshes stats.nidoran from the Nidoking's visible stats (used by potionBeforeMisty,
	-- potionForMankey, leer checks). It is a local of ai/strategies.lua that the engine only calls from teachThrash /
	-- learnThrash, which our route mostly skips (code review 2026-10-11, finding 2). Reached via an upvalue.
	local engineNidokingStats
	do
		local i = 1
		while true do
			local name, value = debug.getupvalue(Strategies.functions.learnThrash, i)
			if not name then break end
			if name == "nidokingStats" then engineNidokingStats = value break end
			i = i + 1
		end
		assert(engineNidokingStats, "refstrat: nidokingStats not found")
	end
	local function refreshNidokingStats()
		if Pokemon.inParty("nidoking") and Pokemon.indexOf("nidoking") == 0 then
			engineNidokingStats()
		end
	end
	S.refNidokingStats = function()
		refreshNidokingStats()
		return true
	end
	-- learnThrash (level-up prompt in battle at L23) with the same replacement rule.
	Strategies.functions.learnThrash = function()
		local status = Strategies.status
		if Strategies.initialize() then
			if Pokemon.info("nidoking", "level") ~= 22 then
				return true
			end
		end
		if Strategies.trainerBattle() then
			if Pokemon.moveIndex("thrash", "nidoking") then
				refreshNidokingStats()
				return true
			end
			if Memory.value("menu", "settings_row") == 8 then
				local column = Memory.value("menu", "column")
				if column == 15 then
					Input.press("A")
					return false
				end
				if column == 5 then
					local replaceIndex = Pokemon.moveIndex(refReplacement("thrash", "leer"), "nidoking")
					if replaceIndex then
						Menu.select(replaceIndex - 1, true)
					else
						Input.cancel()
					end
					return false
				end
			end
			Battle.automate()
		elseif status.foughtTrainer then
			return true
		end
	end


	-- Enter a warp that needs a direction press while standing on it (e.g. the Cerulean burgled-house hole from
	-- behind, reference 36:19-36:23): press toward it until the map changes.
	S.refWarpDir = function(data)
		local st = Strategies.status
		local map = Memory.value("game", "map")
		if not st.map then st.map = map end
		if map ~= st.map then return true end
		if not Textbox.isActive() and not Menu.isOpened() then
			Input.press(data.dir or "Down", 2)
		end
		return false
	end

	-- Item ids missing from the engine's item table (storage/inventory.lua local items).
	do
		local i = 1
		while true do
			local name, value = debug.getupvalue(Inventory.indexOf, i)
			if not name then break end
			if name == "items" then
				value.blizzard = 214
				value.tm06 = 206
				value.parlyz_heal = value.paralyze_heal
				break
			end
			i = i + 1
		end
	end

	-- Celadon roof (reference 52:0x): Soda Pop only for the girl (TM48 Rock Slide); Fresh Water is kept for the
	-- Saffron guard (bought after, by the inherited shopExtraWater).
	S.refVendSoda = function()
		-- v19 edit J3: unpayable purchase -> logged skip (see shopGuard below)
		if REFSTRAT_SHOP_UNPAYABLE and REFSTRAT_SHOP_UNPAYABLE("soda_pop", 300) then return true end
		return Shop.vend {direction = "Up", buy = {{name = "soda_pop", index = 1}}}
	end

	-- Vermilion Mart (reference 40:44-41:12): sell TM34 and the Nugget, buy 3 Repel and 3 Parlyz Heal.
	S.refShopVermilion = function()
		-- v19 edit A (S3/S4, reference 40:56-41:06): sell TM34, sell the Nugget, buy REPEL x3, then PARLYZ HEAL x3 (purchase
		-- quantities, targets fixed at entry); no Super Potion (the v4.2/v18 Super Potions are removed).
		local st = Strategies.status
		if st.repTarget == nil then
			st.repTarget, st.parTarget = Inventory.count("repel") + 3, Inventory.count("paralyze_heal") + 3
			print(string.format("refstrat SHOP S3/S4 Vermilion: reference list sell TM34 (%d), sell NUGGET (%d); REPEL x3 (bag -> %d), PARLYZ_HEAL x3 (bag -> %d), money %d",
				Inventory.count("tm34"), Inventory.count("nugget"), st.repTarget, st.parTarget, REFSTRAT_MONEY()))
		end
		-- (history: v4.1 dropped the v2/v3 Super Potions and lost S.S. Anne / Surge seeds to "Ran out of potions"; v19
		-- covers that stretch with the post-Misty Cerulean Center recovery and the RB2 Potion floor instead, edit C)
		return Shop.transaction {sell = {{name = "tm34"}, {name = "nugget"}},
			buy = {{name = "repel", index = 5, amount = st.repTarget}, {name = "paralyze_heal", index = 4, amount = st.parTarget}}}
	end


	-- Blizzard (reference TM14 from the Mansion, used on Giovanni/rival/Agatha/Lance) replaces the engine's Ice Beam:
	-- forced "ice_beam" choices select Blizzard; Red's Blizzard accuracy is 90% (controller table had a later value);
	-- Blizzard PP (5) restored after Agatha when low (ported from upgrades/wr-blizzard-addon.lua).
	require("data.movelist").get(59).accuracy = 90
	local function mapIce(move)
		if move == "ice_beam" and Pokemon.battleMove and Pokemon.battleMove("blizzard") then return "blizzard" end
		return move
	end
	local automateBeforeIce = Battle.automate
	Battle.automate = function(move, skipBuffs)
		return automateBeforeIce(mapIce(move), skipBuffs)
	end
	local fightBeforeIce = Battle.fight
	Battle.fight = function(move, ...)
		return fightBeforeIce(mapIce(move), ...)
	end
	S.refRestoreBlizzard = function(data)
		local status = Strategies.status
		if Strategies.initialize("checkedBlizzard") then
			local slot = Pokemon.moveIndex("blizzard", "nidoking")
			if not slot then
				status.skip = true
			else
				local pp = Memory.raw(0x116B + Pokemon.indexOf("nidoking") * 0x2C + 28 + slot)
				status.skip = bit.band(pp, 0x3F) >= 5
			end
		end
		if status.skip then return Strategies.closeMenuFor(data) end
		data.item = status.item
		if status.item and Strategies.completedMenuFor(data) then
			return Strategies.closeMenuFor(data)
		end
		if not status.item then
			status.item = Inventory.contains("ether", "max_ether", "elixer")
			if not status.item then return Strategies.closeMenuFor(data) end
			status.startCount = Inventory.count(status.item)   -- done after one use (review finding 8)
		end
		if status.item == "elixer" then
			data.item, data.poke = "elixer", "nidoking"
			return Strategies.useItem(data)
		end
		if Memory.value("menu", "main") == 144 and Menu.getCol() == 5 then
			if Menu.canCloseMessage() then Input.cancel()
			else Menu.select(Pokemon.moveIndex("blizzard", "nidoking"), true) end
		elseif Menu.pause() then Inventory.use(status.item, "nidoking") end
		return false
	end


	-- Use an item only if we have it (reference: Rare Candy at Bill's, 33:14).
	S.refUseIf = function(data)
		if Strategies.initialize("refChecked") then
			Strategies.status.refSkip = not Inventory.contains(data.item)
			-- Rare Candies reaching L23 would trigger the THRASH learn prompt outside battle, which the item menu
			-- cancels; keep them then (Thrash comes from the next battle level-up, the candies are used later).
			local level = Pokemon.inParty("nidoking") and Pokemon.info("nidoking", "level") or 99
			if data.item == "rare_candy" and level < 23 and not Pokemon.moveIndex("thrash", "nidoking")
				and level + (data.all and Inventory.count("rare_candy") or 1) >= 23 then
				Strategies.status.refSkip = true
			end
		end
		if Strategies.status.refSkip then return true end
		return Strategies.functions.item(data)
	end

	-- Conditional Pokemon Center heal (not in the reference: it healed with 2 Potions at Bill's, 33:17, and fought the
	-- Rocket at 61/81 and Misty at 50/81). Checked after the Rocket on the way to the gym (+4 steps): if the lead cannot
	-- be brought to `frac` of max HP with the Potions left, heal (also restores PP). {s="refMaybeHeal", map=3, door={19,17}, center=64}
	local Combat = require "ai.combat"
	S.refMaybeHeal = function(data)
		local st = Strategies.status
		if st.need == nil and data.postMansion then
			-- v19 edit E1 (row 23b, after the Koga faint, candy revive and Mansion; reference: Erika 10/142, Blaine 13/145,
			-- Sabrina 16/148, no heal, O): the inherited Cinnabar (11,12) step heals below 70; the Dig lands at the Celadon
			-- Center door first (the reference's own last Center: Dig return point unchanged), so the same trigger is
			-- served by the Center. The nurse also restores PP incidentally (e.g. Thunderbolt 14 -> 15; the reference PP
			-- actions still execute, PLAN.md 13 item 6). RECOVERY (healing), not shopping.
			local target = 70
			if LATE_RED and Inventory.count("full_restore") >= (MANSION_FR_SKIP and 1 or 2) then   -- v26: banked Mansion Full Restore replaces this Center (v59 r2: one is enough without the Mansion pickup; paired test r1: 9-HP runs took the Center)
				target = 0
				print("refstrat LATE_RED: Full Restores " .. Inventory.count("full_restore") .. " -> no post-Mansion Center (red HP like the record)")
			end
			local ni = Pokemon.indexOf("nidoking")
			local pp = {}
			if ni and ni >= 0 then for _, mv in ipairs({"thunderbolt", "horn_drill", "earthquake", "blizzard"}) do pp[#pp + 1] = mv.." "..tostring(Pokemon.pp(ni, mv)) end end
			st.need = Combat.hp() < target
			print("refstrat Celadon Center decision (row 23b, after the Mansion): hp "..Combat.hp().."/"..Combat.maxHP().." target "..target
				.." PP "..table.concat(pp, ", ").." -> "..(st.need and "RECOVERY: Pokemon Center (HP below the Cinnabar step's survival target)" or "no Center (reference branch)"))
		end
		if st.need == nil and data.postMisty then
			-- v19 edit C (row 17, after Misty .. Surge; reference: no heal, O): the inherited Route 5 Potion step heals
			-- below its survival target 50 (40 under yolo); the route passes the Cerulean Center door first, so the
			-- same trigger is served by the Center (free; HP and PP). Same Center as the reference's row 13 heal, so the
			-- Dig / Escape Rope return point does not change. RECOVERY (healing), not shopping.
			local target = HPM_T or (Control.yolo and 40 or 50)   -- v24 HPM_T
			local items = Inventory.count("potion") + Inventory.count("super_potion")
			local low = Combat.hp() < target
			local empty = items == 0 and Combat.hp() < (HPM_T and (HPM_T + 20) or Combat.maxHP())   -- v19 edit H; v24 HPM_T
			st.need = low or empty
			print("refstrat Cerulean Center decision (row 17, after Misty): hp "..Combat.hp().."/"..Combat.maxHP().." target "..target
				.." healing items "..items.." -> "..(low and "RECOVERY: Pokemon Center (HP below the Route 5 step's survival target)"
				or (empty and "RECOVERY: Pokemon Center (no healing item held until Celadon, HP below max)") or "no Center (reference branch)"))
		end
		if st.need == nil then
			local potions = Inventory.count("potion") * 20 + Inventory.count("super_potion") * 50
			if data.mistyFloor and REFSTRAT_MISTY_FLOOR then
				-- v17 (row 16): after the Cerulean Rocket the reference does not visit the Center. RECOVERY only if HP plus all
				-- healing items cannot reach Misty's one-hit floor (the Misty recovery could not be paid from the bag).
				local floor = REFSTRAT_MISTY_FLOOR()
				local margin = 20   -- v19 edit G: in-gym trainer damage before Misty (330 of 336 observations <= 20, search/margin_hist.txt)
				st.need = Combat.hp() + potions < floor + margin
				if REFSTRAT_MISTY_TACTIC(1) then   -- v41 MISTY_TACTIC bit 1: Center only far below the floor
					st.need = Combat.hp() + potions < (MISTY_CENTER_HP or 30)
					print("refstrat MISTY_TACTIC center gate (row 16): hp "..Combat.hp().." + potion hp "..potions.." vs "..(MISTY_CENTER_HP or 30)
						.." -> "..(st.need and "Center" or "no Center"))
				end
				print("refstrat Cerulean Center decision (row 16): hp "..Combat.hp().."/"..Combat.maxHP().." potion hp "..potions.." Misty floor "..floor.." + gym margin "..margin
					.." -> "..(st.need and "RECOVERY: Pokemon Center (bag cannot reach the floor)" or "no Center (reference branch)"))
			else
				st.need = Combat.hp() + potions < (data.frac or 0.7) * Combat.maxHP()
				print("refstrat heal check: hp "..Combat.hp().."/"..Combat.maxHP().." potion hp "..potions.." -> "..(st.need and "Pokemon Center" or "skip"))
			end
		end
		if not st.need then return true end
		local map = Memory.value("game", "map")
		local px, py = Player.position()
		if map == data.map then
			if st.healed then return true end
			Walk.step(data.door[1], data.door[2])
		elseif map == data.center then
			if not st.healed then
				if px ~= 3 or py ~= 3 then
					Walk.step(3, 3)
				elseif Strategies.functions.dialogue({dir = "Up"}) then
					st.healed = true
				end
			else
				Walk.step(3, 8)
			end
		end
		return false
	end


	-- Bag space (20 slots). The reference's bag was full too (refused TM06/TM21/TM38); the Secret Key must fit:
	-- toss items that are no longer needed.
	S.refMakeSpace = function()
		if Strategies.initialize("refChecked") then
			Strategies.status.refSkip = not Inventory.isFull()
		end
		if Strategies.status.refSkip then return true end
		-- Key items (Helix Fossil, S.S. Ticket) cannot be tossed (review finding 1). TM06 (Koga) is unused on this
		-- route; Parlyz Heals were for Rock Tunnel (passed). tossItem tosses one unit per pass until the slot frees.
		return Strategies.tossItem("tm06", "paralyze_heal")
	end


	-- Elixer only if one is left (the inherited strategy assumes it).
	S.refElixerIf = function(data)
		if Strategies.initialize("refChecked") then
			Strategies.status.refSkip = not Inventory.contains("elixer")
			if not Strategies.status.refSkip and data.moves then
				-- v3: Elixer when ANY listed move is below its minimum (v2 checked Horn Drill only, so the Viridian
				-- rival was fought with Blizzard 0 / Earthquake 1 PP while 2 Elixers stayed in the bag).
				local low
				for move, min in pairs(data.moves) do
					local idx = Pokemon.moveIndex(move, "nidoking")
					if idx and Pokemon.pp(0, move) < min then low = move end
				end
				Strategies.status.refSkip = low == nil
				if low then Strategies.status.refMove = low end
			end
		end
		if Strategies.status.refSkip then return true end
		if data.moves then
			return Strategies.functions.elixer({move = Strategies.status.refMove, min = 99, chain = data.chain})
		end
		return Strategies.functions.elixer(data)
	end


	-- v3 Misty preparation from the ACTUAL battle state (replaces the inherited potionBeforeMisty, whose speed-DV
	-- thresholds assume the old EXP plan). Starmie's trainer stats are fixed (L21, DVs 9/8/8/8): HP 59, Def 44,
	-- Spd 56, Spc 50 (observed identical in all traced fights). Gen 1 damage formula; BubbleBeam is STAB and 2x vs
	-- Nidoking (ground). Thrash (90, normal) is our move; it carries over from Staryu. Requirement:
	--   hits needed  = ceil(59 / min Thrash roll)
	--   hits taken   = hits needed if Starmie moves first (our speed <= 56), else hits needed - 1, +1 if BubbleBeam's
	--                  speed drop could hand Starmie the first move (we outspeed by less than x1.5)
	--   target HP    = hits taken * max BubbleBeam + 1, capped at max HP (then: as healthy as possible).
	local function gen1Damage(level, power, atk, def, stab, eff, roll)
		local base = math.floor(math.floor(math.floor(2 * level / 5 + 2) * power * atk / def) / 50) + 2
		if stab then base = math.floor(base * 3 / 2) end
		base = math.floor(base * eff)
		return math.floor(base * roll / 255)
	end
	REFSTRAT_MISTY_PLAN = function()
		local level = Pokemon.index(0, "level")
		local atk, spd, spc, maxHP = Pokemon.index(0, "attack"), Pokemon.index(0, "speed"), Pokemon.index(0, "special"), Pokemon.index(0, "max_hp")
		local maxBB = gen1Damage(21, 65, 50, spc, true, 2, 255)
		local minThrash = math.max(1, gen1Damage(level, 90, atk, 44, false, 1, 217))
		local hitsNeeded = math.ceil(59 / minThrash)
		local outspeeds = spd > 56
		local hitsTaken = outspeeds and hitsNeeded - 1 or hitsNeeded
		if outspeeds and math.floor(spd * 2 / 3) <= 56 and hitsNeeded > 1 then hitsTaken = hitsTaken + 1 end
		local target = math.min(maxHP, hitsTaken * maxBB + 1)
		return {level = level, speed = spd, outspeeds = outspeeds, maxBB = maxBB, minThrash = minThrash, hitsNeeded = hitsNeeded,
			hitsTaken = hitsTaken, target = target, maxHP = maxHP, survivable = hitsTaken * maxBB < maxHP}
	end
	-- v17 Misty policy (healing table rows 15-16; HEAL_SHOP_BIRD.md:72, 101, 420): the reference prepares at Bill's (two
	-- Potions, 18 -> 61/81) and does NOT heal again before Misty (entered at 50/81, "basically 50 % dead here", risk
	-- accepted). Reference branch = no heal. One RECOVERY: if Nidoking could not survive even a single maximum NON-CRITICAL
	-- BubbleBeam (HP <= maxBB from the Starmie model above; party stats before Staryu, so an approximation), Potions to maxBB + 1 only - the reference's own 50/81 entry
	-- survives one maximum hit; a state below that floor is outside the reference's accepted-risk branch.
	REFSTRAT_MISTY_FLOOR = function() local p = REFSTRAT_MISTY_PLAN() return p.maxBB + 1, p end
	S.refMistyPrep = function()
		local st = Strategies.status
		if not st.plan then
			local floor, p = REFSTRAT_MISTY_FLOOR()
			st.plan, st.floor = p, floor
			local hp = Pokemon.index(0, "hp")
			st.heal = hp < floor
			print(string.format("refstrat Misty decision (row 16): L%d hp %d/%d maxBB %d floor %d outspeeds=%s hitsNeeded %d potions %d+%d -> %s",
				p.level, hp, p.maxHP, p.maxBB, floor, tostring(p.outspeeds), p.hitsNeeded, Inventory.count("potion"), Inventory.count("super_potion"),
				st.heal and "RECOVERY: Potions to the one-hit floor (HP <= max non-critical BubbleBeam)" or "no heal (reference branch)"))
			if REFSTRAT_MISTY_TACTIC(2) then
				-- v41 bit 2: a Potion here costs ~5.5 s + instant text (Misty fight +9.9 s, Misty->Surge +11.5 s, recorded medians).
				-- After Staryu (always one-shot by Thrash: badge Atk 66, min 42 = Staryu HP) Nidoking is L25, Spd 57 > Starmie 56,
				-- so Starmie usually acts once: a critical BubbleBeam (61-72) is the main killer. Heal only when HP is so low that a
				-- plain hit kills, and then past the critical (HP + 3 level-up HP > 72); further Potions cost only ~3.3 s each.
				st.heal = hp < (MISTY_POTION_HP or 30)
				st.floor = math.min(p.maxHP, MISTY_POTION_TO or 70)
				print(string.format("refstrat MISTY_TACTIC prep: hp %d/%d below %d -> %s", hp, p.maxHP, MISTY_POTION_HP or 30,
					st.heal and ("Potions to "..st.floor) or "no heal (keeps instant text)"))
			end
		end
		if not st.heal then return true end
		return Strategies.functions.potion({hp = st.floor})
	end
	-- v41 MISTY_TACTIC bit mask (unset = v39): 1 Center gate, 2 Misty Potion rule, 4 no confusion swap; true = 7
	REFSTRAT_MISTY_TACTIC = function(part)
		local m = MISTY_TACTIC
		if not m then return false end
		if m == true then m = 7 end
		return bit.band(m, part) ~= 0
	end
	-- v41 bit 4: the engine's fightMisty swaps to a sacrifice (Pidgey) when Thrash ends with Starmie alive and Nidoking
	-- confused; that opens the Pokemon menu (instant text lost), costs two switches, and when the sacrifice survives
	-- (Starmie Tackle / Harden, 50 %) Starmie still hits Nidoking on the way back. Recorded: 649 of 7037 won fights needed a
	-- second Thrash, +20.3 s in the fight and +11.5 s Misty->Surge. Starmie is then at 0-10 HP (X Defend branch) and we
	-- move first: any hit (50 % while confused) ends the fight. Here: hit through confusion (best move; Thrash).
	local engineFightMisty = Strategies.functions.fightMisty
	S.fightMisty = function()
		if not REFSTRAT_MISTY_TACTIC(4) then return engineFightMisty() end
		local st = Strategies.status
		if Strategies.trainerBattle() then
			if Battle.redeployNidoking() then return false end
			if Battle.opponentAlive() and Combat.isConfused() and not st.mistyConfLog then
				st.mistyConfLog = true
				print("refstrat MISTY_TACTIC: confused, "..Battle.opponent().." hp "..Memory.double("battle", "opponent_hp")
					.." -> hit through confusion (no swap), hp "..Combat.hp().." frame "..emu.framecount())
			end
			Battle.automate()
		elseif st.foughtTrainer then
			return true
		end
	end


	-- v3: conditional Cerulean Mart stop (not in the reference). The gym now includes the Swimmer (EXP for L25 before
	-- Starmie), whose damage must be healable before Misty; a Center heal alone leaves no Potions (seed 1720000000:
	-- 24/78 HP and 0 Potions at Misty). If fewer than `min` Potions remain, round trip PC door -> Mart -> PC door and
	-- buy Potions up to `min` (Shop amounts are bag targets). Paths: plan_path.py (walls, objects).
	local function stepToward(tx, ty)
		local px, py = Player.position()
		if px ~= tx then Walk.step(tx, py) else Walk.step(px, ty) end
	end
	local function walkPoints(st, key, points)
		local px, py = Player.position()
		st[key] = st[key] or 1
		while points[st[key]] and px == points[st[key]][1] and py == points[st[key]][2] do st[key] = st[key] + 1 end
		local wp = points[st[key]]
		if not wp then return true end
		stepToward(wp[1], wp[2])
		return false
	end
	-- v19 edit N (RB3, shopping RECOVERY; tools/edit_c3_n.py): after the S.S. Anne, one Super Potion at the Vermilion
	-- Mart only when no Potion / Super Potion is held and HP < 30 (Surge entries in that state died 3 of 4 times; the
	-- reference reached Surge at 13/91 with 3 unused Potions). A Center would move the Dig return point.
	S.refVermilionRB3 = function()
		local st = Strategies.status
		if st.need == nil then
			local p, s, money, target = Inventory.count("potion"), Inventory.count("super_potion"), REFSTRAT_MONEY(), 30
			local state = p + s == 0 and Combat.hp() < target
			st.need = state and money >= 700
			st.superTarget = s + 1
			print(string.format("refstrat SHOP RB3 Vermilion check (after the S.S. Anne, before Surge): hp %d/%d target %d, Potions %d, Super Potions %d, money %d -> %s",
				Combat.hp(), Combat.maxHP(), target, p, s, money, st.need and "RECOVERY: buy SUPER_POTION x1"
				or (state and "no purchase (money below 700)" or "no purchase (reference branch)")))
		end
		if not st.need then return true end
		if not Battle.handleWild() then return false end
		local map = Memory.value("game", "map")
		if map == 91 and st.bought and (Textbox.isActive() or Menu.isOpened())
			and emu.framecount() - (st.closing or emu.framecount()) < 300 then
			if not st.closing then st.closing = emu.framecount(); print("refstrat Vermilion Mart (RB3): closing shop menus with B") end
			Input.press("B")
			return false
		end
		if not (map == 91 and not st.bought) and not Textbox.handle() then return false end
		if map == 5 then
			if st.bought then return true end
			walkPoints(st, "to", {{23,13}})
		elseif map == 91 then
			if not st.bought then
				if walkPoints(st, "inMart", {{3,5}, {2,5}}) then
					if not st.rb3logged then
						st.rb3logged = true
						print(string.format("refstrat SHOP RECOVERY RB3 Vermilion: buy SUPER_POTION x1 (bag %d -> %d), money %d",
							st.superTarget - 1, st.superTarget, REFSTRAT_MONEY()))
					end
					if Shop.transaction {buy = {{name = "super_potion", index = 1, amount = st.superTarget}}} then
						st.bought = true
						print("refstrat Vermilion Mart (RB3): Super Potions now "..Inventory.count("super_potion"))
					end
				end
			else
				walkPoints(st, "outMart", {{3,5}, {3,8}})
			end
		end
		return false
	end
	-- v22 ROUTE_MISTY_DIRECT: the row-16 Center decision of refMaybeHeal (mistyFloor, frac 1.0) taken at the Rocket;
	-- no Center -> the record's path (33,9) (33,18) ledge (33,20), round the NPC on row 21, gym door (30,19), skipping the house entries
	local MISTY_DIRECT = {{33,9}, {33,18}, {33,20}, {33,21}, {30,21}, {30,20}, {30,19}}   -- row 21: an NPC stands at (31,20) (dev, seed 1820500000)
	S.refMistyDirect = function()
		local st = Strategies.status
		if st.direct == nil then
			local potions = Inventory.count("potion") * 20 + Inventory.count("super_potion") * 50
			local need, rule
			if REFSTRAT_MISTY_FLOOR then
				local floor = REFSTRAT_MISTY_FLOOR()
				need, rule = Combat.hp() + potions < floor + 20, "Misty floor "..floor.." + gym margin 20"
				if REFSTRAT_MISTY_TACTIC(1) then   -- v41: a Center costs ~28 s walk + instant text (~21 s), see REPORT.md
					need, rule = Combat.hp() + potions < (MISTY_CENTER_HP or 30), "v41 MISTY_TACTIC center gate "..(MISTY_CENTER_HP or 30)
				end
			else
				need, rule = Combat.hp() + potions < Combat.maxHP(), "max hp"
			end
			st.direct = not need
			print("refstrat ROUTE misty direct: hp "..Combat.hp().."/"..Combat.maxHP().." potion hp "..potions.." "..rule
				.." -> "..(st.direct and "direct to the gym (no Center)" or "Center needed: v21 route"))
		end
		if not st.direct then return true end
		if Memory.value("game", "map") == 65 then
			if not st.skipped then
				st.skipped = true
				Walk.skipPaths(2)   -- the house entry and the front-door -> gym entry
				print("refstrat ROUTE misty direct: in the gym at frame "..emu.framecount())
			end
			return true
		end
		if not Textbox.handle() then return false end
		walkPoints(st, "misty", MISTY_DIRECT)
		return false
	end

	-- v26 LATE_RED: one banked Full Restore at Viridian before the gym trainers (HP < 80, 2+ held; one kept for the League)
	S.refLateFR = function(data)
		local st = Strategies.status
		if RED_LATE then   -- v35: no heal here; red HP to the end of Lorelei
			if not REFSTRAT_RED_WINDOW then
				REFSTRAT_RED_WINDOW = true
				print("refstrat RED_LATE: red-HP window opens at Viridian (hp " .. Combat.hp() .. "/" .. Combat.maxHP() .. ", Full Restores " .. Inventory.count("full_restore") .. ")")
			end
			return true
		end
		if st.go == nil then
			st.go = LATE_RED and Inventory.count("full_restore") >= 2 and Combat.hp() < 80
			print("refstrat LATE_RED Viridian: hp " .. Combat.hp() .. "/" .. Combat.maxHP() .. " Full Restores " .. Inventory.count("full_restore")
				.. " -> " .. (st.go and "use one Full Restore" or "no Full Restore"))
		end
		if not st.go then return true end
		return Strategies.functions.potion({hp = 999, forced = "full_restore", chain = true})
	end
	-- v58 SHIP_FIRST (= v22 ROUTE_SHIP_FIRST): the reference Vermilion Mart list after the S.S. Anne (record order), on
	-- the way to Surge
	S.refShopVermilionLate = function()
		local st = Strategies.status
		if not Battle.handleWild() then return false end
		local map = Memory.value("game", "map")
		if map == 91 and st.bought and (Textbox.isActive() or Menu.isOpened())
			and emu.framecount() - (st.closing or emu.framecount()) < 300 then
			st.closing = st.closing or emu.framecount()
			Input.press("B")
			return false
		end
		if not (map == 91 and not st.bought) and not Textbox.handle() then return false end
		if map == 5 then
			if st.bought then return true end
			walkPoints(st, "to", {{23,13}})
		elseif map == 91 then
			if not st.bought then
				-- v58 r2 fix (paired test: 33/226 stalls): the RB3 recovery step after this one walked back to the Mart door
				-- it was standing on and waited forever. Its rule (no Potion / Super Potion, HP < 30, money >= 700) is now
				-- applied here, in the same visit: the Super Potion joins this transaction and RB3 then finds one in the bag.
				if st.lateRB3 == nil then
					local pp, sp = Inventory.count("potion"), Inventory.count("super_potion")
					st.lateRB3 = (pp + sp == 0 and Combat.hp() < 30 and REFSTRAT_MONEY() >= 700) and (sp + 1) or false
					print("refstrat ROUTE ship first: RB3 rule in the late Mart: hp "..Combat.hp()..", Potions "..pp..", Super Potions "..sp
						..", money "..REFSTRAT_MONEY().." -> "..(st.lateRB3 and "add SUPER_POTION x1" or "no Super Potion"))
				end
				local done
				if walkPoints(st, "inMart", {{3,5}, {2,5}}) then
					if not st.lateRB3 then done = S.refShopVermilion()
					else
						if st.repTarget == nil then st.repTarget, st.parTarget = Inventory.count("repel") + 3, Inventory.count("paralyze_heal") + 3 end
						done = Shop.transaction {sell = {{name = "tm34"}, {name = "nugget"}},
							buy = {{name = "repel", index = 5, amount = st.repTarget}, {name = "paralyze_heal", index = 4, amount = st.parTarget},
								{name = "super_potion", index = 1, amount = st.lateRB3}}}
					end
				end
				if done then
					st.bought = true
					print("refstrat ROUTE ship first: Vermilion Mart after the ship done at frame "..emu.framecount())
				end
			else
				walkPoints(st, "outMart", {{3,5}, {3,8}})
			end
		end
		return false
	end
	-- v19 edit M (row 14b): Cerulean Center recovery before Nugget Bridge when no healing item is held and HP is below
	-- the bridge's first recovery step target (12, yolo 10); see experiments/refstrat-v19-2026-10-12/tools/edit_c2_m.py
	local PRE_NUGGET_TO = {{21,12}, {8,12}, {8,16}, {17,16}, {17,18}, {19,18}}
	local PRE_NUGGET_BACK = {{17,18}, {17,16}, {8,16}, {8,12}, {21,12}, {21,6}}
	S.refPreNuggetCenter = function()
		local st = Strategies.status
		if st.need == nil then
			local items = Inventory.count("potion") + Inventory.count("super_potion")
			local target = Control.yolo and 10 or 12
			local survival = items == 0 and Combat.hp() < target
			-- v19 edit O: <= 2 healing items (Bill's maximum reference heal) and HP below max -> cross the bridge at full HP
			local reserve = not PRE_BRIDGE_RELAX and items <= 2 and Combat.hp() < Combat.maxHP()   -- v24 PRE_BRIDGE_RELAX
			st.need = survival or reserve
			print("refstrat Cerulean Center decision (row 14b, before Nugget Bridge): hp "..Combat.hp().."/"..Combat.maxHP().." target "..target
				.." healing items "..items.." -> "..(survival and "RECOVERY: Pokemon Center (no healing item, HP below the bridge step's survival target)"
				or (reserve and "RECOVERY: Pokemon Center (<= 2 healing items kept for Bill's reference heal, HP below max)") or "no Center (reference branch)"))
		end
		if not st.need then return true end
		local map = Memory.value("game", "map")
		local px, py = Player.position()
		-- v19 edit M2 (c2diagM: the rival's post-battle text was still open and the walk held Down forever): close any
		-- open textbox before walking, as refMaybeMart does; the nurse dialogue inside the Center handles its own text
		if map ~= 64 and not Textbox.handle() then return false end
		if map == 3 then
			if not st.healed then
				if walkPoints(st, "to", PRE_NUGGET_TO) then Walk.step(19, 17) end
			elseif walkPoints(st, "back", PRE_NUGGET_BACK) then
				return true
			end
		elseif map == 64 then
			if not st.healed then
				if px ~= 3 or py ~= 3 then
					Walk.step(3, 3)
				elseif Strategies.functions.dialogue({dir = "Up"}) then
					st.healed = true
				end
			else
				Walk.step(3, 8)
			end
		end
		return false
	end

	-- v8 RECOVERY (not in the reference): before the Nidoran save, a Squirtle at <= 17 HP is healed at the Viridian
	-- Pokemon Center. The reference path takes no Potions (tree / forest Potions skipped, Viridian Mart sells none) and
	-- relied on several Weedle String Shots; in v8 section runs two chain-intact games lost Squirtle (17 HP, Defense DV
	-- 2-3) to the Bug Catcher's Weedle. Squirtle fights nothing between the save and that battle, so its HP there is
	-- the HP at the save; the heal does not change the post-reset inputs (HP is not part of the timing).
	S.refViridianHealIf = function(data)
		local st = Strategies.status
		if VIRIDIAN_SKIP and st.smart == nil then   -- v35: = v25 E7 (EARLY_SMART, empty override table)
			local ok_keys = {["15/21"] = true, ["16/22"] = true, ["20/23"] = true, ["19/21"] = true, ["18/23"] = true}
			local hp, mx = Pokemon.info("squirtle", "hp"), Pokemon.info("squirtle", "max_hp")
			local key = hp .. "/" .. mx
			local ok = hp == mx or ok_keys[key]
			st.smart = ok and "skip" or "heal"
			print("refstrat EARLY smart: Squirtle " .. key .. " -> " .. (ok and "no Center (supported key)" or "RECOVERY: Center (unsupported key)")
				.. (data.after and " (after the EXP detour)" or ""))
		end
		if VIRIDIAN_SKIP and st.smart == "skip" then return true end
		if VIRIDIAN_SKIP then data = setmetatable({full = true}, {__index = data}) end
		if st.go == nil then
			local hp = Pokemon.info("squirtle", "hp")
			st.go = data.full and hp < Pokemon.info("squirtle", "max_hp") or hp <= (data.hp or 17)
			print(st.go and ("refstrat RECOVERY: Viridian Center heal before the Nidoran save (Squirtle "..hp.." HP"..(data.after and ", after the EXP detour" or "")..")")
				or ("refstrat: no Viridian heal (reference path; Squirtle "..hp.." HP"..(data.after and ", after the EXP detour" or "")..")"))
		end
		if not st.go then return true end
		if not Battle.handleWild() then return false end
		local map = Memory.value("game", "map")
		if map == 41 then
			if not st.healed then
				if walkPoints(st, "in", {{3,3}}) and Strategies.functions.dialogue({dir = "Up"}) then st.healed = true end
				return false
			end
			if not Textbox.handle() then return false end
			walkPoints(st, "out", {{3,7}, {3,8}})
			return false
		end
		if not Textbox.handle() then return false end
		if not st.healed then
			-- v14: the post-detour check starts at (15,20) (detour end) and first walks the route's street to (29,20)
			walkPoints(st, "to", data.after and {{29,20}, {29,26}, {23,26}, {23,25}} or {{29,26}, {23,26}, {23,25}})
			return false
		end
		return walkPoints(st, "back", {{15,26}, {15,20}})
	end
	-- v9: turn in place on a save tile (pokered home/overworld.asm: a direction pressed while standing, other than the
	-- last stop direction, only turns the player; held on the next poll it moves). One 1-frame press, then 21 frames
	-- to see the facing change. If a press moved the player anyway, walk back and retry (logged; at most 3 tries).
	S.refFaceAt = function(data)
		local st = Strategies.status
		if not Textbox.handle() then return false end
		local px, py = Player.position()
		if Player.isFacing(data.dir) and px == data.x and py == data.y then
			if st.tries then print("refstrat: facing "..data.dir.." at ("..px..","..py..") after "..st.tries.." press(es)") end
			return true
		end
		if px ~= data.x or py ~= data.y then
			if not st.away then
				st.away = true
				print("refstrat RECOVERY: the turn press moved the player to ("..px..","..py.."); back to ("..data.x..","..data.y..")")
			end
			if (st.tries or 0) >= 3 then
				return Strategies.reset("error", "Could not face "..data.dir.." on the save tile", nil, true)
			end
			Walk.step(data.x, data.y)
			return false
		end
		st.away = false
		local now = emu.framecount()
		if not st.at or now - st.at >= 21 then   -- odd: the overworld reads the pad on alternate frames
			if (st.tries or 0) >= 12 then return Strategies.reset("error", "Could not face "..data.dir.." on the save tile", nil, true) end
			st.at, st.tries = now, (st.tries or 0) + 1
			Input.press(data.dir, 0)
		end
		return false
	end
	-- v8: to the Route 3 save tile (27,11), arriving facing Down (reference 17:08-17:10: R3 then D6 from (24,5)). After
	-- the inherited flier backup (east grass, ends at x > 33) the way back retraces that backup's own path.
	S.refRoute3SaveTile = function()
		local st = Strategies.status
		if not Battle.handleWild() or not Textbox.handle() then return false end
		if st.points == nil then
			local px, py = Player.position()
			st.points = px > 28 and {{32,11}, {32,10}, {27,10}, {27,11}} or (px == 27 and {{27,10}, {27,11}} or {{26,py}, {26,10}, {27,10}, {27,11}})
		end
		return walkPoints(st, "save", st.points)
	end
	-- v8: flier backup (no Route 2 Pidgey) in the WEST part of the Route 3 grass, (25,12) <-> (26,12): from x <= 27 the
	-- trainers east of x = 28 (Lass (33,10) ...) are never on screen before the Mt. Moon save, so their saved sprite
	-- state (facing, movement delay) stays at its map-load value and the post-reset RNG does not depend on this detour
	-- (v8 offline finding: saves 030/035 diverged at frame 890 in exactly those sprite bytes). The v7 backup paced at
	-- x = 32-37. Logged.
	-- v9 (v8 final review, h8-1798100023: 40 steps without an encounter, then "No Pokemon able to learn fly" at HM02,
	-- 33 game minutes later): the search is bounded by FLIER_MAX_STEPS steps / FLIER_MAX_FRAMES frames and ends either
	-- with a Fly learner in the party or with an explicit reset here naming the exhausted resource (steps, frames or
	-- Poke Balls). The bot never continues towards Fly without a learner. Pre-save, so the Mt. Moon chain is unaffected.
	local FLIER_MAX_STEPS, FLIER_MAX_FRAMES = 160, 20000
	REFSTRAT_FLIER_LIMITS = {steps = FLIER_MAX_STEPS, frames = FLIER_MAX_FRAMES}
	S.refFlierBackupWest = function()
		local st = Strategies.status
		local lim = REFSTRAT_FLIER_LIMITS
		if st.go == nil then
			st.go = not Pokemon.inParty("pidgey", "spearow", "pidgeotto")
			st.start = emu.framecount()
			st.encounters = 0
			if st.go then print("refstrat RECOVERY: flier backup in the west Route 3 grass (no Route 2 Pidgey; bound "
				..lim.steps.." steps / "..lim.frames.." frames, "..Inventory.count("pokeball").." balls)") end
		end
		if not st.go then return true end
		-- review 1 #2: the frame bound applies before any battle / text handling (a long battle cannot bypass it)
		if emu.framecount() - st.start >= lim.frames + 3000 and not Pokemon.inParty("pidgey", "spearow", "pidgeotto") then
			print("refstrat RECOVERY FAILED: flier backup exhausted - frame bound "..lim.frames.." (+3000 grace for a running battle) reached")
			return Strategies.reset("error", "Flier backup exhausted (frame bound reached)", nil, true)
		end
		if Battle.isActive() then
			if not st.inBattle then
				st.inBattle = true
				st.encounters = st.encounters + 1
			end
			Battle.handleWild()
			return false
		end
		st.inBattle = false
		if not Textbox.handle() then return false end
		local steps, frames = st.steps or 0, emu.framecount() - st.start
		if Pokemon.inParty("pidgey", "spearow", "pidgeotto") then
			local bird = Pokemon.inParty("spearow") and "spearow" or (Pokemon.inParty("pidgey") and "pidgey" or "pidgeotto")
			print("refstrat flier backup: done (flier "..bird..", steps "..steps..", frames "..frames..", encounters "..st.encounters..", balls left "..Inventory.count("pokeball")..")")
			return true
		end
		local why = Inventory.count("pokeball") == 0 and "no Poke Balls left"
			or (steps >= lim.steps and ("step bound "..lim.steps.." reached"))
			or (frames >= lim.frames and ("frame bound "..lim.frames.." reached"))
		if why then
			print("refstrat RECOVERY FAILED: flier backup exhausted - "..why.." (steps "..steps..", frames "..frames
				..", encounters "..st.encounters..", balls "..Inventory.count("pokeball")..")")
			return Strategies.reset("error", "Flier backup exhausted ("..why..")", nil, true)
		end
		local px, py = Player.position()
		if py ~= 12 or (px ~= 25 and px ~= 26) then
			if px ~= 25 then Walk.step(25, py) else Walk.step(25, 12) end
			return false
		end
		local tx = px == 25 and 26 or 25
		if st.last ~= px then st.steps = (st.steps or 0) + 1; st.last = px end
		Walk.step(tx, 12)
		return false
	end
	-- v8 RECOVERY (not in the reference): Squirtle must enter the Weedle fight with >= 215 EXP (the Weedle's 99 completes L8
	-- = 314 for Bubble at Brock; reference 217 from its Route 1 Pidgey, EARLY_ROUTE 2.1). With the reference forest there
	-- are no wild fights, and on some seeds Route 1 offers none (v2: 3 seeds left Viridian at 202 EXP and reset at Brock).
	-- Before the Nidoran save the bot then fights in the Route 22 grass (33,11)/(32,11) until 215 and comes back; nothing
	-- is caught here. Pre-save, so the post-reset chain is unaffected.
	S.refSquirtleExpIf = function()
		local st = Strategies.status
		if st.go == nil then
			local exp = Pokemon.getExp()
			st.go = Pokemon.info("squirtle", "level") < 8 and exp < 215
			print(st.go and ("refstrat RECOVERY: Route 22 EXP detour before the Nidoran save (Squirtle EXP "..exp..")")
				or ("refstrat: no EXP detour (Squirtle EXP "..exp..")"))
			if st.go then
				setControlLocal("shouldCatch", nil)
				setControlLocal("minExp", 215)
				setControlLocal("shouldFight", {{name="rattata"}, {name="spearow"}, {name="nidoran"}, {name="nidoranf"}})
			end
		end
		if not st.go then return true end
		if Battle.isActive() then
			Battle.handleWild()
			return false
		end
		if not Textbox.handle() then return false end
		local map = Memory.value("game", "map")
		local px, py = Player.position()
		if map == 1 then
			if not st.trained then
				if walkPoints(st, "out1", {{15,20}, {15,17}, {0,17}}) then Walk.step(-1, 17) end
				return false
			end
			return walkPoints(st, "back1", {{15,17}, {15,20}})
		elseif map == 33 then
			if not st.trained then
				if not walkPoints(st, "out22", {{35,9}, {35,12}, {33,12}, {33,11}}) then return false end
				if Pokemon.getExp() >= 215 or Pokemon.info("squirtle", "level") >= 8 or (st.steps or 0) >= 80 then
					st.trained = true
					print("refstrat EXP detour: done (Squirtle EXP "..Pokemon.getExp()..", steps "..(st.steps or 0)..")")
					return false
				end
				local tx = px == 33 and 32 or 33
				if st.last ~= px then st.steps = (st.steps or 0) + 1; st.last = px end
				Walk.step(tx, 11)
				return false
			end
			if walkPoints(st, "back22", {{33,12}, {35,12}, {35,9}}) then Walk.step(40, 9) end
			return false
		end
		return false
	end
	-- v8 RECOVERY (v2-v7 behaviour, not in the reference): the Viridian tree Potion, taken before the Nidoran save (so the

	-- v4.2: back on the route as a CONDITIONAL fallback (v4.1 removed it with the Swimmer fix; held-out H3 then lost 7
	-- seeds to "No Pokemon able to learn cut" — no Paras, no balls for the Oddish fallback — and 5 to Route 6 /
	-- Vermilion fights with 0-1 Potions). Now money-capped (balls first, then Potions).
	S.refMaybeMart = function(data)
		local st = Strategies.status
		if st.need == nil then
			-- also Poke Balls (up to 3) while there is no Cut learner: the Route 6 Oddish fallback otherwise runs out
			-- (1720000008 threw both balls at Oddish; 1720000209 had none left after Mt. Moon)
			st.balls = not Pokemon.inParty("paras", "oddish") and Inventory.count("pokeball") < 3
			st.need = Inventory.count("potion") < (data.min or 3) or st.balls   -- v19 edit E2: min = 0 (Ball sub-branch only)
			print("refstrat Cerulean Mart check: potions "..Inventory.count("potion").." balls "..Inventory.count("pokeball").." -> "..(st.need and "buy" or "skip"))
			-- v19: shopping recovery RB2 (trigger: Potions < floor, or no Cut learner and Balls < 3)
			print(string.format("refstrat SHOP RB2 Cerulean check: Potions %d (floor %d), Poke Balls %d, Cut learner %s, money %d -> %s",
				Inventory.count("potion"), data.min or 3, Inventory.count("pokeball"), Pokemon.inParty("paras", "oddish") and "yes" or "no", REFSTRAT_MONEY(),
				st.need and "RECOVERY: buy" or "no purchase (reference branch)"))
		end
		if not st.need then return true end
		if not Battle.handleWild() then return false end
		local map = Memory.value("game", "map")
		-- the clerk's dialogue is a textbox handled by Shop.transaction: no text gate inside the Mart before buying
		-- v6 fix: after the purchase only B is pressed until the shop menus/text are closed. Textbox.handle ->
		-- Input.cancel alternates A and B, which re-opened BUY from "anything else?" forever (d1 seed 1776300008:
		-- balls + potions bought, then 7,200 s IGT stall in the Cerulean Mart; FINDINGS F12).
		if map == 67 and st.bought and (Textbox.isActive() or Menu.isOpened())
			and emu.framecount() - (st.closing or emu.framecount()) < 300 then   -- cap: stale textbox flag (F8)
			if not st.closing then st.closing = emu.framecount(); print("refstrat Cerulean Mart: closing shop menus with B") end
			Input.press("B")
			return false
		end
		if not (map == 67 and not st.bought) and not Textbox.handle() then return false end
		if map == 3 then
			if not st.bought then
				walkPoints(st, "to", {{19,23}, {17,23}, {17,26}, {25,26}, {25,25}})
			elseif walkPoints(st, "back", {{25,26}, {17,26}, {17,23}, {19,23}, {19,18}}) then
				return true
			end
		elseif map == 67 then
			if not st.bought then
				if walkPoints(st, "inMart", {{3,5}, {2,5}}) then
					local function bcd(b) return math.floor(b / 16) * 10 + b % 16 end
					local cash = bcd(Memory.raw(0x1347)) * 10000 + bcd(Memory.raw(0x1348)) * 100 + bcd(Memory.raw(0x1349))
					local balls = st.balls and math.min(3 - Inventory.count("pokeball"), math.floor(cash / 200)) or 0
					cash = cash - balls * 200
					local potions = math.min(math.max(0, (data.min or 3) - Inventory.count("potion")), math.floor(cash / 300))
					local buy = {}
					if potions > 0 then buy[#buy + 1] = {name = "potion", index = 1, amount = Inventory.count("potion") + potions} end
					if balls > 0 then buy[#buy + 1] = {name = "pokeball", index = 0, amount = Inventory.count("pokeball") + balls} end
					if #buy == 0 then st.bought = true end
					if #buy > 0 and not st.rb2logged then
						st.rb2logged = true
						print(string.format("refstrat SHOP RECOVERY RB2 Cerulean: buy POTION x%d, POKE_BALL x%d (money %d)", potions, balls, REFSTRAT_MONEY()))
					end
					if #buy > 0 and Shop.transaction {buy = buy} then
						st.bought = true
						print("refstrat Cerulean Mart: potions now "..Inventory.count("potion"))
					end
				end
			else
				walkPoints(st, "outMart", {{2,6}, {3,6}, {3,8}})
			end
		end
		return false
	end


	-- v3 Celadon purchases (money-capped refShopBuffs, refShopRepels) are replaced by the v4 plan at the end.
	REFSTRAT_MONEY = function()
		local function bcd(b) return math.floor(b / 16) * 10 + b % 16 end
		return bcd(Memory.raw(0x1347)) * 10000 + bcd(Memory.raw(0x1348)) * 100 + bcd(Memory.raw(0x1349))
	end
	local money = REFSTRAT_MONEY
	-- v8: 5 Poke Balls (reference 3, 5:36). Deviation for the fallback: when the timed Nidoran catch fails (1 ball used)
	-- the free-mode catch ran out of balls in 3 of 4 v8 section runs (seeds 1797000023/27/29, "Ran out of Pokeballs").
	-- v19 edit A (S1, reference 5:36-5:43): exactly 3 Poke Balls (purchase quantity). The v8 spare Balls are removed:
	-- 0 of 48 frozen-v18 Pewter arrivals had used a third Ball (search/diag_v18_shops.txt); a failed catch is handled by
	-- RB1 (Pewter) / RB2 (Cerulean) recovery purchases.
	S.refShopViridian = function()
		local st = Strategies.status
		if st.ballTarget == nil then
			st.ballTarget = Inventory.count("pokeball") + 3
			print(string.format("refstrat SHOP S1 Viridian: reference list POKE_BALL x3 (bag %d -> %d), money %d", Inventory.count("pokeball"), st.ballTarget, REFSTRAT_MONEY()))
		end
		return Shop.transaction {buy = {{name = "pokeball", index = 0, amount = st.ballTarget}}}
	end


	---------------------------------------------------------------------------------------------
	-- v4 resource plan (experiments/refstrat-v4-2026-10-11/FINDINGS.md section 2).
	---------------------------------------------------------------------------------------------

	-- PP reads: fixed in the candidate's private engine copy (v5, engine/ENGINE_CHANGES.md #1: Battle.pp/movePP,
	-- Combat.getMoves, Pokemon.pp all PP-Up-masked and party-based outside battle); the v4 overlay copy was removed.

	-- Item ids the inherited Inventory table lacks (PP Up 79), so Inventory.count/use work for them.
	do
		local i = 1
		while true do
			local name, value = debug.getupvalue(Inventory.indexOf, i)
			if not name then break end
			if name == "items" then value.pp_up = 79; value.max_elixer = 83; break end
			i = i + 1
		end
	end

	-- Hidden item pickup the reference made (Route 10 Max Ether 49:53, Route 17 PP Up 1:09:00; coordinates from the
	-- pokered hidden-object table). Stand on (x,y), face dir, press A; done when the bag count rises. Conditional:
	-- skipped with a full bag, abandoned after 10 s (logged), so it can never stall the route.
	-- {s="refHidden", item="max_ether", x=15, y=53, dir="Right"}; slope=true on the Cycling Road (forced downhill).
	S.refHidden = function(data)
		local st = Strategies.status
		if st.start == nil then
			st.start, st.tries = Inventory.count(data.item), 0
			if Inventory.isFull() and st.start == 0 then
				print("refstrat hidden "..data.item..": bag full, skipped")
				st.give = true
			end
		end
		if st.give then return true end
		if Inventory.count(data.item) > st.start then
			if Textbox.isActive() then Input.cancel() return false end
			print("refstrat hidden "..data.item..": picked up after "..st.tries.." frames")
			return true
		end
		st.tries = st.tries + 1
		if st.tries > 600 then
			print("refstrat hidden "..data.item..": NOT found (gave up)")
			return true
		end
		if Textbox.isActive() then Input.press("A", 2) return false end
		local px, py = Player.position()
		if data.slope then
			if px ~= data.x then Walk.step(data.x, py)
			elseif py < data.y then return false
			elseif py == data.y then Player.interact(data.dir)
			else Input.press("Up") end
		elseif px ~= data.x or py ~= data.y then
			Walk.step(data.x, data.y)
		else
			Player.interact(data.dir)
		end
		return false
	end

	-- Keep one bag slot free before a gift/hidden item (20-slot bag): with the Route 10 Max Ether the bag was full at
	-- the Fly house on 2/6 r1 seeds (HM02 refused -> reset). Tosses items this route no longer needs; the reference
	-- carried none of them at that point (no Antidote/Balls; Parlyz Heals unused to the end).
	S.refFreeSlot = function(data)
		if Strategies.initialize("refChecked") then
			Strategies.status.refSkip = Inventory.count() < 20
			if not Strategies.status.refSkip then print("refstrat bag full before "..tostring(Control.areaName)..": tossing") end
		end
		if Strategies.status.refSkip then return true end
		-- v7: close the item menu after the toss (t4/t9 Route 16 stalls: the open item menu + the inherited A/B text
		-- handler re-opened items forever once the bag was full there, which the reference Silph order now causes)
		if Strategies.status.refTossed or Strategies.tossItem("antidote", "pokeball", "tm34", "paralyze_heal") then
			Strategies.status.refTossed = true
			return Menu.close()
		end
		return false
	end

	-- Super Potion reserve (reference: the 3 Celadon Super Potions were all still in the bag at the Elite Four, used
	-- before Agatha and Lance, 1:36:54 / 1:38:46). Outside the League, overworld potion steps may only use Super
	-- Potions above the reserve; they fall back to Potions (or skip, as the inherited step does when nothing fits).
	local LEAGUE = {[174] = true, [245] = true, [246] = true, [247] = true, [113] = true, [120] = true, [118] = true}
	local SUPER_RESERVE = ROUTE22_REPEL and 1 or 2   -- v79: restore one field Super Potion; off = v78 reserve
	local enginePotion = Strategies.functions.potion
	-- v16 healing policy log (HEALING_TABLE.md): every route potion step logs its decision once - map, tile, HP, the
	-- step's target and whether it is a reference heal point (REF_HEAL) or a recovery branch. Reference branch at
	-- non-reference points = no heal; the inherited step heals only below its survival target for the next uncontrolled
	-- damage (state trigger: HP < target), logged as RECOVERY with the items it consumed.
	local REF_HEAL = {[61] = "row10 Potions after the Paras", [88] = "row15 Bill's Potions", [247] = "row28 Agatha",
		[113] = "row29-30 Lance / Champion"}
	local function potionLogged(data, inner)
		local st = Strategies.status
		local map = Memory.value("game", "map")
		if st.healLog == nil then
			local hp, mx = Combat.hp(), Combat.maxHP()
			local toHP = (Control.yolo and data.yolo ~= nil) and data.yolo or data.hp
			if type(toHP) == "string" then toHP = Combat.healthFor(toHP) end
			toHP = math.min(toHP or 0, mx)
			local px, py = Player.position()
			st.healLog = {hp = hp, target = toHP, items = Inventory.count("potion") + Inventory.count("super_potion") + Inventory.count("full_restore")}
			local refRow = REFSTRAT_REF_HEAL_ROW or REF_HEAL[map]
			-- edit O: step identity, also printed on the ITEMUSE lines of this step's item uses
			st.stepId = string.format("%d:%d,%d:%d", map, px, py, emu.framecount())
			REFSTRAT_STEP = {id = st.stepId, route = REFSTRAT_CUR_DATA}
			print(string.format("refstrat HEAL step map %d (%d,%d): hp %d/%d target %d -> %s%s step=%s", map, px, py, hp, mx, toHP,
				hp < toHP and "heal" or "no heal", refRow and (" [reference point "..refRow.."]")
				or (hp < toHP and " [RECOVERY: HP below the step's survival target]" or " [reference branch]"), st.stepId))
		end
		local r = inner(data)
		if r and not st.healDone then
			st.healDone = true
			local used = st.healLog.items - (Inventory.count("potion") + Inventory.count("super_potion") + Inventory.count("full_restore"))
			if used > 0 then print("refstrat HEAL result map "..map..": hp "..st.healLog.hp.." -> "..Combat.hp()..", healing items used "..used.." step="..tostring(st.stepId))
			-- v18 cycle 2 (edit K): a heal decision that used nothing says so (no allowed item: none in the bag, or only
			-- Super Potions at the League reserve outside the League)
			elseif st.healLog.hp < st.healLog.target and Combat.hp() == st.healLog.hp then
				print("refstrat HEAL result map "..map..": hp "..st.healLog.hp..", no healing item used (Potions "..Inventory.count("potion")
					..", Super Potions "..Inventory.count("super_potion").." with reserve "..SUPER_RESERVE.." outside the League) step="..tostring(st.stepId))
			end
		end
		return r
	end
	S.potion = function(data)
		if REFSTRAT_RED_WINDOW then return true end   -- v35 RED_LATE: no Potion steps in the red-HP window
		local f = LEAGUE[Memory.value("game", "map")] and HEAL_SCALE_LEAGUE or HEAL_SCALE   -- v36 risk dial
		if f and data and not data.refScaled then
			local d = {}
			for k, v in pairs(data) do d[k] = v end
			for _, k in ipairs({"hp", "yolo"}) do
				local v = d[k]
				if type(v) == "string" then v = Combat.healthFor(v) end
				if type(v) == "number" and v < 999 then d[k] = math.floor(v * f) elseif v ~= nil then d[k] = v end
			end
			d.refScaled = true
			data = d
		end
		if LEAGUE[Memory.value("game", "map")] or Inventory.count("super_potion") > SUPER_RESERVE then
			return potionLogged(data, enginePotion)
		end
		local contains = Inventory.contains
		Inventory.contains = function(...)
			local args = {}
			for _, v in ipairs({...}) do if v ~= "super_potion" then args[#args + 1] = v end end
			return contains((table.unpack or unpack)(args))
		end
		local ok, r = pcall(potionLogged, data, enginePotion)
		Inventory.contains = contains
		if not ok then error(r) end
		return r
	end

	-- BEGIN_PURE_LAVENDER_FLOOR
	-- v52 LAVENDER_FLOOR: Tower 2F rival Pidgeotto (pokered parties.asm Rival2Data: L25; base Attack 60, trainer Attack DV 9 ->
	-- Attack 39; L25 moves Gust/Sand-Attack/Quick Attack/Whirlwind, Gust and Quick Attack are 40-power Normal, STAB, x1 vs
	-- Nidoking; Quick Attack moves first). Max non-critical hit against party Defense `def` (no Thunderbadge boost =
	-- conservative): ((2*25/5+2) * 39 * 40 / def) / 50 + 2, then STAB +1/2.
	REFSTRAT_PIDGEOTTO_MAXHIT = function(def)
		local floor = math.floor
		local a = 39
		if def > 255 then a, def = floor(a / 4), floor(def / 4) end   -- pokered: a stat > 255 scales both by 1/4
		def = math.max(1, def)
		local x = math.min(997, floor(floor(12 * a * 40 / def) / 50)) + 2
		return x + floor(x / 2)
	end
	REFSTRAT_LAVENDER_TARGET = function(stepHP, def, hasPotion, hits)
		if not hasPotion then return stepHP end
		return math.max(stepHP, REFSTRAT_PIDGEOTTO_MAXHIT(def) * (hits or 1) + 1)
	end
	-- END_PURE_LAVENDER_FLOOR
	local v51Potion = S.potion
	S.potion = function(data)
		if LAVENDER_FLOOR and data and data.refLavenderFloor then
			local st = Strategies.status
			if st.lavFloor == nil then
				local def = Memory.raw(0x116B + 38) * 256 + Memory.raw(0x116B + 39)   -- lead (slot 0) party Defense
				local hits = type(LAVENDER_FLOOR) == "number" and LAVENDER_FLOOR or 1
				st.lavFloor = REFSTRAT_LAVENDER_TARGET(data.hp, def, Inventory.contains("potion") ~= nil, hits)
				print("refstrat LAVENDER_FLOOR: Defense " .. def .. ", Pidgeotto max hit " .. REFSTRAT_PIDGEOTTO_MAXHIT(def) .. " x" .. hits
					.. ", Potions " .. Inventory.count("potion") .. " -> target " .. data.hp .. " -> " .. st.lavFloor .. " (hp " .. Combat.hp() .. ")")
			end
			if st.lavFloor ~= data.hp then
				local d = {}
				for k, v in pairs(data) do d[k] = v end
				d.hp = st.lavFloor
				data = d
			end
		end
		return v51Potion(data)
	end

	-- Surge's trash cans (reference 41:41-42:11: SAVE outside the gym after the cut tree, reset, CONTINUE, first can,
	-- second can; commentary: "can manip ... with IGT tracking 100%"). v5 replaces the inherited hidden read of the
	-- lock indices (trash-direct-v100) with the save/reset manip: the route's manipSave at Vermilion (12,20) uses the
	-- boot schedule first=50/period=12, after which Vermilion City's map load rolls first lock = can 0 (top-left, (1,7))
	-- and opening it rolls second lock = can 0 again (the Gen 1 second-lock quirk). Offline (tools/surge_sens*.py,
	-- research-only reads): 360/360 clock phases x seconds on two seeds' saves for the first lock, 60/60 for the
	-- second. The bot reads NO lock index: it walks to (2,7), faces left, presses A, and checks the visible lock
	-- progress (the "1st/2nd electric lock opened" messages = engine progress flag). Fallback, only if a press does
	-- not open its lock: the engine's original visible can-by-can search (ai/red/strategies.lua trashcans).
	local SURGE_PATH = {{4,16}, {5,16}, {5,12}, {4,12}, {4,6}, {2,6}, {2,7}}
	S.refSurgeCans = function()
		local st = Strategies.status
		local progress = Memory.value("progress", "trashcans")
		if st.fallback then
			if progress == 3 then
				if Textbox.isActive() then Input.cancel() return false end
				return Strategies.completeCans()
			end
			if progress == 0 and st.back then
				if Textbox.isActive() then Input.cancel() return false end   -- only during the walk back; the engine
				-- search must see its own text boxes (it counts a try and advances its path on them)
				-- the engine's search starts at (2,11); the straight line down from (2,7) is blocked by cans (sv/d1
				-- 1740000001 stalled there), so first walk around: (2,6) (4,6) (4,12) (2,12) (2,11)
				local px, py = Player.position()
				while st.back[1] and px == st.back[1][1] and py == st.back[1][2] do table.remove(st.back, 1) end
				local wp = st.back[1]
				if wp then
					if px ~= wp[1] then Walk.step(wp[1], py) else Walk.step(px, wp[2]) end
					return false
				end
				st.back = nil
				Strategies.status.direction, Strategies.status.canProgress = nil, false
			end
			return Strategies.functions.trashcans()
		end
		local function fallback(why)
			print("refstrat Surge cans: "..why.." -> engine visible search")
			st.fallback = true
			Strategies.status.tries = Strategies.status.tries or 0
			-- the engine's search expects to have found lock 1 itself; it then checks the can opposite the facing
			if progress == 2 then Strategies.status.direction = "Left" end
			st.back = {{2, 6}, {4, 6}, {4, 12}, {2, 12}, {2, 11}}
			return false
		end
		if Textbox.isActive() then
			if st.pressing then st.pressing, st.sawText = false, true end   -- this press registered
			Input.cancel()
			return false
		end
		if progress == 3 then
			if not st.reported then
				st.reported = true
				print("refstrat Surge cans: both locks opened at can 0 ("..(st.presses or 0).." presses)")
			end
			return Strategies.completeCans()
		end
		if st.sawText then
			-- a press's text box appeared and was cleared: did its lock open?
			st.sawText = false
			if progress ~= (st.presses == 1 and 2 or 3) then
				return fallback("manip missed after press "..st.presses.." (progress "..progress..")")
			end
		end
		local px, py = Player.position()
		st.i = st.i or 1
		while SURGE_PATH[st.i] and px == SURGE_PATH[st.i][1] and py == SURGE_PATH[st.i][2] do st.i = st.i + 1 end
		local wp = SURGE_PATH[st.i]
		if wp then
			if px ~= wp[1] then Walk.step(wp[1], py) else Walk.step(px, wp[2]) end
			return false
		end
		if not st.pressing then
			local expected = (st.presses or 0) == 0 and 0 or 2
			if progress ~= expected then return fallback("unexpected lock progress "..progress) end
			if (st.presses or 0) >= 2 then return fallback("two presses without both locks") end
			st.pressing, st.pressFrame = true, emu.framecount()
			st.presses = (st.presses or 0) + 1
		end
		-- keep facing left and pressing A until this press's text box appears (the engine drops repeated presses)
		if emu.framecount() - st.pressFrame > 600 then return fallback("no text after press "..st.presses) end
		Player.interact("Left")
		return false
	end

	-- v9: after the 'surge' chain (lua/chain.lua: SAVE at Vermilion (12,20), power cycle, can 8 then can 5 as the
	-- reference). The bot reads no lock index: it checks the visible outcome (the lock messages = engine progress flag).
	-- Both opened -> the inherited completion walk. Otherwise logged RECOVERY: if only the first lock is open, one visible
	-- retry of the reference's second can 5 from (3,12); then the v5 fallback (engine visible can-by-can search from
	-- (2,11)).
	S.refSurgeVerify = function()
		local st = Strategies.status
		st.tries = st.tries or 0
		if st.fallback then return S.refSurgeCans() end
		if Textbox.isActive() then
			if st.retry == "pressing" then st.retry = "pressed" end
			Input.cancel()
			return false
		end
		local progress = Memory.value("progress", "trashcans")
		local c = REFSTRAT_CHAIN
		if progress == 3 then
			if not st.reported then
				st.reported = true
				if st.retry then
					print("refstrat RECOVERY Surge cans: second lock opened by the visible retry of can 5")
				else
					print("refstrat Surge cans: both locks opened, cans 8 then 5 ("..((c and c.ok) and "timed chain intact" or "after RECOVERY")..")")
				end
			end
			return Strategies.completeCans()
		end
		local function toFallback(why)
			-- review 1 #1: the v5 fallback is only valid from lock progress 0 (its direction hack assumed can 0's first
			-- lock); with the first lock still open after the retry, end the attempt explicitly instead of stalling
			if Memory.value("progress", "trashcans") == 2 then
				print("refstrat RECOVERY FAILED Surge cans: "..why.." with the first lock still open")
				return Strategies.reset("error", "Surge cans: second lock not reachable", nil, true)
			end
			print("refstrat RECOVERY Surge cans: "..why.." -> engine visible search")
			st.fallback = true
			st.back = {{2, 12}, {2, 11}}
			local px, py = Player.position()
			if px ~= 3 or py ~= 12 then st.back = {{px, 12}, {2, 12}, {2, 11}} end
			return false
		end
		if st.retry == "pressed" then
			return toFallback("retry of can 5 did not open the second lock (progress "..progress..")")
		end
		if progress == 2 and not st.retry then
			print("refstrat RECOVERY Surge cans: first lock open, second not - one visible retry of can 5")
			st.retry, st.pressFrame = "walking", emu.framecount()
		end
		if st.retry == "walking" or st.retry == "pressing" then
			local px, py = Player.position()
			if px ~= 3 or py ~= 12 then
				if py ~= 12 then Walk.step(px, 12) else Walk.step(3, 12) end
				return false
			end
			st.retry = "pressing"
			if emu.framecount() - st.pressFrame > 900 then return toFallback("no text on the retry of can 5") end
			Player.interact("Up")
			return false
		end
		return toFallback("chain ended with lock progress "..progress)
	end

	-- Giovanni (reference 1:26:10-1:27:35, commentary 1:35:48 "you just Earthquake everything except at the end you
	-- Blizzard"): no X item. The inherited fightGiovanni prepares an X Special whenever Nidoking is not in red HP
	-- (the reference fought in red HP, where the inherited rule would not use it either; the candidate heals more).
	-- v5: X Special is never prepared here; the inherited move choice (Earthquake, Blizzard on Rhydon) is kept.
	local engineFightGiovanni = Strategies.functions.fightGiovanni
	S.fightGiovanni = function()
		local prepare = Strategies.prepare
		Strategies.prepare = function(...)
			local only = {...}
			if #only == 1 and only[1] == "x_special" then return true end
			return prepare(...)
		end
		local ok, r = pcall(engineFightGiovanni)
		Strategies.prepare = prepare
		if not ok then error(r) end
		return r
	end

	-- Viridian gym Blackbelt (reference 1:25:29-1:25:52: X ACCURACY, Horn Drill Machoke, Blizzard Machop, Horn Drill
	-- Machoke; commentary 1:34:42 "60% to flat kill you" without it; WR guide "X Acc + HD, Blizz, HD").
	-- v5 only swapped the inherited X Special for X Accuracy when the inherited DV/PP rule wanted an item (2 of 14
	-- arrivals). v6: X Accuracy unconditionally on the first Machoke (if one is left in the bag), Horn Drill forced on
	-- each Machoke while X Accuracy is active, Nidoking is faster and HD has PP; Blizzard on Machop if it has PP;
	-- otherwise the damage model. Fallback without X Accuracy: the inherited damage model (logged). Party (pokered
	-- parties.asm): Machoke, Machop, Machoke.
	S.fightGiovanniMachoke = function()
		local st = Strategies.status
		if Strategies.trainerBattle() then
			local ehp = Memory.raw(0x0FE6) * 256 + Memory.raw(0x0FE7)
			if ehp == 0 or not Pokemon.isDeployed("nidoking") then
				Battle.automate()
				return false
			end
			if not Combat.xAccuracy() and not st.refXAccTried then
				if Inventory.contains("x_accuracy") then
					Inventory.use("x_accuracy", nil, true)
					return false
				end
				st.refXAccTried = true
				print("refstrat Blackbelt: no X Accuracy left -> damage model")
			end
			local forced
			local ours, theirs = Memory.raw(0x1029) * 256 + Memory.raw(0x102A), Memory.raw(0x0FFA) * 256 + Memory.raw(0x0FFB)
			-- internal id compared directly: the engine's pokeIDs table has no "machop", so Pokemon.isOpponent("machop")
			-- is never true (inherited defect; t1 section checks: Machop was Horn-Drilled, Blizzard PP unchanged)
			if Memory.value("battle", "opponent_id") == 0x6A then   -- MACHOP (pokered pokemon_constants.asm)
				if Battle.pp("blizzard") > 0 then forced = "blizzard" end
			elseif Combat.xAccuracy() and ours > theirs and Battle.pp("horn_drill") > 0 then
				forced = "horn_drill"
			end
			Battle.automate(forced)
		elseif st.foughtTrainer then
			return true
		end
	end

	-- Indigo PC (reference 1:33:56-1:34:04): deposit everything except Nidoking and the bird; the bird is sacrificed to
	-- Lorelei's Dewgong on turn 1 (1:34:36), so Nidoking never takes the turn-1 Aurora Beam. The inherited step kept
	-- the bird only when Nidoking could not survive Dewgong and no Center was needed; r3 seed ...010 deposited it after
	-- the Center and died at 151/151 to a turn-1 critical Aurora Beam (199) while using X Accuracy (r3b trace).
	S.depositPokemon = function()
		local st = Strategies.status
		if st.toSize == nil then
			st.toSize = Pokemon.inParty("pidgey", "spearow") and 2 or 1
			print("refstrat Indigo PC: keeping "..st.toSize.." Pokemon (bird for the Lorelei sacrifice)")
		end
		if Memory.value("player", "party_size") <= st.toSize then
			return Menu.close()
		end
		if not Menu.isOpened() then
			Player.interact("Up")
		else
			local pc = Memory.value("menu", "size")
			if not Menu.canCloseMessage() and (pc == 2 or pc == 4) then
				local menuColumn = Menu.getCol()
				if menuColumn == 10 then
					Input.press("A")
				elseif menuColumn == 5 then
					local depositIndex = 1
					if st.toSize == 2 and Pokemon.indexOf("pidgey", "spearow") == 1 then depositIndex = 2 end
					Menu.select(depositIndex)
				else
					Menu.select(1)
				end
			else
				Input.press("A")
			end
		end
		return false
	end

	-- After Lance (reference 1:40:26): FULL RESTORE (27 -> 175/175) before the Champion. The inherited step healed only to
	-- about Sky Attack damage - 50 and kept the Full Restore (fT seeds ...004/...013 entered at 79/166 and 49/166).
	local enginePrepareForBlue = Strategies.functions.prepareForBlue
	S.prepareForBlue = function(data)
		local st = Strategies.status
		if st.refFull == nil then
			st.refFull = Inventory.contains("full_restore") and Combat.hp() < Combat.maxHP() and Inventory.count("full_restore") or false
			print("refstrat after Lance: hp "..Combat.hp().."/"..Combat.maxHP().." -> "..(st.refFull and "Full Restore" or "inherited heal"))
		end
		if not st.refFull then return enginePrepareForBlue(data) end
		if Inventory.count("full_restore") < st.refFull then return Menu.close() end
		if Menu.pause() then Inventory.use("full_restore") end
		return false
	end

	-- Champion (reference 1:41:01-1:42:20; WR route guide "CHAMP SPLIT": "X Acc + X Speed + HD x6 ... If Sky Attack turn 1:
	-- HD Pidgeot, X Speed Alakazam (~1/3 to live), HD x5"). v6 order: (1) X Accuracy; (2) X Speed PRE-EMPTIVELY on the
	-- first opponent, before Alakazam can act - unless Pidgeot is charging Sky Attack, then Horn Drill it first (guide);
	-- (3) X Speed again only while Nidoking is not faster; (4) Horn Drill forced whenever X Accuracy is active, Nidoking is
	-- faster (Gen 1 OHKO moves fail against a faster target) and it has PP; otherwise the inherited damage model.
	-- v5 used X Speed only once already slower, which gave Alakazam a free turn (Reflect in the mt1 trace, seed
	-- 1740000019); the damage model then chose Earthquake (79/143 through Reflect) - FINDINGS F2, engine fix #2.
	-- Stat stages survive a level-up (pokered experience.asm: CalculateModifiedStats + ApplyBadgeStatBoosts); only the
	-- stacked badge-boost reapplications are lost, so a level-up can lower speed and step (3) re-applies X Speed.
	-- Reads: battle speeds/HP (inherited Combat reads), X Accuracy flag (inherited), Sky Attack charge = bit 4 of the
	-- inherited attack_turns byte 0xD067 (the engine's own blue strategy reads that byte; the charge is announced on
	-- screen). No new hidden state.
	local function word(a) return Memory.raw(a) * 256 + Memory.raw(a + 1) end
	S.blue = function()
		local st = Strategies.status
		if Strategies.trainerBattle() then
			if st.refXS0 == nil then st.refXS0 = Inventory.count("x_speed") end
			if not Pokemon.isDeployed("nidoking") then
				Battle.automate()
				return false
			end
			if word(0x0FE6) == 0 then
				Battle.automate()
				return false
			end
			if not Combat.xAccuracy() and Inventory.contains("x_accuracy") then
				Inventory.use("x_accuracy", nil, true)
				return false
			end
			local ours, theirs = word(0x1029), word(0x0FFA)
			local canDrill = Combat.xAccuracy() and ours > theirs and Battle.pp("horn_drill") > 0
			local usedXSpeed = Inventory.count("x_speed") < st.refXS0
			if not usedXSpeed and Inventory.contains("x_speed") then
				local charging = bit.band(Memory.value("battle", "attack_turns"), 0x10) == 0x10
				if charging and canDrill then
					if not st.refSkyLogged then
						st.refSkyLogged = true
						print("refstrat Champion: Sky Attack charging, speed "..ours.." vs "..theirs.." -> Horn Drill first (guide)")
					end
					Battle.automate("horn_drill")
					return false
				end
				if not st.refPreLogged then
					st.refPreLogged = true
					print("refstrat Champion: pre-emptive X Speed, speed "..ours.." vs "..theirs)
				end
				Inventory.use("x_speed", nil, true)
				return false
			end
			if ours <= theirs and Inventory.contains("x_speed") then
				if st.speedFor ~= Memory.value("battle", "opponent_id") or st.speedAt ~= ours then
					st.speedFor, st.speedAt = Memory.value("battle", "opponent_id"), ours
					print("refstrat Champion: speed "..ours.." vs "..theirs.." -> X Speed")
				end
				Inventory.use("x_speed", nil, true)
				return false
			end
			if canDrill then
				Battle.automate("horn_drill")
			else
				if st.noDrillFor ~= Memory.value("battle", "opponent_id") then
					st.noDrillFor = Memory.value("battle", "opponent_id")
					print("refstrat Champion: no forced Horn Drill (xacc "..tostring(Combat.xAccuracy())..", speed "..ours.." vs "..theirs..", HD PP "..Battle.pp("horn_drill")..") -> damage model")
				end
				Battle.automate()
			end
		elseif st.foughtTrainer then
			return true
		end
	end

	-- v7: Route 23 recovery branches (inherited engine steps that act only when the engine predicts an Elite Four
	-- Center). The reference uses no PP item and skips the Max Ether here; any bag change these steps cause is logged
	-- as "refstrat RECOVERY" so that trigger counts can be reported separately from the reference path.
	local PP_ITEMS = {"ether", "max_ether", "elixer", "antidote", "tm34", "x_attack", "pokeball"}
	local function bagSnapshot()
		local t = {}
		for _, it in ipairs(PP_ITEMS) do t[it] = Inventory.count(it) end
		return t
	end
	for _, name in ipairs({"ether", "tossInVictoryRoad", "grabMaxEther"}) do
		local engineFn = Strategies.functions[name]
		S[name] = function(data)
			local st = Strategies.status
			if Memory.value("game", "map") ~= 34 then return engineFn(data) end   -- only the Route 23 steps are wrapped
			if not st.refBag then st.refBag = bagSnapshot(); st.refBagTotal = Inventory.count() end
			local r
			if name == "tossInVictoryRoad" then
				-- v18 cycle 1: free a slot for the spare Max Ether when the League plan needs it and the bag is full
				local ni = Pokemon.indexOf("nidoking")
				local hd = (ni and ni >= 0) and (Pokemon.pp(ni, "horn_drill") or 0) or 0
				local eth = Inventory.count("max_ether") + Inventory.count("ether")
				if st.refTossNeed == nil then
					st.refTossNeed = hd < 5 and eth < 2 and Inventory.isFull()
					print("refstrat Route 23 toss trigger: HD "..hd..", Ethers "..eth..", bag full "..tostring(Inventory.isFull()).." -> "..(st.refTossNeed and "toss for the spare Max Ether" or "no toss"))
				end
				if st.refTossNeed and Inventory.isFull() then
					local done = Strategies.tossItem("antidote", "tm34", "x_attack", "pokeball", "paralyze_heal")
					r = done or not Inventory.isFull()   -- done also when nothing tossable is left (no loop)
				else
					r = st.refTossNeed and true or engineFn(data)
				end
			elseif name == "grabMaxEther" then
				-- v18 cycle 1: also pick the Max Ether when the reference League plan needs a spare Ether (Horn Drill < 5
				-- and fewer than 2 Ethers: Bruno + Indigo top-up); the inherited check is shown a zero PP-item count
				if st.refNeed == nil then
					local ni = Pokemon.indexOf("nidoking")
					local hd = (ni and ni >= 0) and (Pokemon.pp(ni, "horn_drill") or 0) or 0
					local eth = Inventory.count("max_ether") + Inventory.count("ether")
					st.refNeed = hd < 5 and eth < 2
					print("refstrat Route 23 grabMaxEther trigger: HD "..hd..", Ethers "..eth.." -> "..(st.refNeed and "League plan needs a spare Ether" or "no League-plan need"))
				end
				if st.refNeed then
					local count = Inventory.ppRestoreCount
					Inventory.ppRestoreCount = function() return 0 end
					local ok, res = pcall(engineFn, data)
					Inventory.ppRestoreCount = count
					if not ok then error(res) end
					r = res
				else
					r = engineFn(data)
				end
			else
				r = engineFn(data)
			end
			if r then
				local now, diff = bagSnapshot(), {}
				for _, it in ipairs(PP_ITEMS) do
					if now[it] ~= st.refBag[it] then diff[#diff + 1] = it .. " " .. st.refBag[it] .. "->" .. now[it] end
				end
				if Inventory.count() < (st.refBagTotal or Inventory.count()) then diff[#diff + 1] = "tossed (bag slots " .. st.refBagTotal .. "->" .. Inventory.count() .. ")" end
				print("refstrat Route 23 " .. name .. ": " .. (#diff > 0 and ("RECOVERY acted: " .. table.concat(diff, ", ")) or "reference path (no action)"))
			end
			return r
		end
	end

	-- Elixer reserve (reference: an Elixer was still in the bag for Lance's room, 1:38:44, restoring Horn Drill for the
	-- Champion and Blizzard for Lance). Outside the League the last Elixer is kept: an inherited Elixer step then uses a
	-- (Max) Ether on its move instead, or nothing. r2: the 4th Elixer went at the Viridian exit, Lance's room had
	-- only a Max Ether (Blizzard) and the Champion fight started with 1 Horn Drill PP.
	local engineElixer = Strategies.functions.elixer
	-- v18 edit N (c2i-1805000354: the inherited Saffron-entry Earthquake Elixer took the Viridian Elixer -> Giovanni,
	-- rival and E4 with low PP, Agatha death): the reserve is the number of Elixers the reference chain still needs
	-- (11F, Koga stall, Viridian gym entrance, Lance's room): 3 in Koga's gym (before the stall), 2 before the Viridian
	-- gym, else 1. An inherited Elixer step uses an Elixer only above that reserve (logged RECOVERY); otherwise a
	-- (Max) Ether on its move or nothing (logged).
	local ELIXER_RESERVE = {[157] = 3, [18] = 2, [10] = 2, [178] = 2}
	S.elixer = function(data)
		local map = Memory.value("game", "map")
		local reserve = ELIXER_RESERVE[map] or 1
		local st = Strategies.status
		if not LEAGUE[map] and REFSTRAT_NIDO_PP(data.move) < data.min and st.refElixerLog == nil then
			st.refElixerLog = true
			print(string.format("refstrat inherited Elixer step map %d: %s PP %d < %d, Elixers %d (reference chain reserve %d) -> %s", map, data.move,
				REFSTRAT_NIDO_PP(data.move), data.min, Inventory.count("elixer"), reserve,
				Inventory.count("elixer") > reserve and "RECOVERY: Elixer (spare)" or "Max Ether/Ether on the move if held, else none (Elixers kept for the reference chain)"))
		end
		if LEAGUE[map] or Inventory.count("elixer") > reserve then
			return engineElixer(data)
		end
		if REFSTRAT_NIDO_PP(data.move) >= data.min then
			return Strategies.closeMenuFor(data)
		end
		-- v19 edits K/K2 withdrawn (K3, impl review 2 finding 7): v18's fallback everywhere, logged as PP RECOVERY
		if st.refPPRecLog == nil and (Inventory.contains("ether") or Inventory.contains("max_ether")) then
			st.refPPRecLog = true
			print(string.format("refstrat inherited Elixer step map %d: %s PP %d < %d -> PP RECOVERY: %s on the move (Ethers %d, Max Ethers %d)",
				map, data.move, REFSTRAT_NIDO_PP(data.move), data.min, Inventory.contains("max_ether") and "Max Ether" or "Ether",
				Inventory.count("ether"), Inventory.count("max_ether")))
		end
		return S.refRestorePP({moves = {{data.move, data.min}}, prefer = {"max_ether", "ether"}, chain = data.chain})
	end

	-- PP Up on a move (reference 1:10:00, Safari Center: PP Up on HORN DRILL, max PP 5 -> 6). Conditional on having it.
	S.refPPUp = function(data)
		local st = Strategies.status
		if st.start == nil then
			st.start = Inventory.count("pp_up")
			if st.start == 0 or not Pokemon.moveIndex(data.move, "nidoking") then return true end
		end
		if Inventory.count("pp_up") < st.start then
			if data.chain and not st.mf2Closing then
				-- MENU_FIX2 (experiments/target-policy-2026-10-17/menus; chain=true only via its route block). pokered:
				-- PP Up is a party-menu item -> after its text the bag list is redisplayed (StartMenu_Item); stay there
				-- for the chained TM26 step. Guard: no bag list within 240 frames -> close as before.
				st.mf2 = (st.mf2 or 0) + 1
				if Memory.value("menu", "main") == 128 and Menu.getCol() == 5 and not Menu.canCloseMessage() then
					print("refstrat PP Up used on "..data.move.." (MENU_FIX2: bag list kept open)")
					return true
				end
				if st.mf2 < 240 then
					if Menu.canCloseMessage() then Input.press("B") end
					return false
				end
				st.mf2Closing = true
				print("refstrat MENU_FIX2: no bag list 240 frames after the PP Up -> closing the menu")
			end
			if Menu.close() then
				print("refstrat PP Up used on "..data.move)
				return true
			end
			return false
		end
		if Memory.value("menu", "main") == 144 and Menu.getCol() == 5 then
			if Menu.canCloseMessage() then Input.cancel()
			else Menu.select(Pokemon.moveIndex(data.move, "nidoking"), true) end
		elseif Menu.pause() then
			Inventory.use("pp_up", "nidoking")
		end
		return false
	end

	-- MENU_FIX2: closes a menu left open by a chained step whose follower had nothing to do (placed only by MENU_FIX2
	-- route blocks; Menu.close returns true at once when no menu is open)
	S.refMf2Close = function()
		return Menu.close()
	end

	-- PP restore in the reference order (Bruno room: MAX ETHER -> Horn Drill, 1:35:37; Lance room: ELIXER, 1:38:44).
	-- {s="refRestorePP", moves={{"blizzard","max"},{"horn_drill","max"}}, prefer={"elixer","max_ether","ether"}}.
	-- v5 (bug 3): every declared requirement is planned, not only the first low move. An Elixer covers all moves; a
	-- (Max) Ether covers one move, so with several low moves and no Elixer one single-move item is used per move, in
	-- the declared priority order. A requirement that no item can cover is logged as a SHORTFALL (no silent pass).
	-- BEGIN_PURE_PP_PLAN
	REFSTRAT_PP_PLAN = function(lows, counts, prefer)
		-- lows: ordered list of move names below their requirement; counts: item -> quantity; prefer: item order
		local steps, short = {}, {}
		if #lows == 0 then return steps, short end
		local left, allowed = {}, {}
		for _, it in ipairs(prefer) do allowed[it] = true end
		for k, v in pairs(counts) do left[k] = allowed[k] and v or 0 end   -- items not listed in prefer are never used
		local function firstSingle()
			for _, it in ipairs(prefer) do
				if it ~= "elixer" and (left[it] or 0) > 0 then return it end
			end
		end
		local elixerFirst = false
		for _, it in ipairs(prefer) do
			if it == "elixer" then elixerFirst = true break end
			if (left[it] or 0) > 0 then break end
		end
		if (left.elixer or 0) > 0 and (elixerFirst or #lows > 1 and not firstSingle()) then
			steps[1] = {item = "elixer"}
			return steps, short
		end
		for i, move in ipairs(lows) do
			local it = firstSingle()
			if it then
				left[it] = left[it] - 1
				steps[#steps + 1] = {item = it, move = move}
			elseif (left.elixer or 0) > 0 then
				steps[#steps + 1] = {item = "elixer"}
				return steps, short
			else
				for j = i, #lows do short[#short + 1] = lows[j] end
				return steps, short
			end
		end
		return steps, short
	end
	-- END_PURE_PP_PLAN
	-- v6: Nidoking's current PP for a move. In battle the active battle mon (inherited Battle.pp); outside battle
	-- Nidoking's own party slot, not the lead's (the inherited Battle.pp reads party slot 0, which is wrong once the
	-- bird leads the party for Lorelei). Same party bytes the engine already reads; PP-Up bits masked.
	local function nidoPP(move)
		if Memory.value("game", "battle") > 0 then return Battle.pp(move) end
		local slot, idx = Pokemon.moveIndex(move, "nidoking"), Pokemon.indexOf("nidoking")
		if not slot or idx < 0 then return 0 end
		return Memory.raw(0x116B + idx * 0x2C + 28 + slot) % 64
	end
	REFSTRAT_NIDO_PP = nidoPP
	local BASE_PP = {horn_drill = 5, blizzard = 5, thunderbolt = 15, earthquake = 10}
	local function requiredPP(move, req)
		if req ~= "max" then return req end
		local slot = Pokemon.moveIndex(move, "nidoking")
		local ups = math.floor(Memory.raw(0x116B + Pokemon.indexOf("nidoking") * 0x2C + 28 + slot) / 64)
		local base = BASE_PP[move] or 5
		return base + math.floor(base / 5) * ups
	end
	S.refRestorePP = function(data)
		local st = Strategies.status
		if st.steps == nil then
			local lows = {}
			for _, m in ipairs(data.moves) do
				if not Pokemon.moveIndex(m[1], "nidoking") then
					-- v6 (review item 4): a declared move that Nidoking does not know is an explicit failure, not a silent
					-- pass. Supported fallback: battles that would force the move (Battle.automate(move), S.blue) see 0 PP
					-- and fall back to the inherited damage model.
					print("refstrat PP restore: FAILED requirement - Nidoking does not know " .. m[1] .. " (fallback: damage model)")
				elseif nidoPP(m[1]) < requiredPP(m[1], m[2]) then
					lows[#lows + 1] = m[1]
				end
			end
			local counts = {}
			for _, it in ipairs({"elixer", "max_ether", "ether"}) do counts[it] = Inventory.count(it) end
			local steps, short = REFSTRAT_PP_PLAN(lows, counts, data.prefer)
			st.steps, st.i = steps, 1
			local desc = {}
			for _, x in ipairs(steps) do desc[#desc + 1] = x.item .. (x.move and ("->" .. x.move) or "") end
			print("refstrat PP restore: low " .. table.concat(lows, ",") .. " -> " .. (#desc > 0 and table.concat(desc, ", ") or "none"))
			if #short > 0 then
				local miss = {}
				for _, mv in ipairs(short) do miss[#miss + 1] = mv .. " " .. nidoPP(mv) .. "/" .. requiredPP(mv, "max") end
				print("refstrat PP restore: SHORTFALL (no item left) " .. table.concat(miss, ", "))
			end
		end
		local step = st.steps[st.i]
		if not step then
			-- v6 (review item 4): post-check every declared requirement after the planned items were used.
			if not st.checked then
				st.checked = true
				local res = {}
				for _, m in ipairs(data.moves) do
					if Pokemon.moveIndex(m[1], "nidoking") then
						local have, need = nidoPP(m[1]), requiredPP(m[1], m[2])
						res[#res + 1] = m[1] .. " " .. have .. "/" .. need .. (have >= need and " ok" or " CHECK FAILED")
					else
						res[#res + 1] = m[1] .. " missing CHECK FAILED"
					end
				end
				print("refstrat PP restore check: " .. table.concat(res, ", "))
			end
			return Strategies.closeMenuFor(data)
		end
		if st.startCount == nil then st.startCount = Inventory.count(step.item) end
		if Inventory.count(step.item) < st.startCount then
			st.i, st.startCount = st.i + 1, nil
			return false
		end
		if step.item == "elixer" then
			if Menu.pause() then Inventory.use("elixer", "nidoking") end
			return false
		end
		if Memory.value("menu", "main") == 144 and Menu.getCol() == 5 then
			if Menu.canCloseMessage() then Input.cancel()
			else Menu.select(Pokemon.moveIndex(step.move, "nidoking"), true) end
		elseif Menu.pause() then
			Inventory.use(step.item, "nidoking")
		end
		return false
	end

	-- Celadon purchases (reference 51:21-52:45, money 24331 -> 31): TM07, Super Repel x9, Super Potion x3, Poke Doll,
	-- Soda Pop, Fresh Water, X Accuracy x12, X Special x3, X Speed x5. One money-capped plan, made at 2F with the money
	-- on the shop screen. Floors for this route's usage: X Special 3, X Speed 5, X Accuracy 10 (v4 r0 traces used at
	-- most 9 X Accuracy); then Super Potions up to 6 (reference 3; r2: with only 3, kept for the League, mid-game
	-- heals ran dry -> 3 deaths), then X Accuracy up to 12.
	-- v5 (bug 2): ONE money-capped plan, pure functions (tested offline by tools/shop_check.py). Order: Super Repels
	-- (up to 9 in the bag), then the 5F X-item floors (X Special 3, X Speed 5, X Accuracy 10) and Doll/Soda/Water,
	-- then Super Potions up to 6 in the bag, then X Accuracy up to 12. Nothing is ever planned beyond the money held.
	-- BEGIN_PURE_SHOP_PLAN
	-- v7 plan (reference list: HEAL_SHOP_BIRD 2.2, TM07, Super Repel x9, Super Potion x3, Poke Doll, Soda Pop, Fresh
	-- Water, X Accuracy x12, X Special x3, X Speed x5 = ₽24300 of ₽24331). The bot keeps v6's Pewter/Vermilion
	-- purchases (3 Super Potions already in the bag), so at 2F (after TM07) it buys: Super Repels to 9, X Special 3 +
	-- X Speed 5 (5F), X Accuracy up to 12, then Super Potions up to 6 in the bag - all money-capped, no minimum. With
	-- the bot's typical ₽18.7-19.4k this gives 10-11 X Accuracy (reference 12).
	REFSTRAT_CELADON_PLAN = function(cash, haveRepel, haveSuper)
		-- order: Super Repels to 9; Doll/Soda/Water; X Special 3 + X Speed 5; X Accuracy up to 12 (the reference count:
		-- 12 uses incl. the Silph Arbok Rocket, Bruno and the Champion); Super Potions up to 3 in the bag (the
		-- reference's 3), then up to 6 if money is left.
		local fixed = 1000 + 300 + 200
		local repels = math.max(0, math.min(9 - haveRepel, math.floor(cash / 500)))
		-- v18 cycle 1 (block c1a): the 9th Super Repel is required (Victory Road (24,16) stalled without it) - kept
		local rest = cash - repels * 500 - fixed - 3 * 350 - 5 * 350
		-- v18 cycle 1 (FINDINGS C1): X Accuracy to 11 (with the Arbok reserve 9 this covers the 11F X Accuracy + Horn
		-- Drill; the Arbok fight without X Accuracy cost no Super Potions), then the reference's 3 Super Potions (League
		-- heals), then the 12th X Accuracy, then Super Potions to 6
		local xacc = math.max(0, math.min(11, math.floor(rest / 950)))
		rest = rest - xacc * 950
		local supers = math.max(0, math.min(math.max(0, 3 - haveSuper), math.floor(rest / 700)))
		rest = rest - supers * 700
		if xacc == 11 and rest >= 950 then xacc = 12; rest = rest - 950 end
		supers = supers + math.max(0, math.min(math.max(0, 6 - haveSuper - supers), math.floor(rest / 700)))
		return {repels = repels, supers = supers, xacc = xacc}
	end
	-- v19 edit A: the exact reference list (S6-S10). REFSTRAT_CELADON_EXACT(cash at 2F after TM07) returns the purchase
	-- quantities. The full list after TM07 costs 22300 (SR 4500, SP 2100, Doll 1000, Soda 300, Water 200, X Acc 11400,
	-- X Special 1050, X Speed 1750); the reference had 22331. RC1 (shortfall branch, only if cash < 22300): drop in this
	-- order - the 3rd X Special (the reference's unused spare), the 5th X Speed, the 12th X Accuracy, then further X
	-- Speed / X Accuracy units; Super Repels 9, Super Potions 3, Doll, Soda and Water are never dropped.
	REFSTRAT_CELADON_EXACT = function(cash)
		local p = {repels = 9, supers = 3, xacc = 12, xspc = 3, xspd = 5, dropped = {}}
		local cost = function() return p.repels * 500 + p.supers * 700 + 1500 + p.xacc * 950 + p.xspc * 350 + p.xspd * 350 end
		local order = {{"xspc", "X_SPECIAL"}, {"xspd", "X_SPEED"}, {"xacc", "X_ACCURACY"}}
		-- v42 LEAGUE_TACTIC bit 2: the bot uses one X Special (Lance's Gyarados) and nothing else before Blue (recorded
		-- bags: Blue starts with 2 / 1 X Special), but Blue's pre-emptive X Speed is the 5th X Speed - without it 52 of 89
		-- recorded Blue arrivals died (Alakazam outspeeds). Drop the 2nd X Special before the 5th X Speed.
		if LEAGUE_TACTIC and math.floor(LEAGUE_TACTIC / 2) % 2 == 1 then
			while cost() > cash and p.xspc > 1 do
				p.xspc = p.xspc - 1
				p.dropped[#p.dropped + 1] = "X_SPECIAL"
			end
		end
		local guard = 0
		while cost() > cash and guard < 40 do
			guard = guard + 1
			local done = false
			for _, o in ipairs(order) do
				local floor = (o[1] == "xspc") and 2 or 0
				if p[o[1]] > floor and cost() > cash then
					p[o[1]] = p[o[1]] - 1
					p.dropped[#p.dropped + 1] = o[2]
					done = true
				end
			end
			if not done then break end
		end
		p.exact = #p.dropped == 0
		p.affordable = cost() <= cash
		if not p.affordable then
			-- v19 edit J2: uncovered deficit (terminal): Doll / Soda / Water first (1500), then Super Repels, then
			-- Super Potions from the remainder; no X items
			p.terminal = true
			p.xacc, p.xspc, p.xspd = 0, 0, 0
			local avail = math.max(0, cash - 1500)
			p.repels = math.min(9, math.floor(avail / 500)); avail = avail - p.repels * 500
			p.supers = math.min(3, math.floor(avail / 700))
			p.dropped[#p.dropped + 1] = "TERMINAL"
			p.prereq = cash >= 1500   -- v19 edit P: false = Doll + Soda + Water cannot be paid (run ends at the 2F decision)
		end
		return p
	end
	REFSTRAT_X_PLAN = function(cash, xaccCap)
		local acc = math.max(0, math.min(xaccCap or 12, math.floor((cash - 3 * 350 - 5 * 350) / 950)))
		cash = cash - acc * 950
		local spc = math.max(0, math.min(3, math.floor(cash / 350))); cash = cash - spc * 350
		local spd = math.max(0, math.min(5, math.floor(cash / 350)))
		return {spc = spc, spd = spd, acc = acc}
	end
	-- END_PURE_SHOP_PLAN

	-- Shop watchdog (bug 2): a purchase that makes no progress (e.g. "You don't have enough money") would repeat
	-- forever; after 1500 frames without a bag change the step gives up, logs it, and closes the menu.
	local function guardedTransaction(st, options, label)
		local key = Inventory.count() .. ":" .. money()
		if st.guardKey ~= key then st.guardKey, st.guardFrame = key, emu.framecount() end
		if st.gaveUp or emu.framecount() - st.guardFrame > 1500 then
			if not st.gaveUp then print("refstrat shop "..label..": no progress for 1500 frames -> gave up") end
			st.gaveUp = true
			return Menu.close()
		end
		return Shop.transaction(options)
	end


	-- BEGIN_PURE_SHORTFALL
	-- v19 edit J3 + P: a Celadon prerequisite (TM07, Poke Doll, Soda Pop, Fresh Water) the money cannot pay is an
	-- unrepairable shortfall: logged, then the run ends (recorded gameplay failure) before the segment that needs it.
	REFSTRAT_SHORTFALL_TERMINAL = function(item, cash, price)
		print(string.format("refstrat SHOP SHORTFALL TERMINAL %s: money %d < %d -> unrepairable shortfall, run ended before its dependent segment", item, cash, price))
		return Strategies.hardReset("shortfall", "Unrepairable shopping shortfall: "..item)
	end
	REFSTRAT_SHOP_UNPAYABLE = function(item, price)
		local cash = REFSTRAT_MONEY()
		if Inventory.contains(item) or cash >= price then return false end
		print(string.format("refstrat SHOP SHORTFALL RC1-UNPAYABLE %s: money %d < %d -> not bought (unrepairable shortfall)", item, cash, price))
		REFSTRAT_SHORTFALL_TERMINAL(item, cash, price)
		return true
	end
	REFSTRAT_TM07_UNPAYABLE = function()
		local cash = REFSTRAT_MONEY()
		if Inventory.contains("horn_drill") or cash >= 2000 then return false end
		print("refstrat SHOP SHORTFALL RC1-TM07 Celadon 2F: money "..cash.." < 2000 -> TM07 not bought")
		REFSTRAT_SHORTFALL_TERMINAL("tm07", cash, 2000)
		return true
	end
	-- END_PURE_SHORTFALL
	local enginePokeDoll = Strategies.functions.shopPokeDoll
	S.shopPokeDoll = function(data)
		if REFSTRAT_SHOP_UNPAYABLE("pokedoll", 1000) then return true end
		return enginePokeDoll(data)
	end
	local engineExtraWater = Strategies.functions.shopExtraWater
	S.shopExtraWater = function(data)
		if REFSTRAT_SHOP_UNPAYABLE("fresh_water", 200) then return true end
		return engineExtraWater(data)
	end
	-- v19 edit L: a pickup the reference skips (logged, no interaction)
	S.refSkipPickup = function(data)
		local px, py = Player.position()
		print(string.format("refstrat pickup skipped at map %d (%d,%d): %s", Memory.value("game", "map"), px, py, tostring(data.why)))
		return true
	end
	-- v19 edit J2: TM07 with less than 2000 on the 2F is not bought (logged RC1-TM07; unreachable on the reference money
	-- path); otherwise the inherited shopTM07
	local engineShopTM07 = Strategies.functions.shopTM07
	S.shopTM07 = function(data)
		local st = Strategies.status
		if st.tmChecked == nil then
			st.tmChecked = true
			st.skip = REFSTRAT_TM07_UNPAYABLE()   -- v19 edit P: terminal (logged, run ended)
		end
		if st.skip then return true end
		return engineShopTM07(data)
	end
	S.refShopRepels = function()
		local st = Strategies.status
		if not st.plan then
			-- v19 edit A (S6): exact purchase quantities SUPER_REPEL x9 then SUPER_POTION x3; the whole Celadon list is
			-- planned here from the money after TM07 (RC1 only on a shortfall)
			local p = REFSTRAT_CELADON_EXACT(money())
			if p.prereq == false then
				print(string.format("refstrat SHOP SHORTFALL RC1 Celadon: money %d < 22300 -> drop %s; prerequisites Doll + Soda + Water 1500 unpayable", money(), table.concat(p.dropped, ",")))
				return REFSTRAT_SHORTFALL_TERMINAL("prerequisites", money(), 1500)
			end
			REFSTRAT_CELADON = {xacc = p.xacc, xspc = p.xspc, xspd = p.xspd, exact = p.exact}
			st.plan = {repels = Inventory.count("super_repel") + p.repels, supers = Inventory.count("super_potion") + p.supers}
			if p.exact then
				print(string.format("refstrat SHOP S6 Celadon 2F: reference list SUPER_REPEL x9 (bag -> %d), SUPER_POTION x3 (bag -> %d); planned 5F X_ACCURACY x12, X_SPECIAL x3, X_SPEED x5; money %d",
					st.plan.repels, st.plan.supers, money()))
			else
				print(string.format("refstrat SHOP SHORTFALL RC1 Celadon: money %d < 22300 -> drop %s; SUPER_REPEL x%d, SUPER_POTION x%d, 5F X_ACCURACY x%d, X_SPECIAL x%d, X_SPEED x%d%s",
					money(), table.concat(p.dropped, ","), p.repels, p.supers, p.xacc, p.xspc, p.xspd,
					p.terminal and " (uncovered deficit: protected list capped by money)" or ""))
			end
		end
		local buy = {}
		if st.plan.repels > Inventory.count("super_repel") then buy[#buy + 1] = {name = "super_repel", index = 3, amount = st.plan.repels} end
		if st.plan.supers > Inventory.count("super_potion") then buy[#buy + 1] = {name = "super_potion", index = 1, amount = st.plan.supers} end
		return guardedTransaction(st, {direction = "Up", buy = buy}, "Celadon 2F")
	end
	S.refShopBuffs = function()
		local st = Strategies.status
		if not st.plan then
			-- v19 edit A (S10): X ACCURACY, then X SPECIAL, then X SPEED (reference order), quantities from the 2F plan
			local c = REFSTRAT_CELADON or REFSTRAT_CELADON_EXACT(money() + 4500 + 2100 + 1500)
			st.plan = {acc = Inventory.count("x_accuracy") + c.xacc, spc = Inventory.count("x_special") + c.xspc,
				spd = Inventory.count("x_speed") + c.xspd}
			print(string.format("refstrat SHOP S10 Celadon 5F: %s X_ACCURACY x%d, X_SPECIAL x%d, X_SPEED x%d; money %d",
				(c.exact and "reference list") or "SHORTFALL RC1 list", c.xacc, c.xspc, c.xspd, money()))
		end
		local buy = {}
		if st.plan.acc > Inventory.count("x_accuracy") then buy[#buy + 1] = {name = "x_accuracy", index = 0, amount = st.plan.acc} end
		if st.plan.spc > Inventory.count("x_special") then buy[#buy + 1] = {name = "x_special", index = 6, amount = st.plan.spc} end
		if st.plan.spd > Inventory.count("x_speed") then buy[#buy + 1] = {name = "x_speed", index = 5, amount = st.plan.spd} end
		return guardedTransaction(st, {direction = "Up", buy = buy}, "Celadon 5F")
	end

	-- Viridian rival (reference 1:28:27-1:28:34): X ACCURACY then X SPEED. The inherited plan used X Accuracy + X
	-- SPECIAL, which (with Giovanni's) left 0 X Special for Lance in v3. Move choices stay the inherited ones.
	local engineViridianRival = Strategies.functions.viridianRival
	S.viridianRival = function()
		local prepare = Strategies.prepare
		Strategies.prepare = function(...)
			local args = {...}
			for i, v in ipairs(args) do if v == "x_special" then args[i] = "x_speed" end end
			return prepare((table.unpack or unpack)(args))
		end
		local automate = Battle.automate
		if ROUTE22_SIX_HD then   -- v31: guaranteed one-hit KOs while X Accuracy is up and Nidoking is faster
			Battle.automate = function(move, skipBuffs)
				local faster = Memory.raw(0x1029) * 256 + Memory.raw(0x102A) > Memory.raw(0x0FFA) * 256 + Memory.raw(0x0FFB)
				if Combat.xAccuracy() and faster and Battle.pp("horn_drill") > 0 then
					local opp = Battle.opponent() or "?"
					if REFSTRAT_R22HD_LOG ~= opp then
						REFSTRAT_R22HD_LOG = opp
						print("refstrat FIGHT r22: Horn Drill on " .. opp .. " (X Accuracy, faster)")
					end
					move = "horn_drill"
				end
				return automate(move, skipBuffs)
			end
		end
		local ok, r = pcall(engineViridianRival)
		Battle.automate = automate
		Strategies.prepare = prepare
		if not ok then error(r) end
		return r
	end

	-- v7: LORELEI BIRD IN PARTY SLOT 1 BEFORE THE BATTLE (reference: Indigo PC 1:33:56-1:34:04, commentary "I swap
	-- Pidgey to slot 1 immediately ... back in the day the strat was to swap in the fight"; Advanced Flex route
	-- "Standard Lorelei Menu: deposit squirtle and paras, swap nido w/ bird in pkmn menu"). After the swap the bird
	-- leads (and, once sacrificed, stays fainted in slot 1 for the rest of the League, as in the reference: later menus
	-- select Nidoking one slot below). The inherited code assumes Nidoking in party slot 0 for its HP (death check,
	-- heals), default item target, PP outside battle and in-battle potion permission; those four are made
	-- Nidoking-aware ONLY while Nidoking is in the party but not in slot 0 (i.e. only after this swap).
	local function nidoIdx()
		local i = Pokemon.indexOf("nidoking")
		return i
	end
	local function swapped()
		local i = nidoIdx()
		return i and i > 0
	end
	REFSTRAT_BIRD_SWAPPED = swapped
	local engineHP, engineMaxHP = Combat.hp, Combat.maxHP
	Combat.hp = function() if swapped() then return Pokemon.index(nidoIdx(), "hp") end return engineHP() end
	Combat.maxHP = function() if swapped() then return Pokemon.index(nidoIdx(), "max_hp") end return engineMaxHP() end
	local engineUse = Inventory.use
	Inventory.use = function(item, poke, midfight)
		-- review1 #1: also in battle (the inherited party selection uses `poke or 0`, the fainted bird after the swap)
		if poke == nil and swapped() then poke = "nidoking" end
		return engineUse(item, poke, midfight)
	end
	local engineMainFighter = Pokemon.mainFighter
	Pokemon.mainFighter = function()
		if swapped() then return Pokemon.isDeployed("nidoking") ~= nil end
		return engineMainFighter()
	end
	local enginePP = Battle.pp
	Battle.pp = function(move)
		if Memory.value("game", "battle") == 0 and swapped() then return REFSTRAT_NIDO_PP(move) end
		return enginePP(move)
	end

	-- {s="refBirdToSlot1"} on Lorelei's room entry tile (4,5) (reference 1:34:14.0-1:34:16.5, sources/HEAL_SHOP_BIRD.md
	-- 3.1: START -> POKEMON -> Nidoking -> SWITCH -> Pidgey; the PC at 1:33:56 only deposits). Here: the bird is
	-- selected and switched with slot 1 (same resulting order). Skipped (logged) when no bird is in the party.
	local BIRDS = {"pidgey", "pidgeotto", "spearow", "fearow"}
	S.refBirdToSlot1 = function()
		-- Explicit state machine (diags on seed 1787000041). The menu "size" byte is the highest cursor index, so in the
		-- party submenu ([field moves], STATS, SWITCH, CANCEL) SWITCH is size - 1 (size - 2 opened STATS = menu 141).
		-- After SWITCH the party list is in swap mode: choose slot 1. Navigation uses the menu cursor wCurrentMenuItem
		-- (0xCC26); success = the bird first in the party.
		local st = Strategies.status
		local bird = Pokemon.inParty(unpack(BIRDS))
		if st.logged == nil then
			st.logged = true
			st.phase, st.wait = "start", 0
			print("refstrat Lorelei room: bird " .. tostring(bird) .. " at party index " .. tostring(bird and Pokemon.indexOf(bird)) .. " -> slot 1")
		end
		if not bird then return true end
		if st.wait > 0 then st.wait = st.wait - 1; return false end
		local main, cursor = Memory.value("menu", "main"), Memory.raw(0x0C26)
		local function moveTo(target)
			if cursor == target then
				Input.press("A", 2); st.wait = 10
				return true
			end
			Input.press(cursor > target and "Up" or "Down", 2); st.wait = 4
			return false
		end
		if Pokemon.indexOf(bird) == 0 then
			if not st.done then st.done = true; print("refstrat Lorelei room: bird now in slot 1, Nidoking index " .. tostring(nidoIdx())) end
			if Menu.isOpened() or Textbox.isActive() then Input.press("B", 2); st.wait = 6; return false end
			return true
		end
		if st.switchPressed and main == Menu.pokemon then
			moveTo(0)                                                -- swap mode ("Move POKEMON where?"): slot 1
		elseif main == Menu.pokemon then
			moveTo(Pokemon.indexOf(bird))                            -- party screen: the bird
		elseif main == 128 and (Menu.getCol() == 10 or Menu.getCol() == 12) then
			if moveTo(Memory.value("menu", "size") - 1) then st.switchPressed = true end   -- [field moves], STATS, SWITCH, CANCEL
		elseif main == 128 and Menu.getCol() == 11 then
			moveTo(1)                                                -- START menu: POKEMON
		elseif Menu.isOpened() or Textbox.isActive() then
			Input.press("B", 2); st.wait = 6
		else
			Input.press("Start", 2); st.wait = 8
		end
		return false
	end
	-- v51 SKIP_INDIGO_PC: second swap, Nidoking into slot 2 (Bruno would otherwise face Squirtle after the fainted bird)
	local v50BirdToSlot1 = S.refBirdToSlot1
	S.refBirdToSlot1 = function(data)
		local st = Strategies.status
		if not st.v51phase2 then
			if not v50BirdToSlot1(data) then return false end
			if not SKIP_INDIGO_PC or not Pokemon.inParty("nidoking") or nidoIdx() == 1 then return true end
			st.v51phase2, st.wait, st.switchPressed = true, 0, nil
			print("refstrat SKIP_INDIGO_PC: Nidoking index " .. tostring(nidoIdx()) .. " -> slot 2")
		end
		if st.wait > 0 then st.wait = st.wait - 1; return false end
		local main, cursor = Memory.value("menu", "main"), Memory.raw(0x0C26)
		local function moveTo(target)
			if cursor == target then
				Input.press("A", 2); st.wait = 10
				return true
			end
			Input.press(cursor > target and "Up" or "Down", 2); st.wait = 4
			return false
		end
		local ni = nidoIdx()
		if ni == 1 then
			if not st.v51done then st.v51done = true; print("refstrat SKIP_INDIGO_PC: Nidoking now index 1") end
			if Menu.isOpened() or Textbox.isActive() then Input.press("B", 2); st.wait = 6; return false end
			return true
		end
		if st.switchPressed and main == Menu.pokemon then
			moveTo(1)
		elseif main == Menu.pokemon then
			moveTo(ni)
		elseif main == 128 and (Menu.getCol() == 10 or Menu.getCol() == 12) then
			if moveTo(Memory.value("menu", "size") - 1) then st.switchPressed = true end
		elseif main == 128 and Menu.getCol() == 11 then
			moveTo(1)
		elseif Menu.isOpened() or Textbox.isActive() then
			Input.press("B", 2); st.wait = 6
		else
			Input.press("Start", 2); st.wait = 8
		end
		return false
	end

	-- v7 Silph helpers. {s="refFightX", x="accuracy", move="horn_drill", reserve=N}: a talk-started trainer battle, X item
	-- first (prepared once) when more than N remain (N = the later fixed uses: Silph rival, Giovanni, Koga, Blackbelt,
	-- Route 22 rival, Lorelei, Bruno, Champion = 8 at the Arbok Rocket, 7 at the 11F Rocket; the reference had 10 and 8
	-- there and used one each), then the given move while it has PP, otherwise the damage model. {s="refSilphElevator", index=N}:
	-- the elevator panel with the floor list index N (0 = 1F ... 8 = 9F, 9 = 10F).
	S.refFightX = function(data)
		local st = Strategies.status
		if Strategies.trainerBattle() then
			if st.refXUse == nil then
				local have = Inventory.count("x_" .. tostring(data.x))
				st.refXUse = data.x ~= nil and have > (data.reserve or 0)
				print("refstrat " .. tostring(data.label) .. ": x_" .. tostring(data.x) .. " " .. have .. " (reserve " ..
					tostring(data.reserve or 0) .. ") -> " .. (st.refXUse and "use (reference)" or "RECOVERY: keep for the later fixed uses, damage model"))
			end
			if st.refXUse and not st.refXDone then
				if Strategies.prepare("x_" .. data.x) then st.refXDone = true else return false end
			end
			-- review1 #2: Horn Drill is forced only with X Accuracy active (reference: X Acc + HD); when the reserve rule
			-- keeps the X item (RECOVERY, logged above), the damage model chooses (t12-1787000094: 3 misses, HD 5 -> 1)
			local forced = st.refXDone and data.move or nil
			-- v19 edit F: per-opponent reference move (11F Rocket: Cubone BubbleBeam, SILPH.md row 25)
			local byOpp = data.byOpponent and data.byOpponent[Battle.opponent() or ""]
			if byOpp and Battle.pp(byOpp) > 0 then forced = byOpp end
			if forced and Battle.pp(forced) == 0 then forced = nil end
			if forced == "horn_drill" and RISK_TARGETED then
				local ours = Memory.raw(0x1029) * 256 + Memory.raw(0x102A)
				local theirs = Memory.raw(0x0FFA) * 256 + Memory.raw(0x0FFB)
				if ours < theirs then
					if st.refHDGuard ~= Memory.value("battle", "opponent_id") then
						st.refHDGuard = Memory.value("battle", "opponent_id")
						print("refstrat RISK " .. tostring(data.label) .. ": no forced Horn Drill (speed " .. ours .. " < " .. theirs .. ") -> damage model")
					end
					forced = nil
				end
			end
			Battle.automate(forced)
		elseif st.foughtTrainer then
			return true
		end
	end
	S.refSilphElevator = function(data)
		local st = Strategies.status
		if Menu.isOpened() then
			st.canProgress = true
			Menu.select(data.index, false, true)
		else
			if st.canProgress then return true end
			Player.interact("Up")
		end
	end

	-- v7 Lorelei with the bird leading (reference 1:34:30-1:35:30): turn 1 the bird fights and takes Dewgong's attack
	-- (in the reference a critical Aurora Beam knocks it out); Nidoking comes in (forced switch after the faint, or a
	-- manual switch if the bird survived a hit), X Accuracy (Dewgong's turn-2 Rest fails at full HP), then Horn Drill.
	-- The inherited lorelei (in-battle sacrifice swap) is used only when the pre-swap did not happen.
	local engineLorelei = Strategies.functions.lorelei
	S.lorelei = function()
		if not REFSTRAT_BIRD_SWAPPED() then return engineLorelei() end
		local st = Strategies.status
		if Strategies.trainerBattle() then
			if Menu.onPokemonSelect() then
				Battle.swap("nidoking")
				return false
			end
			local bird = Pokemon.isDeployed(unpack(BIRDS))
			if bird then
				local i = Pokemon.indexOf(bird)
				local hp, maxHp = Pokemon.index(i, "hp"), Pokemon.index(i, "max_hp")
				if hp > 0 and hp < maxHp then
					if not st.manualSwap then st.manualSwap = true; print("refstrat Lorelei: bird survived a hit -> switch to Nidoking") end
					Battle.swap("nidoking")
				else
					Battle.automate()
				end
				return false
			end
			if not st.loggedNido then st.loggedNido = true; print("refstrat Lorelei: Nidoking in, HP " .. Combat.hp()) end
			if Strategies.prepare("x_accuracy") then
				-- moves: the damage model (Horn Drill only scores when Nidoking is faster - t9 seed 1787000050: forcing
				-- it against a faster Jynx failed and Nidoking died); the inherited Jynx rule is kept
				local forced
				if Battle.opponent() == "jinx" and Battle.pp("horn_drill") <= 1 then forced = "earthquake" end
				Battle.automate(forced)
			end
		elseif st.foughtTrainer then
			return true
		end
	end

	-- Indigo Plateau: the reference never uses the Center (26/158 HP; Nidoking outspeeds Lorelei's team and one-shots it).
	-- t9 seed 1787000050: skipping it at 15/151 HP with a slower (lower-level) Nidoking died to Jynx, so v7 keeps the
	-- inherited Center check (PP items, and HP for Dewgong) as the decision and only logs it (healing stays partial).
	-- v17 (row 25; HEAL_SHOP_BIRD.md:113, 152-172, 330-338): the reference skips the Indigo Center: the bird (moved to slot
	-- 1 in Lorelei's room) takes Dewgong's only attack and the PP items cover the League (Horn Drill 6, Lorelei x5, Bruno-
	-- room Max Ether, Lance-room Elixer). Plan available = a bird with HP > 0 in the party, Nidoking alive, Horn Drill PP
	-- >= 5 and >= 2 PP-restore items. Low Nidoking HP alone does not require the Center.
	-- v17 edit 2 (pre-freeze review): the plan must be the reference's: (a) a usable sacrifice bird - fragile (L <= 10, the
	-- reference's L5 Pidgey) and undamaged (a damaged bird triggers the inherited manual switch at once), so Dewgong's
	-- first attack faints it and Nidoking gets the free X Accuracy turn; (b) PP closure by item type - Horn Drill PP >= 5
	-- on Nidoking itself (Lorelei x5), a Max Ether or Ether for Bruno's room and an Elixer for Lance's room (it restores
	-- Blizzard and Horn Drill together; afterwards Horn Drill is full for the Champion's six); (c) Nidoking alive.
	REFSTRAT_LEAGUE_PLAN = function()
		local bird = Pokemon.inParty(unpack(BIRDS))
		local birdHP = bird and Pokemon.info(bird, "hp") or 0
		local birdMax = bird and Pokemon.info(bird, "max_hp") or 0
		local birdLv = bird and Pokemon.info(bird, "level") or 0
		local ni = Pokemon.indexOf("nidoking")
		local hd = (ni and ni >= 0) and (Pokemon.pp(ni, "horn_drill") or 0) or 0
		local nhp = (ni and ni >= 0) and Pokemon.index(ni, "hp") or 0
		local ether = Inventory.count("max_ether") + Inventory.count("ether")
		local elixer = Inventory.count("elixer")
		local why = {}
		if not bird then why[#why + 1] = "no bird" elseif birdHP <= 0 then why[#why + 1] = "bird fainted"
		elseif birdHP < birdMax then why[#why + 1] = "bird damaged" elseif birdLv > 10 then why[#why + 1] = "bird not fragile (L"..birdLv..")" end
		if nhp <= 0 then why[#why + 1] = "Nidoking fainted" end
		-- v18 cycle 1: Horn Drill below 5 is covered by a spare Ether (Indigo top-up, a PP action - not a heal)
		local needEther = 1 + (hd < 5 and 1 or 0)
		if ether < needEther then why[#why + 1] = (hd < 5 and ("Horn Drill PP "..hd.." < 5 and Ethers "..ether.." < 2 (Bruno + top-up)")) or "no Max Ether / Ether for Bruno" end
		if elixer < 1 then why[#why + 1] = "no Elixer for Lance" end
		local ok = #why == 0
		REFSTRAT_LEAGUE_TOPUP = ok and hd < 5
		return ok, string.format("bird %s L%d hp %d/%d, Nidoking HD PP %d hp %d, Max Ether/Ether %d, Elixer %d%s", tostring(bird), birdLv, birdHP, birdMax,
			hd, nhp, ether, elixer, ok and "" or (" [unavailable: "..table.concat(why, "; ").."]"))
	end
	local enginePotionBeforeLorelei = Strategies.functions.potionBeforeLorelei
	S.potionBeforeLorelei = function(data)
		if REFSTRAT_RED_WINDOW then return true end   -- v35 RED_LATE
		local st = Strategies.status
		if st.refPlan == nil then
			local ok, why = REFSTRAT_LEAGUE_PLAN()
			st.refPlan = ok
			print("refstrat Victory Road Lorelei heal decision (row 25): "..why.." -> "..(ok and "no heal (reference: bird plan available)" or "RECOVERY: inherited potionBeforeLorelei (bird/PP plan unavailable)"))
		end
		if st.refPlan then return true end
		return enginePotionBeforeLorelei(data)
	end
	-- v35 RED_LATE: in-battle heals off inside the window; after Lorelei heal by the Viridian step's rule
	if RED_LATE then
		local C = require "ai.control"
		local canRecover = C.canRecover
		C.canRecover = function(...) if REFSTRAT_RED_WINDOW then return false end return canRecover(...) end
	end
	S.refRedEnd = function(data)
		local st = Strategies.status
		local agatha = data and data.agatha
		if RED_BRUNO and st.go == nil then   -- v43: Bruno's room keeps the window open (HP >= RED_BRUNO_MIN), Agatha's room closes it
			if agatha then
				if not REFSTRAT_RED_WINDOW then return true end   -- already closed in Bruno's room
			elseif REFSTRAT_RED_WINDOW and Combat.hp() > 0 and Combat.hp() >= (RED_BRUNO_MIN or 0) then
				print("refstrat RED_BRUNO: window stays open through Bruno, hp " .. Combat.hp() .. "/" .. Combat.maxHP() .. " (min " .. tostring(RED_BRUNO_MIN or 0) .. ")")
				return true
			end
		end
		if st.go == nil then
			REFSTRAT_RED_WINDOW = false
			st.fr = Inventory.count("full_restore") >= (MANSION_FR_SKIP and 1 or 2)   -- v59: one Full Restore, used here
			st.go = Combat.hp() < 80
			print("refstrat RED_LATE: window closed " .. (agatha and "after Bruno" or "after Lorelei") .. ", hp " .. Combat.hp() .. "/" .. Combat.maxHP() .. " -> "
				.. (st.go and (st.fr and "Full Restore" or "Potions to 80") or "no heal"))
		end
		if not st.go then return true end
		if st.fr then return Strategies.functions.potion({hp = 999, forced = "full_restore", chain = true}) end
		return Strategies.functions.potion({hp = 80})
	end
	S.refCenterSkip = function()
		local st = Strategies.status
		if st.refPlan == nil then
			local ok, why = REFSTRAT_LEAGUE_PLAN()
			st.refPlan = ok
			print("refstrat Indigo Center decision (row 25): "..why.." -> "..(ok and ("no Center (reference: bird + PP plan available)"
				..(REFSTRAT_LEAGUE_TOPUP and "; PP recovery: Horn Drill top-up with an Ether (not a heal)" or "")) or "RECOVERY: Center (bird/PP plan unavailable)"))
			st.topUp = ok and REFSTRAT_LEAGUE_TOPUP
		end
		if st.refPlan then
			if st.topUp then
				return Strategies.functions.refRestorePP({moves = {{"horn_drill", 5}}, prefer = {"ether", "max_ether"}})
			end
			return true
		end
		-- plan unavailable: the logged RECOVERY is the Center itself (not the inherited skip check)
		return Strategies.functions.dialogue({dir = "Up"})
	end

	-- v16 (healing table row 22, reference H11, HEAL_SHOP_BIRD.md:75; C 1:23:35-1:24:17 "I will elixir so he kills me
	-- with self-destruct"; G-FLEX "Koga Weezing Menu S: use elixer"): on Weezing's first turn the reference uses an
	-- ELIXER on Nidoking (a stall turn) so that Weezing Selfdestructs; Nidoking faints, the win is awarded, and the three
	-- kept Rare Candies revive it after the Fly to Pallet (row 23, the route's Pallet candy step). Prerequisite: Weezing
	-- is the opponent, Nidoking is alive and an Elixer is in the bag. Exactly one stall turn; afterwards (or without an
	-- Elixer: logged RECOVERY fallback) the inherited Weezing plan runs (Horn Drill at low HP / Poke Flute stall /
	-- attack, canDie). Outcome logged at the end of the fight (Nidoking HP 0 = deliberate faint, gym won).
	-- v16 row 7 (reference 13:42-13:44.5, HEAL_SHOP_BIRD.md:67; G-HP "Before Shorts Guy: 1-24 Potion, 25+ Don't heal"):
	-- one Potion at <= 24 HP, otherwise no heal. (The reference first tossed the Antidote - a bag-slot preparation
	-- without healing effect, not reproduced; disclosed.) Replaces the inherited 2x Rattata-damage threshold.
	S.potionBeforeShorts = function()
		local st = Strategies.status
		if st.refShorts == nil then
			local hp = Combat.hp()
			st.refShorts = (hp <= 24 and hp > 0) and math.min(Combat.maxHP(), hp + 1) or false
			print("refstrat Route 3 before the Shorts Guy (reference row 7): hp "..hp.."/"..Combat.maxHP().." -> "..(st.refShorts and "one Potion" or "no heal"))
		end
		if not st.refShorts then return true end
		REFSTRAT_REF_HEAL_ROW = "row7 Route 3 Potion before the Shorts Guy"
		local r = Strategies.functions.potion({hp = st.refShorts, forced = "potion"})
		if r then REFSTRAT_REF_HEAL_ROW = nil end
		return r
	end

	-- v16 row 15 (reference 33:14.5-33:22: Rare Candy first, then POTION x2, 18 -> 61/81; G-HP "Bill's House HP@L23
	-- 8-28: 2 Potions"; G-FLEX target 48-67): after the candy, two Potions at <= 28 HP, one at 29-47, none at >= 48.
	-- Replaces the inherited potionBeforeMisty (Goldeen target) at Bill's; chain keeps the menu for the Escape Rope.
	S.refBillPotions = function(data)
		local st = Strategies.status
		if st.refBill == nil then
			local hp, mx = Combat.hp(), Combat.maxHP()
			local want = (hp <= 28) and 2 or ((hp <= 47) and 1 or 0)
			-- v18 edit W2: the decision is bounded by the Potions held (c6b-1805001535 decided 2 with 1 in the bag)
			local n = math.min(want, Inventory.count("potion"))
			st.refBill = n > 0 and math.min(mx, hp + 20 * n - 19) or false
			print("refstrat Bill's (reference row 15): hp "..hp.."/"..mx.." after the candy -> "..n.." Potion(s)"
				..(n < want and (" (reference rule "..want..", Potions held "..Inventory.count("potion")..")") or ""))
		end
		if not st.refBill then return true end
		return Strategies.functions.potion({hp = st.refBill, forced = "potion", chain = data.chain})
	end

	-- v16 (from reviewed v15; healing decision table row 28): Agatha's room, reference 1:36:54 - ONE Super Potion (36 -> 86/168); WR guide:
	-- skip the heal at <= 32 HP. The inherited heal to 113 HP follows only as a logged RECOVERY (refRecoveryPotion; v7
	-- t9/t10: the guide-only Agatha table died).
	S.refAgathaSuper = function()
		local st = Strategies.status
		if st.target == nil then
			local hp, mx = Combat.hp(), Combat.maxHP()
			-- v18 cycle 2 (edit K2): the guide rule literally (G-WR "Use Super Potion ... If 32 HP or below, can skip heal");
			-- the cycle-1 ">= 50 HP missing" condition is reverted (the Fuchsia top-up removes the supply reason for it)
			st.target = (hp > 32 and hp < mx and Inventory.contains("super_potion")) and math.min(mx, hp + 1) or false
			print("refstrat Agatha (reference H13): hp "..hp.."/"..mx.." -> "..(st.target and "one Super Potion"
				or "no reference heal (<= 32 HP, full HP or no Super Potion)"))
		end
		if not st.target then return true end
		return Strategies.functions.potion({hp = st.target, forced = "super_potion"})
	end

	-- v17 evidence (v16 final review): every healing / PP item use, including direct calls that bypass the potion
	-- wrapper (Forest grabForestPotion, Brock fightBrock, Silph rival, agatha-v1 Gengar, engine recover()), logs one
	-- ITEMUSE decision line: strategy identity, battle flag, map, lead HP and item count before the action. The passive
	-- HEALEVAL item event shows the actual consumption; tools/heal_report.py joins both.
	local HEAL_ITEMS = {potion = true, super_potion = true, hyper_potion = true, full_restore = true, max_potion = true,
		elixer = true, max_elixer = true, ether = true, max_ether = true, rare_candy = true, revive = true, paralyze_heal = true}
	local prevExecute = Strategies.execute
	Strategies.execute = function(data)
		REFSTRAT_CUR_STRATEGY = data and data.s
		-- edit O: a heal step's identity ends when another route step starts
		if REFSTRAT_CUR_DATA ~= data and REFSTRAT_TOSS_FINALIZE then REFSTRAT_TOSS_FINALIZE() end
		REFSTRAT_CUR_DATA = data
		if REFSTRAT_STEP and REFSTRAT_STEP.route ~= data then REFSTRAT_STEP = nil end
		return prevExecute(data)
	end
	-- v18 edit Q: tosses are logged (an item decrease that is not a use)
	-- edit S: logged at completion with the actual bag change (a start log could describe a toss that never happened)
	local engineToss = Strategies.tossItem
	local tossSnap = {}
	-- edit T: completion evidence also when the caller finishes without calling tossItem again (Route 23 wrapper)
	function REFSTRAT_TOSS_FINALIZE()
		if tossSnap.key and not tossSnap.done then
			tossSnap.done = true
			for n, before in pairs(tossSnap.counts) do
				local now = Inventory.count(n)
				if now < before then
					print(string.format("refstrat TOSS item=%s n=%d before=%d after=%d map=%d strategy=%s", n, before - now, before, now,
						Memory.value("game", "map"), tostring(tossSnap.strategy)))
				end
			end
		end
	end
	Strategies.tossItem = function(...)
		local names = {...}
		local key = tostring(REFSTRAT_CUR_DATA)
		if tossSnap.key ~= key then
			REFSTRAT_TOSS_FINALIZE()
			tossSnap = {key = key, counts = {}, strategy = REFSTRAT_CUR_STRATEGY}
			for _, n in ipairs(names) do tossSnap.counts[n] = Inventory.count(n) end
		end
		local r = engineToss(...)
		if r then REFSTRAT_TOSS_FINALIZE() end
		return r
	end
	local engineUse = Inventory.use
	local useKey = nil
	Inventory.use = function(item, poke, midfight)
		if HEAL_ITEMS[item] then
			-- v18 edit L: in battle the turn key is part of the decision identity (one line per turn)
			local inBattle = Memory.value("game", "battle") ~= 0
			local turn = (inBattle and REFSTRAT_TURN_KEY) and REFSTRAT_TURN_KEY(Combat.hp()) or "-"
			local key = tostring(REFSTRAT_CUR_STRATEGY) .. ":" .. item .. ":" .. Inventory.count(item) .. ":" .. tostring(REFSTRAT_ITEM_SOURCE) .. ":" .. turn
			-- one line per decision; a repeated attempt at the same count after an abandoned one (> 300 frames) logs again
			-- edit L3: in battle, log only while the game waits for our action (REFSTRAT_ACTION_PENDING, battle.lua)
			local pending = not inBattle or not REFSTRAT_ACTION_PENDING or REFSTRAT_ACTION_PENDING()
			if pending and (key ~= useKey or emu.framecount() - (REFSTRAT_USE_FRAME or 0) > 300) then
				useKey = key
				-- v18 cycle 2: source (engine recover() / paralysis cure / scripted strategy) and the calling line
				local info = debug and debug.getinfo and debug.getinfo(2, "Sl")
				local src = tostring(info and info.short_src):gsub("\\", "/"):gsub('[%s"%[%]]', '')
				local caller = info and ((src:match("([^/]+/[^/]+)$") or src)..":"..tostring(info.currentline)) or "?"
				print(string.format("refstrat ITEMUSE strategy=%s item=%s count=%d battle=%d map=%d hp=%d/%d target=%s source=%s caller=%s turn=%s step=%s",
					tostring(REFSTRAT_CUR_STRATEGY), item, Inventory.count(item), Memory.value("game", "battle"), Memory.value("game", "map"),
					Combat.hp(), Combat.maxHP(), tostring(poke), REFSTRAT_ITEM_SOURCE or "script", caller, turn,
					(not inBattle and REFSTRAT_STEP) and REFSTRAT_STEP.id or "-"))
			end
			REFSTRAT_USE_FRAME = emu.framecount()
		end
		return engineUse(item, poke, midfight)
	end

	-- v18 League maps (Indigo, E4 rooms, Champion): before them the engine's paralysis cure keeps the Full Restore
	-- (battle.lua; cycle-2 edit H). The cycle-1 recover() item reserve was reverted (edit J): the League supply comes
	-- from the Fuchsia top-up (refShopFuchsia) and the overworld steps' 3-Super-Potion reserve (S.potion).
	REFSTRAT_LEAGUE_MAPS = {[174] = true, [245] = true, [246] = true, [247] = true, [113] = true, [120] = true, [118] = true}
	-- Lance's room (reference 1:38:44: ELIXER, then SUPER POTION 89 -> 139; WR guide "heal to 127+"): after the PP step,
	-- heal with Super Potions / Potions to the survival target = maximum non-critical Hydro Pump of Lance's Gyarados
	-- against THIS Nidoking + 1 (Combat.healthFor; the guide's 127+ is the same quantity for the reference's L52
	-- Nidoking, whose higher Special gives a lower maximum; its Hydro Pump did 116). The Full Restore is the post-Lance
	-- reference item; it is used here only as a logged RECOVERY when Super Potions and Potions cannot reach the target.
	S.prepareForLance = function(data)
		local st = Strategies.status
		if st.lance == nil then
			local hp, mx = Combat.hp(), Combat.maxHP()
			local target = math.min(mx, Combat.healthFor("LanceGyarados") + 1)
			local ltTarget = REFSTRAT_LT_TARGET and REFSTRAT_LT_TARGET()   -- v42 LEAGUE_TACTIC (a)
			if ltTarget and math.min(mx, ltTarget) > target then
				print("refstrat LEAGUE_TACTIC Lance prep: target "..target.." -> "..math.min(mx, ltTarget).." (party Special)")
				target = math.min(mx, ltTarget)
			end
			local pool = hp + 50 * Inventory.count("super_potion") + 20 * Inventory.count("potion")
			st.lance = {target = target, useFull = pool < target and Inventory.contains("full_restore") ~= nil}
			print(string.format("refstrat Lance prep (row 29): hp %d/%d target %d (max Hydro Pump + 1), Super %d, Potion %d, Full Restore %d -> %s",
				hp, mx, target, Inventory.count("super_potion"), Inventory.count("potion"), Inventory.count("full_restore"),
				hp >= target and "no heal (at target)" or (st.lance.useFull and "RECOVERY: Full Restore before Lance (Super Potions/Potions cannot reach the target)"
				or "reference: Super Potion/Potion to the target")))
		end
		if Combat.hp() >= st.lance.target then return true end
		if st.lance.useFull then
			return Strategies.functions.potion({hp = st.lance.target, forced = "full_restore", chain = true})
		end
		local item = Inventory.contains("super_potion", "potion")
		if not item then
			if not st.short then st.short = true; print("refstrat Lance prep: items exhausted below the target ("..Combat.hp().."/"..st.lance.target..")") end
			return true
		end
		return Strategies.functions.potion({hp = st.lance.target, forced = item, chain = true})
	end

	-- v18 cycle 1 / edit M: Viridian (reference 1:26:07 Elixer at the gym entrance, after the Blackbelt and before
	-- Giovanni; route step on the re-entry tile (32,8)): an ELIXER (all moves) when Horn Drill / Earthquake / Blizzard are low and an Elixer
	-- stays for Lance's room; the Max Ether stays for Bruno's room (reference). Otherwise no PP item here (logged).
	S.refViridianElixer = function(data)
		local st = Strategies.status
		if st.go == nil then
			local ni = Pokemon.indexOf("nidoking")
			local function pp(m) return (ni and ni >= 0 and Pokemon.moveIndex(m, "nidoking")) and (Pokemon.pp(ni, m) or 0) or 99 end
			local hd, eq, bz, ex = pp("horn_drill"), pp("earthquake"), pp("blizzard"), Inventory.count("elixer")
			local low = hd < 5 or eq < 4 or bz < 2
			st.go = low and ex >= 2
			print(string.format("refstrat Viridian PP (reference Elixer): HD %d EQ %d Blizzard %d, Elixers %d -> %s", hd, eq, bz, ex,
				st.go and "Elixer" or (low and "no Elixer to spare (one kept for Lance)" or "no PP item needed")))
		end
		if not st.go then return true end
		return Strategies.functions.refRestorePP({moves = {{"horn_drill", "max"}, {"earthquake", "max"}, {"blizzard", "max"}}, prefer = {"elixer"}, chain = data.chain})
	end

	-- v18 edit M: the reference used no PP item after Sabrina (next: the Viridian gym entrance Elixer)
	S.refSabrinaNoElixer = function()
		local ni = Pokemon.indexOf("nidoking")
		local eq = (ni and ni >= 0) and (Pokemon.pp(ni, "earthquake") or 0) or 0
		print("refstrat Sabrina: no Elixer (reference; Earthquake PP "..eq..", Elixers "..Inventory.count("elixer")..", next PP item at the Viridian gym entrance)")
		return true
	end

	local engineFightKoga = Strategies.functions.fightKoga
	S.fightKoga = function(data)
		local st = Strategies.status
		-- side-effect-free battle check (Strategies.trainerBattle() handles text boxes outside battle; calling it here as
		-- well as in the engine function made Koga's pre-battle dialogue stall - dev k1, 4/12 runs at (4,9))
		if Memory.value("game", "battle") == 2 then
			if st.kogaStall == nil and Battle.opponentAlive() and Battle.opponent() == "weezing" then
				local hp, mx, ex = Combat.hp(), Combat.maxHP(), Inventory.count("elixer")
				st.kogaStall = (hp > 0 and ex > 0) and ex or false
				print("refstrat Koga Weezing turn 1: Nidoking "..hp.."/"..mx..", Elixers "..ex.." -> "..(st.kogaStall
					and "reference Elixer stall (H11)" or "RECOVERY: no Elixer for the reference stall - inherited Weezing plan"))
			end
			if st.kogaStall and not st.kogaStallDone then
				st.kogaStallStart = st.kogaStallStart or emu.framecount()
				if emu.framecount() - st.kogaStallStart > 900 and Inventory.count("elixer") >= st.kogaStall then
					-- bound (final review): 900 emulated frames without consumption -> logged fallback, not counted as a stall
					st.kogaStallDone, st.kogaStallFailed = true, true
					print("refstrat RECOVERY Koga: Elixer stall not completed within 900 frames - inherited Weezing plan")
				elseif Inventory.count("elixer") < st.kogaStall then
					st.kogaStallUsed = true
					st.kogaStallDone = true
					print("refstrat Koga: Elixer stall used (Elixers "..st.kogaStall.." -> "..Inventory.count("elixer")..")")
				else
					Inventory.use("elixer", "nidoking", true)
					return false
				end
			end
		end
		-- v18 cycle 1: the reference used no X Accuracy at Koga (its 12 uses: ... Silph Giovanni, Blaine, Blackbelt ...);
		-- the inherited Koffing X Accuracy is suppressed (prepare("x_accuracy") reports done without using an item)
		local enginePrepare = Strategies.prepare
		Strategies.prepare = function(item, ...)
			if item == "x_accuracy" then
				if not st.kogaNoX then st.kogaNoX = true; print("refstrat Koga: no X Accuracy (reference)") end
				return true
			end
			return enginePrepare(item, ...)
		end
		local ok, r = pcall(engineFightKoga, data)
		Strategies.prepare = enginePrepare
		if not ok then error(r) end
		if r and not st.kogaLogged then
			st.kogaLogged = true
			local nhp = Pokemon.info("nidoking", "hp")
			print("refstrat Koga outcome: gym won, Nidoking HP "..tostring(nhp)..(nhp == 0 and " (fainted - reference deliberate faint; Pallet candies revive)" or " (alive - no faint)")
				..", stall "..(st.kogaStallUsed and "used" or (st.kogaStallFailed and "not completed (fallback)" or "not used")))
		end
		return r
	end

	-- v7 RECOVERY heal (documented separately from the reference path; logged "refstrat RECOVERY"): {s="refRecoveryPotion",
	-- hp=N, why=...} = the inherited potion step to N HP. Used before Silph Giovanni (reference: 25/123 HP, no heal).
	S.refRecoveryPotion = function(data)
		local st = Strategies.status
		if st.hp0 == nil then st.hp0 = Combat.hp() end
		local r = Strategies.functions.potion({hp = data.hp})
		if r and Combat.hp() > st.hp0 then
			print("refstrat RECOVERY potion to " .. data.hp .. " (" .. data.why .. "): hp " .. st.hp0 .. " -> " .. Combat.hp())
		end
		return r
	end
	-- v7 evidence log (read-only): every map change seen by the walker ("refstrat MAP a->b (position at the transition)";
	-- the position is sampled when the map byte changes, which may still be the departure tile - review1 #7),
	-- so section traces (Silph floors/pads/elevator, Lorelei room) can be checked against the reference.
	local Walk = require "action.walk"
	local engineTraverse = Walk.traverse
	local lastMapLogged = nil
	Walk.traverse = function(region)
		if region ~= lastMapLogged then
			local x, y = Player.position()
			print(string.format("refstrat MAP %s->%d (position at the transition %d,%d)", tostring(lastMapLogged), region, x, y))
			lastMapLogged = region
		end
		return engineTraverse(region)
	end

	-- v7 evidence log (read-only) for screen-aware decisions (engine fix #2). Whenever a move is chosen while the
	-- opponent has Reflect or Light Screen up (wEnemyBattleStatus3 0xD069 bit 2 / bit 1), print the opponent, the
	-- selected move (forced or the damage model's), the engine's damage range for THAT move with the screen applied
	-- (Combat.calcRange), and when the turn resolves the HP removed ("refstrat SCREEN ... -> outcome"). Opponent HP is
	-- an inherited hidden read (disclosed); the screen itself is announced on screen.
	do
		local CombatL = require "ai.combat"
		local pending, lastKey
		local function opponentHP() return Memory.raw(0x0FE6) * 256 + Memory.raw(0x0FE7) end
		local fightBeforeScreenLog = Battle.fight
		Battle.fight = function(move, ...)
			local es = Memory.raw(0x1069)
			local reflect, ls = bit.band(es, 4) == 4, bit.band(es, 2) == 2
			local hp, opp = opponentHP(), Memory.value("battle", "opponent_id")
			if pending and (pending.opp ~= opp or pending.hp ~= hp) then
				print(string.format("refstrat SCREEN outcome: opp=%d hp %d -> %d (removed %d)%s", pending.opp, pending.hp,
					pending.opp == opp and hp or 0, pending.hp - (pending.opp == opp and hp or 0), pending.opp ~= opp and " (KO)" or ""))
				pending = nil
			end
			if reflect or ls then
				local ours, enemy = CombatL.activePokemon()
				local bm = CombatL.bestMove()
				local chosen = (type(move) == "string" and move) or (type(move) == "table" and move.name) or (bm and bm.name) or "?"
				local key = opp .. ":" .. hp .. ":" .. tostring(chosen)
				if key ~= lastKey then
					lastKey = key
					local lo, hi = "?", "?"
					for _, mv in ipairs(ours.moves) do
						if mv.name == chosen or mv.name:lower():gsub("-", "_") == tostring(chosen):lower() then
							lo, hi = CombatL.calcRange(mv, ours, enemy)
						end
					end
					print(string.format("refstrat SCREEN map=%d opp=%d hp=%d reflect=%s lightscreen=%s chosen=%s range_with_screen=%s-%s",
						Memory.value("game", "map"), opp, hp, tostring(reflect), tostring(ls), tostring(chosen), tostring(lo), tostring(hi)))
					pending = {opp = opp, hp = hp}
				end
			end
			return fightBeforeScreenLog(move, ...)
		end
	end

	-- v7: close menus left open by a chained inherited item step (prepareForLance uses chain=true; in the reference order
	-- it is the last menu action in Lance's room, so nothing else closed it -> A/B text loop, diag 1787000069)
	S.refCloseMenu = function()
		local st = Strategies.status
		st.f0 = st.f0 or emu.framecount()
		if Menu.isOpened() then                      -- an open menu must close (review1 #6)
			if Menu.canCloseMessage() then Input.press("B", 2) else Menu.close() end
			return false
		end
		if Textbox.isActive() and emu.framecount() - st.f0 < 120 then   -- cap only for the stale textbox flag (F8)
			Input.press("B", 2)
			return false
		end
		return true
	end

	-- v7 Silph battles (the reference learns Earthquake only at the Safari gate, after Silph). Reference moves per
	-- opponent (SILPH.md row 21 rival: Pidgeot HD after X Acc + X Speed, Gyarados HD after X Special, Growlithe BB,
	-- Alakazam HD, Venusaur HD; row 27 Giovanni: Nidorino HD after X Acc, Kangaskhan HD, Rhyhorn BB, Nidoqueen HD;
	-- WR guide "HD everything except BB Growlithe", "X Acc + HD, HD, BB, HD"). The inherited silphRival /
	-- fightSilphGiovanni keep their X-item preparation; the move each turn is the reference move, with Horn Drill
	-- forced only while X Accuracy is active and Nidoking is faster (Gen 1 OHKO rule), otherwise the damage model.
	local SILPH_MOVES = {growlithe = "bubblebeam", rhyhorn = "bubblebeam", alakazam = "horn_drill", nidoqueen = "horn_drill",
		nidorino = "horn_drill", pidgeot = "horn_drill", gyarados = "horn_drill", venusaur = "horn_drill", kangaskhan = "horn_drill"}
	local function withSilphMoves(engineFn)
		return function(data)
			local automate = Battle.automate
			Battle.automate = function(move, skipBuffs)
				local ref = SILPH_MOVES[Battle.opponent() or ""]
				if ref == "horn_drill" then
					local faster = Memory.raw(0x1029) * 256 + Memory.raw(0x102A) > Memory.raw(0x0FFA) * 256 + Memory.raw(0x0FFB)
					if not (Combat.xAccuracy() and faster) then ref = nil end
				end
				if ref and Battle.pp(ref) > 0 then move = ref else move = nil end
				if SILPH_ROCKSLIDE and Battle.opponent() == "growlithe" and Combat.xAccuracy() and Battle.pp("rock_slide") > 0 then
					-- v31: Rock Slide only when its minimum non-critical damage surely KOs (no second BubbleBeam)
					local faster = Memory.raw(0x1029) * 256 + Memory.raw(0x102A) > Memory.raw(0x0FFA) * 256 + Memory.raw(0x0FFB)
					local ours, enemy = Combat.activePokemon()
					for _, mv in ipairs(ours.moves or {}) do
						if mv.name == "Rock-Slide" and faster then
							local lo = Combat.calcRange(mv, ours, enemy)
							if lo >= enemy.hp then
								print("refstrat FIGHT silph: Rock Slide KOs Growlithe (min " .. lo .. " >= hp " .. enemy.hp .. ")")
								move = "rock_slide"
							end
						end
					end
				end
				return automate(move, skipBuffs)
			end
			local ok, r = pcall(engineFn, data)
			Battle.automate = automate
			if not ok then error(r) end
			return r
		end
	end
	S.silphRival = withSilphMoves(Strategies.functions.silphRival)
	S.fightSilphGiovanni = withSilphMoves(Strategies.functions.fightSilphGiovanni)
end

-- v40 INPUT_FIX (default off; experiments/overnight-2026-10-16/input/REPORT.md): hold A over the two learn-move text
-- pauses ("1, 2 and... Poof!", pokered learn_move.asm; TextCommand_PAUSE samples held A/B once, else waits 30 frames).
-- Only after the last timed chain (surge) has finished and outside route steps marked chain=true (INPUT_FIX_MENUCHAIN
-- also allows those). Reads only the text box tiles (wTileMap) - no play-time or RNG memory. Unset: not installed.
if INPUT_FIX then
	local Input = require "util.input"
	local engineAdvance = Input.advance
	local armed, held, ended = false, 0, false
	local function oneTwoAnd()   -- first text line, wTileMap (1,14)..(4,14) = "1, 2"
		return memory.readbyte(0x04B9) == 0xF7 and memory.readbyte(0x04BA) == 0xF4
			and memory.readbyte(0x04BB) == 0x7F and memory.readbyte(0x04BC) == 0xF8
	end
	Input.advance = function()
		if not armed then
			local c = REFSTRAT_CHAIN
			if c and c.name == "surge" and c.finished then
				armed = true
				print("refstrat INPUT_FIX: armed after the surge chain at frame " .. emu.framecount())
			end
		elseif oneTwoAnd() then
			local d = REFSTRAT_CUR_DATA
			if not ended and not (d and d.chain and not INPUT_FIX_MENUCHAIN) then
				if memory.readbyte(0x04F2) == 0xEE or held >= 240 then   -- prompt arrow (18,16) drawn after the pauses (cap: 4 s)
					ended = true
					print("refstrat INPUT_FIX: A held " .. held .. " frames over the learn-move pauses (strategy "
						.. tostring(REFSTRAT_CUR_STRATEGY) .. (held >= 240 and ", cap" or "") .. ")")
				else
					held = held + 1
					joypad.set({A = true})
				end
			end
		else
			held, ended = 0, false
		end
		return engineAdvance()
	end
	print("Upgrade loaded: v40 INPUT_FIX (learn-move text pauses after the surge chain"
		.. (INPUT_FIX_MENUCHAIN and ", also in chain=true steps)" or ")"))
end

-- v42 LEAGUE_TACTIC (default off; experiments/overnight-2026-10-16/league/REPORT.md). Bit 1 = Lance, bit 2 = Celadon
-- shortfall keeps Blue's X Speed (REFSTRAT_CELADON_EXACT). Lance facts (pokered): Lance = move_choices 1,3; layer 3
-- (AIGetTypeEffectiveness, first matching type-chart row) encourages Water vs Ground and Psychic vs Poison, so against
-- Nidoking Gyarados always uses Hydro Pump and the Dragonairs (Agility/Slam/Dragon Rage/Hyper Beam) and Dragonite
-- (Agility/Slam/Barrier/Hyper Beam) only Agility/Barrier: 0 of 798 recorded arrivals died on turns 3-5. Aerodactyl
-- (Supersonic/Bite/Take Down/Hyper Beam, 170 speed) is the only later threat; it acts only when our attack fails.
-- Nidoking reaches Lance at L52 (Special 109, exp 138715 in every recorded run) and levels up on the first Dragonair KO.
do
	local Battle = require "action.battle"
	local Combat = require "ai.combat"
	local Inventory = require "storage.inventory"
	local Memory = require "util.memory"
	local Pokemon = require "storage.pokemon"
	local S = REFSTRAT_STRATEGIES
	local engineLance = Strategies.functions.lance
	local DRAGONAIR, AERODACTYL, NIDOKING = 89, 171, 7
	local function word(a) return Memory.raw(a) * 256 + Memory.raw(a + 1) end
	local function on(b) return LEAGUE_TACTIC and math.floor(LEAGUE_TACTIC / b) % 2 == 1 end

	-- BEGIN_PURE_LT_KO
	-- Exact Gen 1 one-turn KO chance of a special move without STAB (pokered core.asm): stats > 255 -> both / 4;
	-- ((2L/5+2) * power * A / D) / 50, cap 997, + 2; type rows x eff/10; damage >= 2 -> x r/255 with r uniform 217..255;
	-- critical (critRate/256): level x2 and unmodified stats; hit chance accByte/256.
	REFSTRAT_LT_KO = function(level, A, D, power, eff, accByte, hp, critA, critD, critRate)
		local floor = math.floor
		local function dmg(L, a, d)
			if a > 255 or d > 255 then a = floor(a / 4); d = floor(d / 4) end
			if a < 1 then a = 1 end
			if d < 1 then d = 1 end
			local x = floor(floor(floor(2 * L / 5 + 2) * power * a / d) / 50)
			if x > 997 then x = 997 end
			x = x + 2
			for _, e in ipairs(eff) do x = floor(x * e / 10) end
			return x
		end
		local function share(base)
			if base < 2 then return (base >= hp) and 1 or 0 end
			local n = 0
			for r = 217, 255 do if floor(base * r / 255) >= hp then n = n + 1 end end
			return n / 39
		end
		local pn, pc = share(dmg(level, A, D)), share(dmg(level * 2, critA, critD))
		return accByte / 256 * (critRate / 256 * pc + (1 - critRate / 256) * pn), pn, pc
	end
	-- END_PURE_LT_KO

	-- (a) maximum non-critical Hydro Pump of Lance's Gyarados (L58, Special 130) after our X Special (stat x15/10, then
	-- the badge boost +1/8) + 1; party Special of slot 0 (Nidoking), so no stale battle value
	REFSTRAT_LT_TARGET = function()
		if not on(1) then return nil end
		local ni = Pokemon.indexOf("nidoking")   -- v47: Nidoking's real slot (index 1 after the Lorelei bird swap)
		if not ni or ni < 0 then return nil end
		local base = 0x116B + 44 * ni
		if Memory.raw(base) ~= NIDOKING then return nil end
		local s = math.floor(word(base + 42) * 15 / 10)
		s = math.min(999, s + math.floor(s / 8))
		local x = math.floor(math.floor(25 * 120 * 130 / s) / 50) + 2
		x = x + math.floor(x / 2)
		return x * 2 + 1
	end

	-- (c) Aerodactyl (Rock/Flying: Thunderbolt and Blizzard both x2, no STAB): higher exact KO chance; ties -> Thunderbolt
	-- (keeps Blizzard PP for Dragonite). Nidoking crit rate 85/2 = 42/256; crit uses the party Special.
	local function aerodactylMove(st)
		local hp = word(0x0FE6)
		if hp == 0 or Combat.sandAttacked() then return nil end
		local L, A, D = Memory.value("battle", "our_level"), word(0x102B), word(0x0FFC)
		local rawA = word(0x116B + 0x2C * Memory.raw(0x0C2F) + 42)
		local best, bestP, txt = nil, -1, {}
		for _, mv in ipairs({{"thunderbolt", 95, 255}, {"blizzard", 120, 229}}) do
			if Battle.pp(mv[1]) > 0 then
				local pko = REFSTRAT_LT_KO(L, A, D, mv[2], {20}, mv[3], hp, rawA, D, 42)
				txt[#txt + 1] = string.format("%s %.3f", mv[1], pko)
				if pko > bestP + 1e-9 then best, bestP = mv[1], pko end
			end
		end
		local key = hp .. ":" .. A .. ":" .. tostring(best)
		if best and st.ltAeroLog ~= key then
			st.ltAeroLog = key
			print("refstrat LEAGUE_TACTIC Lance: Aerodactyl hp "..hp..", Special "..A.." L"..L.." -> KO chance "..table.concat(txt, ", ").." -> "..best)
		end
		return best
	end

	S.lance = function()
		if not on(1) then return engineLance() end
		local st = Strategies.status
		if Strategies.trainerBattle() then
			if st.ltXSpd0 == nil then st.ltXSpd0, st.ltXSpc0 = Inventory.count("x_speed"), Inventory.count("x_special") end
			-- inherited order (engine lance): X Special on the first opponent, X Speed on the first Dragonair
			local xItem = Pokemon.isOpponent("dragonair") and "x_speed" or "x_special"
			if not Strategies.prepare(xItem) then return false end
			local opp = Memory.value("battle", "opponent_id")
			-- (b) free Dragonair turn after X Speed: second X Special (only one X Special used so far, one left)
			-- v52: split off (DIAG9 #4: costs a turn in 23/27 Lance fights) -> only with LEAGUE_XSPECIAL2=true
			if LEAGUE_XSPECIAL2 and opp == DRAGONAIR and word(0x0FE6) > 0 and Pokemon.isDeployed("nidoking")
				and Inventory.count("x_speed") < st.ltXSpd0 and Inventory.count("x_special") == st.ltXSpc0 - 1
				and Inventory.count("x_special") > 0 then
				if not st.ltSpcLogged then
					st.ltSpcLogged = true
					print("refstrat LEAGUE_TACTIC Lance: second X Special on a free Dragonair turn (X Special "..Inventory.count("x_special")..", hp "..Combat.hp()..")")
				end
				Inventory.use("x_special", nil, true)
				return false
			end
			Battle.automate(opp == AERODACTYL and aerodactylMove(st) or nil)
		elseif st.foughtTrainer then
			return true
		end
	end
end

-- v55 RECORD-PACE GAMBLES (experiments/build-2026-10-16/yolo/REPORT.md; owner 16 Oct: "yolo" only on record pace).
-- Every tactic has its own default-off switch; with all off nothing below changes play. Reads: party/battle stats
-- and bag (as the engine), no play-time or RNG read; pace = the approved LCD-on tracker estimate (REFSTRAT_IGT_FRAMES).
do
	local Battle = require "action.battle"
	local Combat = require "ai.combat"
	local Inventory = require "storage.inventory"
	local Memory = require "util.memory"
	local Pokemon = require "storage.pokemon"
	local Menu = require "util.menu"
	local Input = require "util.input"
	local S = REFSTRAT_STRATEGIES
	local floor = math.floor
	local NIDOKING = 7
	local function word(a) return Memory.raw(a) * 256 + Memory.raw(a + 1) end
	local function nidoBase()
		local ni = Pokemon.indexOf("nidoking")
		if not ni or ni < 0 or Memory.raw(0x116B + 44 * ni) ~= NIDOKING then return nil end
		return 0x116B + 44 * ni, ni
	end

	-- PACE GATE. Targets = IGT (s) at the step in the fastest verified runs (rh52-1824711726 1:46:48 IGT finish,
	-- rh1-1824700964 v39): silphRival 3933.1 / 3946.6, Indigo depositPokemon 5829.0 / 5835.5, Lance prepareForLance
	-- 6128.8 / 6138.4, prepareForBlue 6221.7 / 6237.1 -> the faster run's value. The Silph gate runs at the battle start,
	-- 11.0-12.1 s after the silphRival step (65 test games: estimate - step IGT) -> target 3933 + 11 = 3944.
	REFSTRAT_PACE_TARGET = REFSTRAT_PACE_TARGET or {silph = 3944, indigo = 5829, lance = 6129, blue = 6222}
	REFSTRAT_ON_PACE = function(point)
		local target = REFSTRAT_PACE_TARGET[point]
		local c = REFSTRAT_CLOCK or {}
		local est = (c.lcd0 and not c.unreliable and REFSTRAT_IGT_FRAMES) and REFSTRAT_IGT_FRAMES() / 60 or nil
		local margin = YOLO_PACE_MARGIN or 10
		local ok = target ~= nil and est ~= nil and est <= target + margin
			and (YOLO_PACE_AHEAD == nil or est >= target - YOLO_PACE_AHEAD)
		print(string.format("refstrat PACE %s: IGT estimate %s vs target %s (%s), margin %s, ahead cap %s -> %s", point,
			est and string.format("%.1f", est) or "unsynced", tostring(target),
			(est and target) and string.format("%+.1f s", est - target) or "-", tostring(margin), tostring(YOLO_PACE_AHEAD),
			ok and "ON PACE" or "off pace"))
		return ok, (est and target) and est - target or nil
	end

	-- Gen 1 damage (pokered core.asm CalculateDamage + AdjustDamageForMoveType + RandomizeDamage): 39 non-critical
	-- rolls r = 217..255 and the base value. eff10 = type factor x 10 (20 = x2).
	local function dmgRolls(L, A, D, power, stab, eff10)
		if A > 255 or D > 255 then A = floor(A / 4); D = floor(D / 4) end
		if A < 1 then A = 1 end
		if D < 1 then D = 1 end
		local x = floor(floor(floor(2 * L / 5 + 2) * power * A / D) / 50)
		if x > 997 then x = 997 end
		x = x + 2
		if stab then x = x + floor(x / 2) end
		x = floor(x * eff10 / 10)
		local t = {}
		for r = 217, 255 do t[#t + 1] = (x >= 2) and floor(x * r / 255) or x end
		return t, x
	end
	REFSTRAT_DMG_ROLLS = dmgRolls
	local function isRed(h, mx)
		if mx > 255 then h, mx = floor(h / 4), floor(mx / 4) end
		local px = floor(h * 48 / mx)
		if px == 0 and h > 0 then px = 1 end
		return px < 10
	end
	REFSTRAT_IS_RED = isRed
	local RATIO = {[-2] = {50, 100}, [-1] = {66, 100}, [0] = {1, 1}, [1] = {15, 10}, [2] = {2, 1}, [3] = {25, 10}, [4] = {3, 1},
		[5] = {35, 10}, [6] = {4, 1}}
	local function staged(raw, s) local r = RATIO[math.min(6, s)]; return math.min(999, math.max(1, floor(raw * r[1] / r[2]))) end

	---------------------------------------------------------------------------------------------------------------
	-- (1) SILPH_RED. Rival (Squirtle file): Pidgeot 37, Gyarados 38, Growlithe 35, Alakazam 35, Venusaur 40; RIVAL2
	-- move_choices 1,3 -> against Nidoking Gyarados always picks Hydro Pump (Water x2 on Ground, layer 3); 204/256 hit,
	-- crit 40/256 (base speed 81). Each "stall" turn (Poke Flute = no effect; X Special; Potion; Super Potion) gives
	-- Gyarados one Hydro Pump; the action whose hit most often leaves 1..red HP is used, while P(death | hit) <= crit +
	-- SILPH_RED_RISK (0.05); below SILPH_RED_MINP (0.5) red chance -> the old drill. After the hit: Horn Drill as before
	-- (X Accuracy + faster); Growlithe gets Horn Drill instead of a non-certain Rock Slide/BubbleBeam while red.
	local oldSilphRival = S.silphRival
	local function srLog(sr, msg) print("refstrat SILPH_RED: " .. msg) end
	local GYA_L, GYA_SPC = 38, 87                              -- Rival Gyarados (pokered; engine opponents.lua)
	local function hydro(hp, mx, D, rawSpc)
		local t = dmgRolls(GYA_L, GYA_SPC, D, 120, true, 20)
		local tc = dmgRolls(2 * GYA_L, GYA_SPC, rawSpc, 120, true, 20)
		local c = 40 / 256
		local die, red, cdie, cred, lo, hi = 0, 0, 0, 0, 999, -1
		for _, d in ipairs(t) do
			local h = hp - d
			if h <= 0 then die = die + 1 elseif isRed(h, mx) then red = red + 1; lo = math.min(lo, h); hi = math.max(hi, h) end
		end
		for _, d in ipairs(tc) do
			local h = hp - d
			if h <= 0 then cdie = cdie + 1 elseif isRed(h, mx) then cred = cred + 1 end
		end
		return c * cdie / 39 + (1 - c) * die / 39, c * cred / 39 + (1 - c) * red / 39, lo, hi, t[1], t[39]
	end
	-- best Gyarados stall for (hp, stage s) with bag counts xs / pot / sup; returns action ("drill" = no setup), txt
	local function bestStall(hp, mx, s, R, xs, pot, sup)
		local D = staged(R, s)
		local opts = {{"pokeflute", hp, D}}
		if xs > (SILPH_RED_XSPC_KEEP or 1) and s < 6 then opts[#opts + 1] = {"x_special", hp, staged(R, s + 1)} end
		if pot >= 1 and hp < mx then opts[#opts + 1] = {"potion", math.min(mx, hp + 20), D} end
		if sup > (SILPH_RED_SUPER_KEEP or 2) and hp < mx then opts[#opts + 1] = {"super_potion", math.min(mx, hp + 50), D} end
		local best, txt = nil, {}
		local cap = 40 / 256 + (SILPH_RED_RISK or 0.05)
		for _, o in ipairs(opts) do
			local pd, pr, lo, hi, dmin, dmax = hydro(o[2], mx, o[3], R)
			txt[#txt + 1] = string.format("%s(hp %d spc %d: hit %d-%d, death %.3f red %.3f [%d..%d])", o[1], o[2], o[3], dmin, dmax, pd, pr, lo, hi)
			if pd <= cap + 1e-9 and (not best or pr > best.pr + 1e-9) then best = {item = o[1], pr = pr, pd = pd} end
		end
		return (best and best.pr >= (SILPH_RED_MINP or 0.5)) and best.item or "drill", table.concat(txt, "; ")
	end
	local function bag() return Inventory.count("x_special"), Inventory.count("potion"), Inventory.count("super_potion") end
	local function srDecide(sr)
		local base = nidoBase()
		local hp, mx, D = word(0x1015), word(0x1023), word(0x102B)
		local R = word(base + 42)
		local s = 0
		for k = 0, 6 do if staged(R, k) == D then s = k; break end end
		local act, txt = bestStall(hp, mx, s, R, bag())
		srLog(sr, string.format("Gyarados hp %d/%d Special %d (raw %d, stage %+d; Gyarados L%d Special %d), HD PP %d -> %s; %s", hp, mx, D, R, s,
			Memory.raw(0x0FF3), word(0x0FFC), Battle.pp("horn_drill"), act, txt))
		return act
	end
	-- Pidgeot turn 3 (X Accuracy + X Speed used). Pidgeot L37 (Sand-Attack / Quick Attack / Whirlwind / Wing Attack,
	-- uniform: nothing is encouraged against Nidoking) acts once more if we use X Special now. Success = P(the Gyarados
	-- stall then lands red), enumerated over Pidgeot's moves, rolls and crits (45/256); X Special now if that is >=
	-- SILPH_RED_MINP and >= the success of drilling now (X Special as the Gyarados stall), and the Pidgeot turn cannot
	-- kill (<= 1%); else drill now if that succeeds often enough; else no setup (the old line).
	local function pidgeotPlan(sr)
		local base = nidoBase()
		local hp, mx, R, Rdef = word(0x1015), word(0x1023), word(base + 42), word(base + 38)
		local A, L, Dd = word(0x0FF6), Memory.raw(0x0FF3), word(0x1027)
		local xs, pot, sup = bag()
		local cache = {}
		local function succ(h)
			if h <= 0 then return 0 end
			if cache[h] == nil then
				local act = bestStall(h, mx, 1, R, xs - 1, pot, sup)
				local pr = 0
				if act ~= "drill" then
					local D = staged(R, 1)
					local hh, ss = h, 1
					if act == "x_special" then ss = 2 elseif act == "potion" then hh = math.min(mx, h + 20) elseif act == "super_potion" then hh = math.min(mx, h + 50) end
					local _, prr = hydro(hh, mx, staged(R, ss), R)
					pr = prr
				end
				cache[h] = pr
			end
			return cache[h]
		end
		local c = 45 / 256
		local sx, death = 0.5 * succ(hp), 0
		for _, mv in ipairs({40, 35}) do                       -- Quick Attack, Wing Attack (STAB)
			local t = dmgRolls(L, A, Dd, mv, true, 10)
			local tc = dmgRolls(2 * L, A, Rdef, mv, true, 10)
			for _, d in ipairs(t) do sx = sx + 0.25 * (1 - c) / 39 * succ(hp - d); if d >= hp then death = death + 0.25 * (1 - c) / 39 end end
			for _, d in ipairs(tc) do sx = sx + 0.25 * c / 39 * succ(hp - d); if d >= hp then death = death + 0.25 * c / 39 end end
		end
		local a0 = bestStall(hp, mx, 0, R, xs, pot, sup)
		local s0 = 0
		if a0 ~= "drill" then
			local hh, ss = hp, 0
			if a0 == "x_special" then ss = 1 elseif a0 == "potion" then hh = math.min(mx, hp + 20) elseif a0 == "super_potion" then hh = math.min(mx, hp + 50) end
			local _, prr = hydro(hh, mx, staged(R, ss), R)
			s0 = prr
		end
		local minp = SILPH_RED_MINP or 0.5
		local plan = "none"
		if xs >= 2 and death <= 0.01 and sx >= minp and sx >= s0 then plan = "x_special" elseif s0 >= minp then plan = "drill" end
		srLog(sr, string.format("Pidgeot turn 3 hp %d/%d: X Special now -> P(red setup) %.3f (Pidgeot-turn death %.4f); drill now (%s stall) -> %.3f => %s",
			hp, mx, sx, death, a0, s0, plan == "x_special" and "X Special now" or (plan == "drill" and "drill now (stall at Gyarados)" or "NO SETUP (old line)")))
		return plan
	end
	S.silphRival = function(data)
		if not SILPH_RED then return oldSilphRival(data) end
		local st = Strategies.status
		if Memory.value("game", "battle") ~= 2 then return oldSilphRival(data) end
		local sr = st.v55sr
		if not sr then
			sr = {}
			st.v55sr = sr
			local on = REFSTRAT_ON_PACE("silph")
			sr.active = on and Inventory.contains("pokeflute") ~= nil and Inventory.count("x_special") >= 1 and nidoBase() ~= nil
			srLog(sr, (sr.active and "setup ACTIVE" or "inactive") .. string.format(" (on pace %s, flute %s, X Special %d)",
				tostring(on), tostring(Inventory.contains("pokeflute") ~= nil), Inventory.count("x_special")))
		end
		if not sr.active then return oldSilphRival(data) end
		local opp = Battle.opponent()
		if opp == "pidgeot" and sr.pidgeotSpc ~= false and Strategies.isPrepared("x_accuracy", "x_speed") and word(0x0FE6) > 0 then
			if sr.pidgeotSpc == nil then
				local plan = pidgeotPlan(sr)
				sr.pidgeotSpc = plan == "x_special"
				if plan == "none" then sr.active = false; return oldSilphRival(data) end
			end
			if sr.pidgeotSpc and not Strategies.prepare("x_special") then return false end
		end
		if opp == "gyarados" and not sr.done and word(0x0FE6) > 0 and Pokemon.isDeployed("nidoking") then
			local hp = word(0x1015)
			if not sr.peak then
				sr.peak, sr.f0 = hp, emu.framecount()
				local faster = word(0x1029) > word(0x0FFA)
				if not (Combat.xAccuracy() and faster and Battle.pp("horn_drill") >= 3) then
					sr.done = true
					srLog(sr, string.format("no setup (X Accuracy %s, faster %s, HD PP %d < 3)", tostring(Combat.xAccuracy()), tostring(faster), Battle.pp("horn_drill")))
					return oldSilphRival(data)
				end
			end
			if hp < sr.peak then
				sr.done = true
				srLog(sr, string.format("HIT: hp %d -> %d/%d (%s) after %d frames, %d stall action(s)", sr.peak, hp, word(0x1023),
					isRed(hp, word(0x1023)) and "RED" or "not red", emu.framecount() - sr.f0, sr.n or 0))
				sr.red = isRed(hp, word(0x1023))
				return oldSilphRival(data)
			end
			if emu.framecount() - sr.f0 > (SILPH_RED_MAXF or 3000) then
				sr.done = true
				srLog(sr, "stall cap reached -> drill")
				return oldSilphRival(data)
			end
			sr.peak = math.max(sr.peak, hp)
			if Menu.onBattleSelect() and Memory.value("menu", "row") ~= nil then
				local key = hp .. ":" .. word(0x102B) .. ":" .. Inventory.count("potion") .. ":" .. Inventory.count("super_potion") .. ":" .. Inventory.count("x_special")
				if key ~= sr.key then sr.key = key; sr.act = srDecide(sr); sr.n = (sr.n or 0) + (sr.act ~= "drill" and 1 or 0) end
			end
			if sr.act == "drill" then
				sr.done = true
				return oldSilphRival(data)
			end
			if sr.act then
				Inventory.use(sr.act, nil, true)
				return false
			end
			Input.cancel()   -- text before the first menu
			return false
		end
		if sr.red and opp == "growlithe" and word(0x0FE6) > 0 and Combat.xAccuracy() and Battle.pp("horn_drill") >= 3 then
			local ours, enemy = Combat.activePokemon()
			local sure = false
			for _, mv in ipairs(ours.moves or {}) do
				if mv.name == "Rock-Slide" and Battle.pp("rock_slide") > 0 then
					local lo = Combat.calcRange(mv, ours, enemy)
					sure = lo >= enemy.hp
				end
			end
			if not sure and word(0x1029) > word(0x0FFA) then
				if not sr.growLog then sr.growLog = true; srLog(sr, "red: Growlithe without a sure Rock Slide KO -> Horn Drill") end
				Battle.automate("horn_drill")
				return false
			end
		end
		return oldSilphRival(data)
	end

	---------------------------------------------------------------------------------------------------------------
	-- (2) CHAMP_NO_FR. Champion Pidgeot (RIVAL3 move_choices 1,3, nothing super effective): Whirlwind / Wing Attack /
	-- Sky Attack / Mirror Move uniform; Mirror Move and Whirlwind fail, Sky Attack charges (S.blue drills first). It acts
	-- on our X Accuracy and X Speed turns; if it charges on turn 1, Alakazam (faster) gets one turn (Psychic / Psybeam,
	-- both encouraged). Risk below = exact roll enumeration of those turns, printed for no-FR and FR.
	local oldPrepareForBlue = S.prepareForBlue
	local function champRisk(hp, base)
		local Rdef, Rspc = word(base + 38), word(base + 42)
		local D = Rdef + floor(Rdef / 8)                      -- Thunder Badge
		local wa, waMax = dmgRolls(61, 113, D, 35, true, 10)
		local wac = dmgRolls(122, 113, Rdef, 35, true, 10)
		local cP = 45 / 256                                    -- Pidgeot base speed 91
		local S2 = Rspc + floor(Rspc / 8)                     -- Volcano Badge
		local psy = dmgRolls(59, 173, S2, 90, true, 20)
		local psb = dmgRolls(59, 173, S2, 65, true, 20)
		local cA = 60 / 256                                    -- Alakazam base speed 120
		local psyc = dmgRolls(118, 173, Rspc, 90, true, 20)
		local psbc = dmgRolls(118, 173, Rspc, 65, true, 20)
		local function share(t, h) local n = 0; for _, d in ipairs(t) do if d >= h then n = n + 1 end end; return n / 39 end
		local function waDie(h) return cP * share(wac, h) + (1 - cP) * share(wa, h) end
		-- distribution after one Wing Attack (hit 255/256): list of {h, p}
		local function afterWA(h)
			local out = {}
			for _, d in ipairs(wa) do out[#out + 1] = {h - d, (1 - cP) / 39} end
			for _, d in ipairs(wac) do out[#out + 1] = {h - d, cP / 39} end
			return out
		end
		local alakazamDie = 0.5 * (cA * share(psyc, hp) + (1 - cA) * share(psy, hp)) + 0.5 * (cA * share(psbc, hp) + (1 - cA) * share(psb, hp))
		local die = 0.25 * alakazamDie                         -- turn 1 Sky Attack charge -> Alakazam's turn at hp
		local t1 = afterWA(hp)                                 -- turn 1 Wing Attack (1/4)
		for _, o in ipairs(t1) do
			if o[1] <= 0 then die = die + 0.25 * o[2] else die = die + 0.25 * o[2] * 0.25 * waDie(o[1]) end
		end
		die = die + 0.5 * 0.25 * waDie(hp)                     -- turn 1 no damage (Whirlwind / Mirror Move), turn 2 WA
		return die, waMax
	end
	-- v58 r2: corrected free-turn death risk for target mode only (Sol review 1 #5). pokered: ItemUseXStat ->
	-- StatModifierUpEffect re-applies the badge boosts (engine/battle/effects.asm), so after the X Speed (turn 2) our
	-- Defense / Special carry the badge boost twice; X Accuracy sets a flag only (turn 1 Wing Attack: one boost). In-battle
	-- level-up (after the Pidgeot KO) recalculates and applies the badge boost once, then the X Speed turn re-applies it.
	-- Rival3 AI mod 3 encourages every Psychic-type move vs Nidoking: Psychic, Psybeam AND Reflect (harmless) -> 1/3 each.
	-- Crits use the unmodified stats. Wing Attack hit chance 255/256.
	-- r3 (Sol review 2 #5): the Sky Attack branch KOs Pidgeot first; its EXP (pokered: base 172 x L61 / 7, x 1.5 trainer =
	-- 2247) can level Nidoking (medium-slow growth) before Alakazam acts: new max HP adds to current HP, Special is
	-- recalculated (CalcStat with DVs and stat EXP) and gets the badge boost again; Psychic / Psybeam hit 255/256.
	local function medSlow(n) return floor(6 * n * n * n / 5) - 15 * n * n + 100 * n - 140 end
	local function calcStat(L, b, dv, se, isHP)
		local r = 0
		while r * r < se and r < 255 do r = r + 1 end            -- pokered CalcStat: smallest r with r^2 >= stat EXP
		local v = floor(((b + dv) * 2 + floor(r / 4)) * L / 100)
		return isHP and v + L + 10 or v + 5
	end
	local function afterPidgeot(hp, base)
		local L = Memory.raw(base + 33)
		local exp = Memory.raw(base + 14) * 65536 + Memory.raw(base + 15) * 256 + Memory.raw(base + 16)
		local Rspc = word(base + 42)
		if L >= 100 or exp + 2247 < medSlow(L + 1) then return hp, Rspc, false end
		local d1, d2 = Memory.raw(base + 27), Memory.raw(base + 28)
		local aD, dD, sD, cD = floor(d1 / 16), d1 % 16, floor(d2 / 16), d2 % 16
		local hD = (aD % 2) * 8 + (dD % 2) * 4 + (sD % 2) * 2 + (cD % 2)
		local hpSE, spcSE = word(base + 17), word(base + 25)
		local gain = calcStat(L + 1, 81, hD, hpSE, true) - calcStat(L, 81, hD, hpSE, true)
		return hp + gain, calcStat(L + 1, 75, cD, spcSE, false), true
	end
	REFSTRAT_CHAMP_AFTER_PIDGEOT = afterPidgeot
	local function champRisk2(hp, base)
		local Rdef = word(base + 38)
		local function badge(x) x = x + floor(x / 8); return x > 999 and 999 or x end
		local D1, D2 = badge(Rdef), badge(badge(Rdef))
		local wa1 = dmgRolls(61, 113, D1, 35, true, 10)
		local wa2 = dmgRolls(61, 113, D2, 35, true, 10)
		local wac = dmgRolls(122, 113, Rdef, 35, true, 10)
		local cP, hit = 45 / 256, 255 / 256
		local hpA, Rspc = afterPidgeot(hp, base)                -- Alakazam's turn: state after the Pidgeot KO
		local S2 = badge(badge(Rspc))
		local psy, psb = dmgRolls(59, 173, S2, 90, true, 20), dmgRolls(59, 173, S2, 65, true, 20)
		local cA = 60 / 256
		local psyc, psbc = dmgRolls(118, 173, Rspc, 90, true, 20), dmgRolls(118, 173, Rspc, 65, true, 20)
		local function share(t, h) local n = 0; for _, d in ipairs(t) do if d >= h then n = n + 1 end end; return n / 39 end
		local function waDie(h, wa) return hit * (cP * share(wac, h) + (1 - cP) * share(wa, h)) end
		local alakazamDie = hit * ((cA * share(psyc, hpA) + (1 - cA) * share(psy, hpA)) / 3 + (cA * share(psbc, hpA) + (1 - cA) * share(psb, hpA)) / 3)
		local die = 0.25 * alakazamDie                         -- turn 1 Sky Attack charge -> Drill, Alakazam's free turn
		for _, d in ipairs(wa1) do                             -- turn 1 Wing Attack (1/4), then turn 2 Wing Attack (1/4)
			local h = hp - d
			if h <= 0 then die = die + 0.25 * hit * (1 - cP) / 39 else die = die + 0.25 * hit * (1 - cP) / 39 * 0.25 * waDie(h, wa2) end
		end
		for _, d in ipairs(wac) do
			local h = hp - d
			if h <= 0 then die = die + 0.25 * hit * cP / 39 else die = die + 0.25 * hit * cP / 39 * 0.25 * waDie(h, wa2) end
		end
		die = die + 0.25 * (1 - hit) * 0.25 * waDie(hp, wa2)    -- turn 1 Wing Attack missed
		die = die + 0.5 * 0.25 * waDie(hp, wa2)               -- turn 1 Whirlwind / Mirror Move, turn 2 Wing Attack
		return die
	end
	REFSTRAT_CHAMP_RISK2 = champRisk2
	S.prepareForBlue = function(data)
		local st = Strategies.status
		if CHAMP_NO_FR and st.v55c == nil then
			st.v55c = "old"
			local base = nidoBase()
			if base then
				local hp, mx = Combat.hp(), Combat.maxHP()
				local riskNo, waMax = champRisk(hp, base)
				local riskFR = champRisk(mx, base)
				local min = CHAMP_NO_FR_MIN or 22
				local hd = Pokemon.pp(floor((base - 0x116B) / 44), "horn_drill") or 0
				local items = Inventory.count("x_accuracy") >= 1 and Inventory.count("x_speed") >= 1
				local why
				if hp >= mx then why = "full HP"
				elseif hd < 6 then why = "Horn Drill PP " .. hd .. " < 6 (Venusaur would act)"
				elseif not items then why = "no X Accuracy / X Speed"
				end
				local on
				if CHAMP_TARGET then   -- v58: real-time target instead of the v55 IGT pace window + risk cap
					if not why then
						-- the action the code below would take: skip at this HP, or the Potion into the band
						local act, hpAct, save
						if hp >= min then act, hpAct, save = "skip", hp, CHAMP_NO_FR_SAVE or 12
						elseif Inventory.count("potion") >= 1 and hp + 20 >= min and isRed(hp + 20, mx) then
							act, hpAct, save = "potion", math.min(hp + 20, mx), CHAMP_POTION_SAVE or 4
						end
						if not Inventory.contains("full_restore") then
							if MANSION_FR_SKIP and act then   -- v59: nothing to compare against -> the skip / Potion branch
								on = true
								print("refstrat v59 MANSION_FR_SKIP: no Full Restore left at the Champion, hp " .. hp .. "/" .. mx .. " -> " .. act)
							else why = "no Full Restore (target gate compares against it)" end
						elseif not act then why = "below band, no Potion"
						else on, why = REFSTRAT_CHAMP_TARGET_GATE(champRisk2(hpAct, base), champRisk2(mx, base), save, act) end
					end
				else
					on = (not why) and REFSTRAT_ON_PACE("blue")
					if not why and not on then why = "off pace" end
				end
				if not why and not CHAMP_TARGET and riskNo - riskFR > (CHAMP_NO_FR_RISK or 0.05) then
					why = string.format("extra death %.3f > cap %.2f", riskNo - riskFR, CHAMP_NO_FR_RISK or 0.05)
				end
				if not why then
					if hp >= min then st.v55c = "skip"
					elseif Inventory.count("potion") >= 1 and hp + 20 >= min and isRed(hp + 20, mx) then st.v55c = "potion"; st.v55min = min end
				end
				print(string.format("refstrat CHAMP_NO_FR: hp %d/%d (red %s), max non-crit Wing Attack %d, band >= %d, HD PP %d, X Acc %d, X Spd %d; "
					.. (CHAMP_TARGET and "legacy v55 helper (not used in target mode) " or "") .. "death risk (Pidgeot/Alakazam free turns) no-FR %.3f vs FR %.3f -> %s", hp, mx, tostring(isRed(hp, mx)), waMax, min, hd,
					Inventory.count("x_accuracy"), Inventory.count("x_speed"), riskNo, riskFR,
					st.v55c == "skip" and "SKIP the Full Restore" or (st.v55c == "potion" and "Potion into the band" or ("Full Restore as before" .. (why and (" (" .. why .. ")") or "")))))
			end
		end
		if st.v55c == "skip" then return Menu.close() end
		if st.v55c == "potion" then
			if Combat.hp() >= st.v55min or Inventory.count("potion") == 0 then return Menu.close() end
			return Strategies.functions.potion({hp = st.v55min, forced = "potion", chain = true})
		end
		return oldPrepareForBlue(data)
	end

	---------------------------------------------------------------------------------------------------------------
	-- (3) YOLO_LORELEI. Lorelei (move_choices 1,2,3): Dewgong L54 Growl / Aurora Beam / Rest / Take Down; on turn 1
	-- (layer-2 counter 0) only Aurora Beam is encouraged (Ice x2 on Ground) -> it is always the move. Yolo = Nidoking
	-- leads, X Accuracy while Aurora Beam hits, Horn Drill x5. Allowed only if hp > max non-crit Aurora Beam (death =
	-- crit 35/256 only); the Indigo PC deposits the bird too and the bird menu is skipped.
	local oldDeposit = S.depositPokemon
	local function auroraMax(base)
		local R = word(base + 42)
		local t, x = dmgRolls(54, 116, R + floor(R / 8), 65, true, 20)
		local tc = dmgRolls(108, 116, R, 65, true, 20)
		return t[39], tc[1], tc[39]
	end
	S.depositPokemon = function(data)
		local st = Strategies.status
		if YOLO_LORELEI and st.v55y == nil then
			st.v55y = false
			local base, ni = nidoBase()
			if base and Pokemon.inParty("pidgey", "pidgeotto", "spearow", "fearow") then
				local hp = word(base + 1)
				local amax, cmin, cmax = auroraMax(base)
				local hd = Pokemon.pp(ni, "horn_drill") or 0
				local ok = hp > amax and hd >= 5 and Inventory.count("x_accuracy") >= 1
				local on = ok and REFSTRAT_ON_PACE("indigo")
				st.v55y = ok and on
				print(string.format("refstrat YOLO_LORELEI: Nidoking hp %d, Aurora Beam max %d (crit %d-%d, crit rate 35/256), HD PP %d -> %s",
					hp, amax, cmin, cmax, hd, st.v55y and "YOLO: deposit the bird, Nidoking leads" or (ok and "off pace: standard" or "standard (hp/PP)")))
				if st.v55y then REFSTRAT_YOLO_LORELEI_ON = true; st.toSize = 1 end
			end
		end
		return oldDeposit(data)
	end
	local oldPlan = REFSTRAT_LEAGUE_PLAN
	REFSTRAT_LEAGUE_PLAN = function()
		local ok, why = oldPlan()
		if ok or not REFSTRAT_YOLO_LORELEI_ON then return ok, why end
		local reasons = why:match("%[unavailable: (.*)%]") or ""
		for r in reasons:gmatch("[^;]+") do
			if not r:find("bird") then return ok, why end
		end
		local hd = tonumber(why:match("HD PP (%d+)")) or 0
		REFSTRAT_LEAGUE_TOPUP = hd < 5
		return true, why .. " [YOLO_LORELEI: no bird needed]"
	end
	local oldLorelei = S.lorelei
	S.lorelei = function(data)
		if not REFSTRAT_YOLO_LORELEI_ON or REFSTRAT_BIRD_SWAPPED() then return oldLorelei(data) end
		local st = Strategies.status
		if Strategies.trainerBattle() then
			if not st.v55log then st.v55log = true; print("refstrat YOLO_LORELEI: Nidoking leads, hp " .. Combat.hp()) end
			if Strategies.prepare("x_accuracy") then
				local forced
				if Battle.opponent() == "jinx" and Battle.pp("horn_drill") <= 1 then forced = "earthquake" end
				Battle.automate(forced)
			end
		elseif st.foughtTrainer then
			return true
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- (4) YOLO_LANCE. Lance's Gyarados (move_choices 1,3) always Hydro Pumps; without X Special its max non-crit hit
	-- (~194 vs Special 122) exceeds Nidoking's max HP, so the standard needs X Special + hp >= target (prepareForLance).
	-- Yolo (only when that heal would be needed): no heal, Horn Drill (76/256, Nidoking faster) until Gyarados dies;
	-- X Special then moves to the first Dragonair (Agility-only turns). P(live) = p/(1-(1-p)(1-h)) = 0.35.
	local oldPrepareForLance = S.prepareForLance
	S.prepareForLance = function(data)
		local st = Strategies.status
		if YOLO_LANCE and st.v55l == nil then
			st.v55l = false
			local hp, mx = Combat.hp(), Combat.maxHP()         -- same target as S.prepareForLance (no side effects)
			local target = math.min(mx, Combat.healthFor("LanceGyarados") + 1)
			local lt = REFSTRAT_LT_TARGET and REFSTRAT_LT_TARGET()
			if lt and math.min(mx, lt) > target then target = math.min(mx, lt) end
			if hp < target then
				local on = REFSTRAT_ON_PACE("lance")
				st.v55l = on and Battle.pp("horn_drill") >= 1
				print(string.format("refstrat YOLO_LANCE: hp %d < target %d -> %s", hp, target, st.v55l and "YOLO: no heal, Horn Drill Gyarados" or "heal as before"))
				REFSTRAT_YOLO_LANCE_ON = st.v55l or nil
			end
		end
		if st.v55l then return true end                       -- refCloseMenu closes the open PP menu
		return oldPrepareForLance(data)
	end
	local oldLance = S.lance
	S.lance = function(data)
		if not REFSTRAT_YOLO_LANCE_ON then return oldLance(data) end
		local st = Strategies.status
		if Memory.value("game", "battle") == 2 then
			local opp = Battle.opponent()
			if opp == "gyarados" and word(0x0FE6) > 0 and Pokemon.isDeployed("nidoking") and Battle.pp("horn_drill") > 0
				and word(0x1029) > word(0x0FFA) then
				if not st.v55drill then st.v55drill = true; print("refstrat YOLO_LANCE: Horn Drill Gyarados, hp " .. word(0x1015)) end
				Battle.automate("horn_drill")
				return false
			end
			if opp == "dragonair" and word(0x0FE6) > 0 and Pokemon.isDeployed("nidoking") and not st.v55spc then
				if Strategies.prepare("x_special") then st.v55spc = true else return false end
			end
		end
		return oldLance(data)
	end
	print("Upgrade loaded: v55 record-pace gambles (SILPH_RED " .. tostring(SILPH_RED) .. ", CHAMP_NO_FR " .. tostring(CHAMP_NO_FR)
		.. ", YOLO_LORELEI " .. tostring(YOLO_LORELEI) .. ", YOLO_LANCE " .. tostring(YOLO_LANCE) .. ", margin " .. tostring(YOLO_PACE_MARGIN) .. ")")
end

-- v58 TARGET-AWARE CHAMPION GAMBLE (experiments/target-policy-2026-10-17/make_v58.py; owner 17 Oct: "beat our best").
-- Default off (CHAMP_TARGET nil = v57). Stopwatch = emulator frames since the LiveSplit start (harness timer start).
do
	local FPS = 4194304 / 70224
	local prevStart = Bridge.liveSplit
	Bridge.liveSplit = function()
		if not REFSTRAT_T0 then REFSTRAT_T0 = emu.framecount() end
		return prevStart()
	end
	REFSTRAT_ELAPSED = function()
		if not REFSTRAT_T0 then return nil end
		return (emu.framecount() - REFSTRAT_T0) / FPS
	end
	local function phi(z)   -- standard normal CDF (Abramowitz-Stegun 26.2.17, |error| < 7.5e-8)
		local t = 1 / (1 + 0.2316419 * math.abs(z))
		local y = 0.3989422804 * math.exp(-z * z / 2) * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
		return z >= 0 and 1 - y or y
	end
	REFSTRAT_CHAMP_TARGET_GATE = function(riskNo, riskFR, save, act)
		local el = REFSTRAT_ELAPSED()
		if not el then
			print("refstrat v58 CHAMP_TARGET: no stopwatch -> Full Restore")
			return false, "no stopwatch"
		end
		local budget = CHAMP_TARGET - el
		local mu, sd, sdNo = CHAMP_REMAIN_FR or 181.2, CHAMP_REMAIN_SD or 3.0, CHAMP_SKIP_SD or 5.0
		local pFR = (1 - riskFR) * phi((budget - mu) / sd)
		local pNo = (1 - riskNo) * phi((budget - mu + save) / sdNo)
		local on = pNo > pFR
		print(string.format("refstrat v58 CHAMP_TARGET: real %.2f s, target %.2f, budget %.2f s; P(beat) Full Restore %.4f "
			.. "(remaining %.1f+-%.1f, death %.3f) vs %s %.4f (-%.0f s +-%.1f, death %.3f) -> %s", el, CHAMP_TARGET, budget, pFR, mu, sd,
			riskFR, act, pNo, save, sdNo, riskNo, on and "GAMBLE" or "Full Restore"))
		return on, (not on) and string.format("target: P %.4f <= %.4f", pNo, pFR) or nil
	end
	print("Upgrade loaded: v58 target-aware Champion gamble (CHAMP_TARGET " .. tostring(CHAMP_TARGET) .. ")")
end

-- v58 SHIP_IT_GAMBLE_HP (owner 17 Oct: may read the instant-text flag; rival/RESEARCH.md): with SHIP_FIRST, at the S.S.
-- Anne rival Potion step, skip the Potion while the Bike Shop instant text is still on (wStatusFlags5 bit 6, 0xD730) and
-- HP >= SHIP_IT_GAMBLE_HP (e.g. 30; the step's own target stays SHIP_POTION_HP = 40). A Potion opens the START menu and
-- ends instant text (~20 s of slow text in the fight + captain). Gamble: v57 deaths entering at 30-39 HP 10/40.
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local prevPotion = S.potion
	S.potion = function(data)
		if SHIP_IT_GAMBLE_HP and data and data.refShipIT then
			local st = Strategies.status
			if st.shipIT == nil then
				local it = bit.band(memory.readbyte(0x1730), 0x40) ~= 0
				local hp = Combat.hp()
				st.shipIT = it and hp < (data.hp or 0) and hp >= SHIP_IT_GAMBLE_HP
				print("refstrat v58 SHIP_IT_GAMBLE_HP: instant text " .. tostring(it) .. ", hp " .. hp .. ", step target " .. tostring(data.hp)
					.. ", floor " .. SHIP_IT_GAMBLE_HP .. " -> " .. (st.shipIT and "SKIP the Potion (keep instant text)" or "as before"))
			end
			if st.shipIT then return true end
		end
		return prevPotion(data)
	end
end

-- v62 IT_REFRESH (experiments/ship-it-2026-10-17): {s="refBikeRefresh"} on Cerulean map 3 at (19,18), after the
-- optional Center/Mart. If the instant-text flag (wStatusFlags5 bit 6, read only; owner-approved 17 Oct) is off:
-- walk (16,18) (16,26) (13,26) into the Bike Shop, talk to the clerk and leave the BICYCLE menu with B (as
-- refBikeClerk), walk back to (19,18). Flag on (no Center / Mart) or switch unset: nothing happens.
do
	local S = REFSTRAT_STRATEGIES
	local Player = require "util.player"
	local Walk = require "action.walk"
	local Textbox = require "action.textbox"
	local Input = require "util.input"
	local Menu = require "util.menu"
	local Memory = require "util.memory"
	local function walk(st, key, points)
		local px, py = Player.position()
		st[key] = st[key] or 1
		while points[st[key]] and px == points[st[key]][1] and py == points[st[key]][2] do st[key] = st[key] + 1 end
		local wp = points[st[key]]
		if not wp then return true end
		if px ~= wp[1] then Walk.step(wp[1], py) else Walk.step(px, wp[2]) end
		return false
	end
	local function it() return bit.band(memory.readbyte(0x1730), 0x40) ~= 0 end
	S.refBikeRefresh = function(data)
		local st = Strategies.status
		if st.need == nil then
			st.need = IT_REFRESH and not it()
			print("refstrat v62 IT_REFRESH (" .. tostring(data.at) .. "): instant text " .. tostring(it()) .. " -> "
				.. (st.need and "Bike Shop clerk again" or "nothing to do"))
		end
		if not st.need then return true end
		local map = Memory.value("game", "map")
		if map == 3 then
			if not st.talked then
				if not Textbox.handle() then return false end
				walk(st, "to", {{16, 18}, {16, 26}, {13, 26}, {13, 25}})
			elseif walk(st, "back", {{16, 26}, {16, 18}, {19, 18}}) then
				print("refstrat v62 IT_REFRESH: back at (19,18), instant text " .. tostring(it()))
				return true
			end
		elseif map == 66 then
			if st.talked then
				walk(st, "out", {{4, 4}, {3, 4}, {3, 7}, {3, 8}})
			elseif not st.clerk then
				local px, py = Player.position()
				if not walk(st, "in", {{3, 4}, {4, 4}, {4, 2}}) then return false end
				if Textbox.isActive() then
					st.clerk, st.start = true, emu.framecount()
					return false
				end
				Player.interact("Right")
			else
				if Textbox.isActive() or Menu.isOpened() then
					st.idle = 0
					if emu.framecount() - st.start > 1800 then
						return Strategies.reset("error", "v62 Bike Shop clerk text did not close", nil, true)
					end
					Input.press("B", 2)
					return false
				end
				st.idle = (st.idle or 0) + 1
				if st.idle < 8 then return false end
				print("refstrat v62 IT_REFRESH: clerk talked, menu left with B; instant text " .. tostring(it())
					.. " after " .. (emu.framecount() - st.start) .. " frames")
				st.talked = true
			end
		end
		return false
	end
end

-- v63 risk switches (experiments/risk-v63-2026-10-17, owner 17 Oct: "V62 is play too safe. Make it more risky."; Sol
-- review SOL_RISK1.md ranks 1 and 3). Each switch runs one engine step with the original bot's yolo decision
-- (Control.yolo = true for that call only; RESET_FOR_TIME / BEAST_MODE stay off). Unset = v62 play.
-- R3_RISK: Shorts Kid fight - in-battle Potion only when the Rattata / Ekans can KO within 2 turns (engine
--   shortsKid yolo branch; also the engine's exact-lethal heal skip during that fight); Potion before the cocoons
--   only below 3 HP (was 6). The route block moves the Route 3 exit Potion from 20 to 14 HP.
-- SURGE_RISK: Potion before Lt. Surge only below 5 HP (was 20); at 6-21 HP no Potion (keep red HP through Surge).
do
	local S = REFSTRAT_STRATEGIES
	local Control = require "ai.control"
	local Combat = require "ai.combat"
	local function yoloStep(name, switch)
		local prev = S[name] or Strategies.functions[name]
		assert(prev, "v63: strategy " .. name .. " not found")
		S[name] = function(data)
			if not _G[switch] then return prev(data) end
			local st = Strategies.status
			if not st.v63log then
				st.v63log = true
				print("refstrat v63 " .. switch .. ": " .. name .. " with yolo decisions, hp " .. Combat.hp() .. "/" .. Combat.maxHP())
			end
			local y = Control.yolo
			Control.yolo = true
			local ok, r = pcall(prev, data)
			Control.yolo = y
			if not ok then error(r, 0) end
			return r
		end
	end
	yoloStep("shortsKid", "R3_RISK")
	yoloStep("potionBeforeCocoons", "R3_RISK")
	yoloStep("potionBeforeSurge", "SURGE_RISK")
	print("Upgrade loaded: v63 risk switches (R3_RISK " .. tostring(R3_RISK) .. ", SURGE_RISK " .. tostring(SURGE_RISK) .. ")")
end

-- v64 (experiments/v64-2026-10-18, owner 18 Oct: build Sol TIME2 gambles as switches, screen them first; owner risk
-- rule 18 Oct). Default off: unset = v63 play.
--   SHORTS_RISK : Potion before the Shorts Kid only at <= SHORTS_POTION_HP (default 10; v63: <= 24), and the Ekans
--                 Wrap Potion only below 8 HP (v63: below 14).
--   MANKEY_REDBAR: the Nugget Bridge Mankey red-bar setup (Poison Sting, let Mankey hit us into red HP for Route 25)
--                 also below level 23: at Nidoking level >= MANKEY_REDBAR_LV (default 20) and >= 2 Potions (v63: 23 / 4).
--   PARAS_RED   : see v64_route.lua (Route 3 exit Potion only at <= PARAS_RED_HP).
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local Control = require "ai.control"
	local Battle = require "action.battle"
	local Pokemon = require "storage.pokemon"
	local Inventory = require "storage.inventory"

	local prevShorts = S.potionBeforeShorts
	assert(prevShorts, "v64: potionBeforeShorts not found")
	S.potionBeforeShorts = function(data)
		if SHORTS_RISK then
			local st = Strategies.status
			if st.refShorts == nil then
				local hp, lim = Combat.hp(), SHORTS_POTION_HP or 10
				st.refShorts = (hp <= lim and hp > 0) and math.min(Combat.maxHP(), hp + 1) or false
				print("refstrat v64 SHORTS_RISK: before the Shorts Guy hp "..hp.."/"..Combat.maxHP().." floor "..lim.." -> "
					..(st.refShorts and "one Potion" or ((hp <= 24) and "no heal (v63 would heal)" or "no heal")))
			end
		end
		return prevShorts(data)
	end

	local prevScript = REFSTRAT_SCRIPT
	assert(prevScript, "v64: REFSTRAT_SCRIPT not found")
	REFSTRAT_SCRIPT = function(site, result, trigger, item, detail)
		if SHORTS_RISK and site == "shortsKid-wrap" and result and Combat.hp() >= 8 then
			print("refstrat v64 SHORTS_RISK: Wrap Potion skipped at hp "..Combat.hp().."/"..Combat.maxHP().." (v63 heals below 14)")
			return prevScript(site, false, false, item, tostring(detail).." v64-skip")
		end
		return prevScript(site, result, trigger, item, detail)
	end

	local prevRedbar = S.redbarMankey or Strategies.functions.redbarMankey
	assert(prevRedbar, "v64: redbarMankey not found")
	-- copy of engine/ai/red/strategies.lua redbarMankey with only the level / Potion gate changed
	S.redbarMankey = function(data)
		if not MANKEY_REDBAR then return prevRedbar(data) end
		local status = Strategies.status
		if Control.yolo then
			return true
		end
		local curr_hp, red_hp = Combat.hp(), Combat.redHP()
		if curr_hp <= red_hp then
			return true
		end
		if Strategies.trainerBattle() then
			local enemyMove, enemyTurns = Combat.enemyAttack()
			if enemyTurns then
				if enemyTurns < 2 then
					return true
				end
				local scratchDmg = enemyMove.damage
				if curr_hp - scratchDmg >= red_hp then
					return true
				end
			end
			Battle.automate("poison_sting")
		elseif status.foughtTrainer then
			return true
		end
		if Strategies.initialize() then
			local lv, n = Pokemon.info("nidoking", "level"), Inventory.count("potion")
			if lv < (MANKEY_REDBAR_LV or 20) or n < 2 then
				print("refstrat v64 MANKEY_REDBAR: level "..lv..", Potions "..n.." -> no red-bar setup")
				return true
			end
			print("refstrat v64 MANKEY_REDBAR: level "..lv..", Potions "..n..", hp "..curr_hp.."/"..Combat.maxHP().." (red "..red_hp..") -> Poison Sting red-bar setup"
				..(lv < 23 and " (v63 would skip it)" or ""))
		end
	end
	print("Upgrade loaded: v64 switches (SHORTS_RISK "..tostring(SHORTS_RISK)..", MANKEY_REDBAR "..tostring(MANKEY_REDBAR)..", PARAS_RED "..tostring(PARAS_RED)..")")
end

-- v65 (experiments/v65-2026-10-19, owner 19 Oct "Yes you may build v65 like that"). Finding: in 38% of v63-R3 runs
-- the bot swaps Pokemon after Pidgeotto's Sand-Attack in the Cerulean rival fight; the Pokemon menu turns instant text
-- off until after Bill (~73 s slower, 0 fast runs). experiments/misty-surge-audit-2026-10-19/REPORT.md.
-- Default off: unset = v64 play.
--   SAND_NO_SWAP     : in rivalSandAttack (Cerulean and S.S. Anne rival) the engine never sees "Sand-Attacked", so it
--                      never swaps in a sacrifice; Nidoking keeps attacking. Everything else in that strategy unchanged.
--   BRIDGE_IT_REFRESH: see v65_route.lua. If the instant-text flag (wStatusFlags5 bit 6, read only; owner OK 17 Oct)
--                      is off after the Cerulean rival, walk to the Bike Shop, talk to the clerk, leave the BICYCLE
--                      menu with B (as v62 refBikeRefresh), walk back to (21,6).
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local Battle = require "action.battle"
	local Player = require "util.player"
	local Walk = require "action.walk"
	local Textbox = require "action.textbox"
	local Input = require "util.input"
	local Menu = require "util.menu"
	local Memory = require "util.memory"

	local prevSand = S.rivalSandAttack or Strategies.functions.rivalSandAttack
	assert(prevSand, "v65: rivalSandAttack not found")
	S.rivalSandAttack = function(data)
		if not SAND_NO_SWAP then return prevSand(data) end
		local orig = Combat.sandAttacked
		local st = Strategies.status
		Combat.sandAttacked = function()
			local hit = orig()
			if hit and not st.v65sand then
				st.v65sand = true
				local opp = Battle.opponent()
				local would = opp == "raticate" or (opp == "pidgeotto" and select(2, Combat.bestMove()) == 1)
				print("refstrat v65 SAND_NO_SWAP: Sand-Attacked, opponent " .. tostring(opp) .. ", map " .. Memory.value("game", "map")
					.. " -> no swap, keep attacking" .. (would and " (v64 would swap)" or ""))
			end
			return false
		end
		local r = prevSand(data)
		Combat.sandAttacked = orig
		return r
	end

	local function walk(st, key, points)
		local px, py = Player.position()
		st[key] = st[key] or 1
		while points[st[key]] and px == points[st[key]][1] and py == points[st[key]][2] do st[key] = st[key] + 1 end
		local wp = points[st[key]]
		if not wp then return true end
		if px ~= wp[1] then Walk.step(wp[1], py) else Walk.step(px, wp[2]) end
		return false
	end
	local function it() return bit.band(memory.readbyte(0x1730), 0x40) ~= 0 end
	-- paths: the pre-Bridge Center path (refPreNuggetCenter) to (17,18), then the v62 refresh path to the Bike Shop
	local TO = {{21, 12}, {8, 12}, {8, 16}, {17, 16}, {17, 18}, {16, 18}, {16, 26}, {13, 26}, {13, 25}}
	local BACK = {{16, 26}, {16, 18}, {17, 18}, {17, 16}, {8, 16}, {8, 12}, {21, 12}, {21, 6}}
	S.refBikeRefreshBridge = function(data)
		local st = Strategies.status
		if st.need == nil then
			st.need = BRIDGE_IT_REFRESH and not it()
			print("refstrat v65 BRIDGE_IT_REFRESH: instant text " .. tostring(it()) .. " -> "
				.. (st.need and "Bike Shop clerk again" or "nothing to do"))
			if st.need then st.t0 = emu.framecount() end
		end
		if not st.need then return true end
		local map = Memory.value("game", "map")
		if map == 3 then
			if not st.talked then
				if not Textbox.handle() then return false end
				walk(st, "to", TO)
			elseif walk(st, "back", BACK) then
				print("refstrat v65 BRIDGE_IT_REFRESH: back at (21,6), instant text " .. tostring(it())
					.. ", detour " .. (emu.framecount() - st.t0) .. " frames")
				return true
			end
		elseif map == 66 then
			if st.talked then
				walk(st, "out", {{4, 4}, {3, 4}, {3, 7}, {3, 8}})
			elseif not st.clerk then
				if not walk(st, "in", {{3, 4}, {4, 4}, {4, 2}}) then return false end
				if Textbox.isActive() then
					st.clerk, st.start = true, emu.framecount()
					return false
				end
				Player.interact("Right")
			else
				if Textbox.isActive() or Menu.isOpened() then
					st.idle = 0
					if emu.framecount() - st.start > 1800 then
						return Strategies.reset("error", "v65 Bike Shop clerk text did not close", nil, true)
					end
					Input.press("B", 2)
					return false
				end
				st.idle = (st.idle or 0) + 1
				if st.idle < 8 then return false end
				print("refstrat v65 BRIDGE_IT_REFRESH: clerk talked, menu left with B; instant text " .. tostring(it())
					.. " after " .. (emu.framecount() - st.start) .. " frames")
				st.talked = true
			end
		end
		return false
	end
	print("Upgrade loaded: v65 switches (SAND_NO_SWAP " .. tostring(SAND_NO_SWAP) .. ", BRIDGE_IT_REFRESH " .. tostring(BRIDGE_IT_REFRESH) .. ")")
end

-- v66 (experiments/v66-2026-10-19, owner 19 Oct "implement the changes ... we have to play in red hp and just run with
-- that"). Why: experiments/silph-koga-audit-2026-10-19/REPORT.md - at red HP the low-HP alarm makes the game skip its
-- sound waits (home/delay.asm WaitForSoundToFinish); the WR runner is red from the Silph rival to Koga, the bot waits
-- ~65 s for sounds there. Default off: unset = v65 play.
--   RED_KEEP      : between Surge and Giovanni's gym (Thunder badge, no Earth badge), a field heal step (S.potion; not
--                   inside potionBeforeHypno, which has its own red-bar logic) is skipped while the HP bar is red (hp*48 < max*10) and
--                   hp >= RED_KEEP_MIN (default 8). In-battle survival heals are unchanged.
--   SNORLAX_REDBAR: Route 16 Snorlax (wild): before running, attack with a weak move (BubbleBeam, else Rock Slide) and
--                   let Snorlax hit Nidoking until the HP bar is red, while Snorlax cannot KO in one normal hit
--                   (Combat.enemyAttack turns >= 2), at most 40 s; then the old code runs away as before.
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local Control = require "ai.control"
	local Battle = require "action.battle"
	local Memory = require "util.memory"
	local Input = require "util.input"

	local function red(hp, mx) return hp > 0 and hp * 48 < mx * 10 end

	-- build 4: potionBeforeHypno keeps its own red-bar logic (Rare Candy loop + Headbutt target); RED_KEEP inside it
	-- soft-locked smoke game 1837005028 (build 3), so RED_KEEP is off while potionBeforeHypno runs.
	local inHypno = false
	local prevHypno = S.potionBeforeHypno or Strategies.functions.potionBeforeHypno
	assert(prevHypno, "v66: potionBeforeHypno not found")
	S.potionBeforeHypno = function(data)
		inHypno = true
		local r = prevHypno(data)
		inHypno = false
		return r
	end

	local prevPotion = S.potion
	assert(prevPotion, "v66: potion not found")
	S.potion = function(data)
		if RED_KEEP and not inHypno then
			local st = Strategies.status
			if st.v66red == nil then
				local hp, mx = Combat.hp(), Combat.maxHP()
				local b = memory.readbyte(0x1356)
				local window = bit.band(b, 0x04) ~= 0 and bit.band(b, 0x80) == 0
				local floor = RED_KEEP_MIN or 8
				st.v66red = window and red(hp, mx) and hp >= floor
				if window and red(hp, mx) then
					local tgt = data and (Control.yolo and data.yolo or data.hp)
					if type(tgt) == "string" then tgt = Combat.healthFor(tgt) end
					local would = type(tgt) == "number" and hp < tgt
					print("refstrat v66 RED_KEEP: hp " .. hp .. "/" .. mx .. " red, step target " .. tostring(tgt) .. ", floor " .. floor .. " -> "
						.. (st.v66red and ("no heal, keep red" .. (would and " (v65 would heal)" or "")) or "heal as before"))
				end
			end
			if st.v66red then return true end
		end
		return prevPotion(data)
	end

	local prevFlute = S.playPokeFlute or Strategies.functions.playPokeFlute
	assert(prevFlute, "v66: playPokeFlute not found")
	S.playPokeFlute = function(data)
		if SNORLAX_REDBAR and Battle.isActive() and Memory.value("game", "battle") == 1 then
			local st = Strategies.status
			if not st.v66done then
				st.v66t0 = st.v66t0 or emu.framecount()
				local el = emu.framecount() - st.v66t0
				local hp, mx = Combat.hp(), Combat.maxHP()
				local snorlax = memory.readbyte(0x0FE5) == 0x84   -- wEnemyMonSpecies, SNORLAX $84 (pokemon_constants.asm)
				local opp = snorlax and "snorlax" or tostring(memory.readbyte(0x0FE5))
				local turns = select(2, Combat.enemyAttack())
				if el < 2700 then
					if (not snorlax or turns == nil) and el < 300 then
						Input.cancel()   -- battle intro: wait until the game has loaded the opponent
						return false
					end
					if snorlax and hp > 0 and not red(hp, mx) and turns and turns >= 2 then
						if not st.v66log then
							st.v66log = true
							print("refstrat v66 SNORLAX_REDBAR: hp " .. hp .. "/" .. mx .. ", Snorlax needs " .. turns .. " hits -> take hits until red (v65 would run)")
						end
						local move = (Battle.pp("bubblebeam") > 0) and "bubblebeam" or "rock_slide"
						local orig = Control.shouldFight
						Control.shouldFight = function() return true end
						Battle.automate(move, true)
						Control.shouldFight = orig
						return false
					end
				end
				st.v66done = true
				print("refstrat v66 SNORLAX_REDBAR: stop at hp " .. hp .. "/" .. mx .. (red(hp, mx) and " (red)" or " (not red)")
					.. ", opponent " .. tostring(opp) .. ", turns to KO " .. tostring(turns) .. ", " .. string.format("%.1f", el / 59.7275) .. " s -> run as before")
			end
		end
		return prevFlute(data)
	end
	print("Upgrade loaded: v66 switches (RED_KEEP " .. tostring(RED_KEEP) .. ", SNORLAX_REDBAR " .. tostring(SNORLAX_REDBAR) .. ")")
end

-- v69 VOLTORB_RED (experiments/v69-2026-10-19, owner 19 Oct "yes lets do the voltorb setup"; Sol SOL_SURGE1.md).
-- Default off = v66 play. Why: both top humans play Route 9 -> Tower at red HP; our bot usually leaves Surge at
-- ~30/93 (experiments/surge-red-2026-10-19/REPORT.md, ../pokeguy-analysis-2026-10-19/REPORT.md).
-- Surge's Voltorb L21 knows SonicBoom (always 20 damage); after it, Pikachu has only Quick Attack and Raichu no move
-- that hurts Nidoking (reference/pokered data/trainers/parties.asm, base_stats, evos_moves).
-- Rule: against Voltorb, before it is damaged, if Nidoking is not red yet and one SonicBoom would leave it red but
-- with >= VOLTORB_RED_MIN HP (default 9, above Quick Attack) and VOLTORB_RED_MARGIN (default 4) HP below the red line, open with BubbleBeam (as the original bot did without
-- RISK_TARGETED) so Voltorb gets another turn. Otherwise the v66 fight.
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local Battle = require "action.battle"
	local Pokemon = require "storage.pokemon"
	local Memory = require "util.memory"
	local prev = S.fightSurge or Strategies.functions.fightSurge
	assert(prev, "v69: fightSurge not found")
	S.fightSurge = function(data)
		if VOLTORB_RED and Memory.value("game", "battle") == 2 and Pokemon.isOpponent("voltorb") and not Battle.opponentDamaged() then
			local hp, mx = Combat.hp(), Combat.maxHP()
			local after = hp - 20
			local min = VOLTORB_RED_MIN or 9
			local margin = VOLTORB_RED_MARGIN or 4   -- build 2: level-ups in the fight add HP (smoke build 1: 2/6 red)
			if hp > 0 and hp * 48 >= mx * 10 and (after + margin) * 48 < mx * 10 and after >= min and Battle.pp("bubblebeam") > 0 then
				local st = Strategies.status
				if not st.v69log then
					st.v69log = true
					print("refstrat v69 VOLTORB_RED: hp " .. hp .. "/" .. mx .. ", a SonicBoom would leave " .. after
						.. " (red, >= " .. min .. ") -> BubbleBeam so Voltorb acts again (v66 would not)")
				end
				Combat.setDisableThrash(true)
				Battle.automate("bubblebeam")
				return false
			end
		end
		return prev(data)
	end
	print("Upgrade loaded: v69 switch (VOLTORB_RED " .. tostring(VOLTORB_RED) .. ", min " .. tostring(VOLTORB_RED_MIN) .. ")")
end

-- v73 BILL_TOPUP_HP (experiments/v73-2026-10-21, owner 21 Oct; ../misty-2026-10-21/README.md). Default off = v72 play.
-- Every Misty reset in the v69 big test was Nidoking fainting, and the HP brought into Misty decides the fight.
-- At Bill's the bag is open anyway and the Bike Shop brings instant text back, so a Potion costs ~3.5 s there.
-- Rule: after the v16 row-15 decision (0-2 Potions), use more Potions (bounded by the Potions held) until HP >= N.
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local Inventory = require "storage.inventory"
	local prev = S.refBillPotions
	assert(prev, "v73: refBillPotions not found")
	S.refBillPotions = function(data)
		local st = Strategies.status
		if BILL_TOPUP_HP and st.refBill == nil then
			local hp, mx = Combat.hp(), Combat.maxHP()
			local want = (hp <= 28) and 2 or ((hp <= 47) and 1 or 0)
			local goal = math.min(BILL_TOPUP_HP, mx)
			local m = (hp > 0 and hp < goal) and math.ceil((goal - hp) / 20) or 0
			local n = math.min(math.max(want, m), Inventory.count("potion"))
			if n > want then
				st.refBill = math.min(mx, hp + 20 * n - 19)
				print("refstrat v73 BILL_TOPUP_HP=" .. BILL_TOPUP_HP .. ": hp " .. hp .. "/" .. mx .. " -> " .. n
					.. " Potion(s) (v72: " .. math.min(want, Inventory.count("potion")) .. ", Potions held " .. Inventory.count("potion") .. ")")
			end
		end
		return prev(data)
	end
	print("Upgrade loaded: v73 switch (BILL_TOPUP_HP " .. tostring(BILL_TOPUP_HP) .. ")")
end

-- v75 SURGE_SAVE_PHASE (experiments/v75-2026-10-21, PM 21 Oct; ../mistysurge-time-2026-10-21/README.md). Default off
-- = v73 play. At the Surge chain's save YES prompt, if the tracked IGT (the bot's own frame count, REFSTRAT_CLOCK_NOW)
-- is at frame 32-40 of its second, wait until frame 41 (at most 9 frames), then let the v11 good-frame rule decide.
do
	local S = REFSTRAT_STRATEGIES
	local Textbox = require "action.textbox"
	local Memory = require "util.memory"
	local prev = S.refChain
	assert(prev, "v75: refChain not found")
	S.refChain = function(data)
		if SURGE_SAVE_PHASE and data.name == "surge" then
			local st = Strategies.status
			if st.choseSave and not st.answered and not st.saved and Textbox.isActive() and Memory.value("battle", "text") == 20 then
				local now = REFSTRAT_CLOCK_NOW and REFSTRAT_CLOCK_NOW()
				if now and now % 60 >= 32 and now % 60 <= 40 and (st.v75wait or 0) < 9 then
					st.v75wait = (st.v75wait or 0) + 1
					if st.v75wait == 1 then print("refstrat v75 SURGE_SAVE_PHASE: tracked IGT frame " .. (now % 60) .. " at the save YES -> wait to frame 41 (v73: no wait)") end
					return false
				end
			end
		end
		return prev(data)
	end
	print("Upgrade loaded: v75 switch (SURGE_SAVE_PHASE " .. tostring(SURGE_SAVE_PHASE) .. ")")
end

-- v77 PARAS_RED2 + R9_WAIT (experiments/v77-2026-10-21, PM 22 Oct). Default off = v75 play.
-- PARAS_RED2: at the Route 3 exit Potion step, if the lead is already red (hp*48 < max*10, the line of the battle
-- low-HP alarm), do not heal; the Mt. Moon chain then uses the red Paras catch script: B-mash 247 pairs + B, the same
-- ball throw, B-mash 285 pairs (1,135 f instead of 1,458 f). At red HP the alarm skips the battle's sound waits
-- (pokered home/delay.asm WaitForSoundToFinish), so the battle ends ~290 f earlier. Offline: 3,450 of 3,450 red
-- classes caught Paras with one ball (search/RESULT.md). Not red: heal and the v75 chain as before.
-- R9_WAIT = N: before talking to the Route 9 Jr. Trainer F, idle N frames when the lead has R9_WAIT_LO..R9_WAIT_HI HP
-- (default 14-15: 8 of 10 such fights died, all on the same frame; team/scout/ROUTE9.md). Memory read + frame count
-- only (no RNG or game-clock read).
do
	local S = REFSTRAT_STRATEGIES
	local Combat = require "ai.combat"
	local function red(hp, mx) return hp > 0 and hp * 48 < mx * 10 end
	S.refParasRed2Potion = function(data)
		local st = Strategies.status
		if st.v77red == nil then
			local hp, mx = Combat.hp(), Combat.maxHP()
			st.v77red = PARAS_RED2 == true and red(hp, mx)
			REFSTRAT_V77_PARAS_RED = st.v77red
			if st.v77red then
				print("refstrat v77 PARAS_RED2: hp " .. hp .. "/" .. mx .. " red at the Route 3 exit -> no heal, red Paras catch script (v75 would heal)")
			end
		end
		if st.v77red then return true end
		return (S.potion or Strategies.functions.potion)(data)
	end
	local THROW = REFSTRAT_CHAIN_CATCH_THROW
	assert(THROW == "left:1,:1,left:1,down:1,:1,down:1,*2(a:1,:1),*5(left:1,:1),a:1,*12(:1,a:3),:1", "v77: catch throw changed")
	local prevBuild = REFSTRAT_CHAIN_BUILD
	assert(prevBuild, "v77: REFSTRAT_CHAIN_BUILD not found")
	REFSTRAT_CHAIN_BUILD = function(name, over)
		local prog = prevBuild(name, over)
		if PARAS_RED2 and name == "moon" and REFSTRAT_V77_PARAS_RED then
			local n = 0
			for _, seg in ipairs(prog) do
				if seg.k == "battle" and seg.id == 109 then
					seg.s = "*247(b:1,:1),b:1," .. THROW .. ",*285(b:1,:1)"
					seg.partyAt = 495 + 70 + 2 * 285 - 1
					n = n + 1
				end
			end
			assert(n == 1, "v77: Paras battle segment found " .. n .. " times")
			print("refstrat v77 PARAS_RED2: Mt. Moon chain uses the red Paras catch script (1135 f, v75 1458 f)")
		end
		return prog
	end
	local prevTalk = S.talk or Strategies.functions.talk
	assert(prevTalk, "v77: talk not found")
	S.talk = function(data)
		if R9_WAIT and data and data.v77wait then
			local st = Strategies.status
			if st.v77w == nil then
				local hp = Combat.hp()
				local lo, hi = R9_WAIT_LO or 14, R9_WAIT_HI or 15
				st.v77w = (hp >= lo and hp <= hi) and (tonumber(R9_WAIT) or 0) or 0
				st.v77n = 0
				if st.v77w > 0 then
					print("refstrat v77 R9_WAIT: hp " .. hp .. " at the Route 9 trainer -> idle " .. st.v77w .. " frames before talking (v75: none)")
				end
			end
			if st.v77n < st.v77w then
				st.v77n = st.v77n + 1
				return false
			end
		end
		return prevTalk(data)
	end
	print("Upgrade loaded: v77 switches (PARAS_RED2 " .. tostring(PARAS_RED2) .. ", R9_WAIT " .. tostring(R9_WAIT) .. ")")
end

-- v78 ROUTE22_REPEL (experiments/v78-2026-10-22/PLAN.md). Default off = v77 play. Celadon 2F buys SUPER_REPEL x10 and
-- SUPER_POTION x2 instead of x9 and x3 (-200 money; the money there is fixed at 22,331 vs a 22,300 list, and the 5 finished
-- late games all ended with 2 Super Potions unused), so the Viridian exit can use one Super Repel (route.lua).
do
	local prevExact = REFSTRAT_CELADON_EXACT
	assert(prevExact, "v78: REFSTRAT_CELADON_EXACT not found")
	REFSTRAT_CELADON_EXACT = function(cash)
		local p = prevExact(cash)
		if ROUTE22_REPEL and p.supers and p.supers >= 3 and p.repels then
			p.repels, p.supers = p.repels + 1, p.supers - 1
			print("refstrat v78 ROUTE22_REPEL: Celadon 2F SUPER_REPEL x" .. p.repels .. ", SUPER_POTION x" .. p.supers .. " (v77: x" .. (p.repels - 1) .. ", x" .. (p.supers + 1) .. ")")
		end
		return p
	end
	print("Upgrade loaded: v78 switch (ROUTE22_REPEL " .. tostring(ROUTE22_REPEL) .. ")")
end

-- v79 ROUTE22_REPEL: the single reserve edit above allows one of Celadon's two Super Potions in the field.
-- Wrap the old potion function only to log an actual use that reserve 2 would have blocked. No new heal policy.
do
	local S = REFSTRAT_STRATEGIES
	local Strategies = require "ai.strategies"
	local Inventory = require "storage.inventory"
	local Memory = require "util.memory"
	local LEAGUE = {[174] = true, [245] = true, [246] = true, [247] = true, [113] = true, [120] = true, [118] = true}
	local prev = S.potion or Strategies.functions.potion
	assert(prev, "v79: potion not found")
	S.potion = function(data)
		if not ROUTE22_REPEL then return prev(data) end
		local map = Memory.value("game", "map")
		if LEAGUE[map] or Inventory.count("super_potion") ~= 2 then return prev(data) end
		local use = Inventory.use
		Inventory.use = function(item, ...)
			local st = Strategies.status
			if item == "super_potion" and not st.v79ReserveLogged then
				st.v79ReserveLogged = true
				print("refstrat v79 ROUTE22_REPEL: SUPER_RESERVE 2 -> 1 permits field Super Potion at map " .. map .. " step=" .. tostring(st.stepId))
			end
			return use(item, ...)
		end
		local ok, result = pcall(prev, data)
		Inventory.use = use
		if not ok then error(result) end
		return result
	end
end

-- v83: reject only the untouched standard level-5 starter before the first fight action.
do
	local S = REFSTRAT_STRATEGIES
	local Strategies = require "ai.strategies"
	local Pokemon = require "storage.pokemon"
	local Memory = require "util.memory"
	local prev = S.fightBulbasaur or Strategies.functions.fightBulbasaur
	assert(prev, "v83: fightBulbasaur not found")
	S.fightBulbasaur = function(...)
		if not EARLY_STARTER_GATE then return prev(...) end
		local st = Strategies.status
		if not st.v83StarterChecked then
			st.v83StarterChecked = true
			local untouched = Memory.value("game", "map") == 40 and
				Memory.value("player", "party_size") == 1 and
				Pokemon.index(0) == Pokemon.getID("squirtle") and
				Pokemon.index(0, "level") == 5 and Pokemon.getExp() == 135 and
				Pokemon.index(0, "status") == 0 and
				Pokemon.index(0, "hp") == Pokemon.index(0, "max_hp") and
				Memory.raw(0x116B + 8) == 33 and Memory.raw(0x116B + 9) == 39 and
				Memory.raw(0x116B + 10) == 0 and Memory.raw(0x116B + 11) == 0 and
				Pokemon.pp(0, "tackle") == 35 and Pokemon.pp(0, "tail_whip") == 30
			if untouched then
				for offset = 17, 26 do
					if Memory.raw(0x116B + offset) ~= 0 then untouched = false; break end
				end
			end
			if untouched then
				local attack, defense, speed, special = Pokemon.getDVs("squirtle")
				if attack <= 1 and special <= 7 then
					print("refstrat v83 EARLY_STARTER_GATE: untouched L5 Squirtle attackDV=" ..
						attack .. " specialDV=" .. special)
					return Strategies.reset("stats", "v83 early bad Squirtle")
				end
			end
		end
		return prev(...)
	end
end

-- v86: LAVENDER_LATE_HP (Late Horn Drill by HP; experiments/silphred-check-2026-10-23/SPEC.md part B).
-- Choice latched once at the Celadon Super Repel shop from the lead Nidoking's HP/level/EXP/status/moves/PP.
-- Late bands 11-15, 17-19, 28+ (else Early = v83 play). Late: TM07 deferred to Tower 6F, Lavender rival without
-- X Accuracy: Thunderbolt Pidgeotto/Gyarados, BubbleBeam Growlithe only when the move's minimum damage is a sure KO and we
-- are faster; Thrash Kadabra/Ivysaur only with a sure Kadabra KO, speed and HP > 16; otherwise the engine's own choice.
-- Memory reads and frame counts only; no RNG / game-clock reads, no writes.
do
	local S = REFSTRAT_STRATEGIES
	local Strategies = require "ai.strategies"
	local Battle = require "action.battle"
	local Combat = require "ai.combat"
	local Memory = require "util.memory"
	local Pokemon = require "storage.pokemon"
	local Inventory = require "storage.inventory"
	local v86 = {}
	local function knows(move) return Pokemon.moveIndex(move, "nidoking") ~= nil end
	local function lateBand(hp)
		if LAVENDER_LATE_MIN then return hp >= tonumber(LAVENDER_LATE_MIN) end
		return (hp >= 11 and hp <= 15) or (hp >= 17 and hp <= 19) or hp >= 28
	end

	local prevShop = S.refShopRepels or Strategies.functions.refShopRepels
	assert(prevShop, "v86: refShopRepels not found")
	S.refShopRepels = function(...)
		if LAVENDER_LATE_HP and v86.choice == nil then
			local hp, maxhp = Pokemon.index(0, "hp"), Pokemon.index(0, "max_hp")
			local lvl, exp, status = Pokemon.index(0, "level"), Pokemon.getExp(), Pokemon.index(0, "status")
			local ok = Pokemon.index(0) == Pokemon.getID("nidoking") and lvl == 31 and exp == 24425 and status == 0
				and knows("thunderbolt") and knows("thrash") and knows("bubblebeam") and not knows("horn_drill")
				and Pokemon.pp(0, "thunderbolt") >= 2 and Pokemon.pp(0, "thrash") >= 1 and Pokemon.pp(0, "bubblebeam") >= 1
			v86.choice = (ok and lateBand(hp)) and "late" or "early"
			print("refstrat v86 LAVENDER_LATE_HP: choice=" .. v86.choice .. " hp=" .. hp .. "/" .. maxhp .. " level=" .. lvl ..
				" exp=" .. exp .. " eligible=" .. tostring(ok))
		end
		return prevShop(...)
	end

	S.v86DrillCeladon = function(data)
		if not (LAVENDER_LATE_HP and v86.choice == "late" and Inventory.contains("horn_drill")) then
			return Strategies.functions.teach(data)
		end
		if not v86.deferLogged then
			v86.deferLogged = true; v86.deferred = true
			print("refstrat v86 LAVENDER_LATE_HP: TM07 deferred at Celadon")
		end
		return Strategies.closeMenuFor(data)
	end

	local Menu = require "util.menu"
	S.v86DrillLate = function()
		if not v86.deferred then return true end
		if knows("horn_drill") then
			if not v86.teaching then return true end
			if not v86.learnedLogged then v86.learnedLogged = true; print("refstrat v86 LAVENDER_LATE_HP: Horn Drill learned on Tower 6F") end
			return Menu.close()   -- finish the teach menus before walking on
		end
		if not Inventory.contains("horn_drill") then
			if v86.teaching then return Strategies.reset("error", "v88: TM07 gone without Horn Drill") end
			return true
		end
		if not v86.teaching then
			v86.teaching = true
			print("refstrat v86 LAVENDER_LATE_HP: teach TM07 over Thrash on Tower 6F")
		end
		return S.refTeach({move = "horn_drill", replace = "thrash", poke = "nidoking"})
	end

	local function sureKO(name)
		local idx = Pokemon.battleMove(name)
		if not idx or Battle.pp(name) <= 0 or Combat.isDisabled(name) or Combat.isConfused()
			or Memory.value("battle", "paralyzed") ~= 0 then return false end
		local ours, enemy = Combat.activePokemon()
		local mv = ours.moves and ours.moves[idx]
		if not mv or enemy.hp <= 0 or ours.speed <= enemy.speed then return false end
		if name == "thrash" then   -- the route bans Thrash in move scoring here ({c="thrash",disable=true}); lift it for this check only
			Combat.setDisableThrash(false)
			local ok, lo = pcall(Combat.calcRange, mv, ours, enemy)
			Combat.setDisableThrash(true)
			return ok and lo >= enemy.hp
		end
		return Combat.calcRange(mv, ours, enemy) >= enemy.hp
	end
	local function act(opp, move, why)
		local ours, enemy = Combat.activePokemon()
		local key = tostring(REFSTRAT_BATTLE_ID) .. ":" .. opp .. ":" .. tostring(move) .. ":" .. enemy.hp
		if v86.actKey ~= key then
			v86.actKey = key
			print("refstrat v86 LAVENDER_LATE_HP: " .. opp .. " -> " .. tostring(move or "engine") .. " (" .. why ..
				") hp=" .. ours.hp .. " enemyHP=" .. enemy.hp)
		end
		Battle.automate(move)
	end

	local prevRival = S.lavenderRival or Strategies.functions.lavenderRival
	assert(prevRival, "v86: lavenderRival not found")
	S.lavenderRival = function(...)
		if not (LAVENDER_LATE_HP and v86.deferred and not knows("horn_drill")) then return prevRival(...) end
		if Strategies.trainerBattle() then
			local opp = Pokemon.isOpponent("pidgeotto", "gyarados", "growlithe", "kadabra", "ivysaur")
			if Memory.value("battle", "attack_turns") > 0 then return Battle.automate() end   -- inside a Thrash lock
			if opp == "pidgeotto" or opp == "gyarados" then
				if sureKO("thunderbolt") then return act(opp, "thunderbolt", "sure KO") end
				return act(opp, nil, "no sure Thunderbolt KO: engine choice")
			elseif opp == "growlithe" then
				if sureKO("bubblebeam") then return act(opp, "bubblebeam", "sure KO") end
				return act(opp, nil, "no sure BubbleBeam KO: engine choice")
			elseif opp == "kadabra" or opp == "ivysaur" then
				local ours, enemy = Combat.activePokemon()
				if ours.hp > 16 and ours.speed > enemy.speed and (opp == "ivysaur" or sureKO("thrash"))
					and Battle.pp("thrash") > 0 and not Combat.isDisabled("thrash")
					and not Combat.isConfused() and Memory.value("battle", "paralyzed") == 0 then
					return act(opp, "thrash", "Thrash guard ok")
				end
				return act(opp, nil, "Thrash guard failed: engine choice")
			end
			return act(tostring(opp), nil, "other opponent: engine choice")
		elseif Strategies.status.foughtTrainer then
			return true
		end
	end
end
