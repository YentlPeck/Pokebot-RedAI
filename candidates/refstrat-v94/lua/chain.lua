-- refstrat v8: post-reset manipulation CHAIN programs (reference "triple extended" manip after the Nidoran save:
-- Nidoran L4 -> Route 2 Pidgey L5 in one ball -> encounter-free Viridian Forest -> Weedle String Shot; sources
-- experiments/refstrat-v8-2026-10-11/sources/GUIDES.md, refstrat-v7 sources/MOON_FOREST.md A).
-- This file is pure data + a builder. It is executed by the candidate (S.refChain in strategies.lua) AND by the
-- offline simulator (experiments/refstrat-v8-2026-10-11/tools/chainprog.py, via lupa), so both play the SAME frames.
-- Script strings: "button:frames" items ("" = no button, "a+b" = both), "*N(...)" repeats a group.

-- Engine inputs recorded in t1-1797000000 (frozen-v7 logic, deterministic after the power cycle), relative to the
-- first frame of the battle flag: Nidoran catch with ball 1, Pokedex, nickname "A" (1449 frames).
REFSTRAT_CHAIN_NIDO_INTRO = "*161(b:1,:1),*34(a:1,:1),a:1,*69(b:1,:1),b:1"
-- [throw delay nd frames], then ITEM -> POKe BALL -> throw, Pokedex, nickname "A"
REFSTRAT_CHAIN_NIDO_CATCH = "left:1,:1,left:1,down:1,:1,down:1,*2(a:1,:1),*5(left:1,:1),a:1,*12(:1,a:3),*155(b:1,:1),*83(a:1,:1),a:1,*25(b:1,:1),b:1,*29(a:1,:1),a:1,*79(b:1,:1),b:1,*43(a:1,:1),a:1,start:1,:1,start:1,a:1,:1,a:1,*2(start:1,:1),*2(b:1,:1),b:1,a:1,b:1"
-- Wild catch: intro text cleared with B (515 frames), [delay], ITEM -> POKe BALL -> throw (70 frames), then B
-- (caught text, Pokedex, nickname NO).
REFSTRAT_CHAIN_CATCH_INTRO = "*257(b:1,:1),b:1"
REFSTRAT_CHAIN_CATCH_THROW = "left:1,:1,left:1,down:1,:1,down:1,*2(a:1,:1),*5(left:1,:1),a:1,*12(:1,a:3),:1"

-- Reference geometry (map,x,y). Save tile Viridian (7,18) facing Left (GUIDES.md 5 / G-NM 2024 default path).
-- Nidoran path: L3 A U2 A U1 L2 D1 L5 (-> Route 22) A D4 A D2 (ledge) L1 A L2 A L1 U2 A U1 -> encounter (33,11).
REFSTRAT_CHAIN_NIDO_PATH = "1,4,18;1,4,16;1,4,15;1,2,15;1,2,16;1,0,16;33,37,8;33,37,12;33,37,14;33,36,14;33,34,14;33,33,14;33,33,12;33,33,11"
-- Deviation (FINDINGS F2): on this platform no level-4 encounter on the first grass step (33,11) was found that is robust
-- within budget, so the bot then paces (32,11) <-> (33,11) until the first encounter (v7 pacing rule, at most 20 steps).
REFSTRAT_CHAIN_NIDO_PACE = string.rep(";33,32,11;33,33,11", 10)
REFSTRAT_CHAIN_NIDO_PRESS = {["1,4,18"] = "a:1", ["1,4,16"] = "a:1", ["33,37,8"] = "a:1", ["33,37,12"] = "a:1",
	["33,36,14"] = "a:1", ["33,34,14"] = "a:1", ["33,33,12"] = "a:1"}
-- Route 22 -> Viridian -> Route 2 west grass (MOON_FOREST A.2 rows 2, 5): D1 R2 U3 R21 U1 R1 U6 R1 U2 [A] L1 U3 [A]
-- U~14 [A at Route 2 (7,61)] then (7,59) (4,59) (4,52) (8,52) [A at (8,51)] (8,44) (3,44).
REFSTRAT_CHAIN_PIDGEY_PATH = "33,33,12;33,35,12;33,35,9;33,39,9;1,16,17;1,16,16;1,17,16;1,17,10;1,18,10;1,18,8;1,17,8;1,17,0;13,7,59;13,4,59;13,4,52;13,8,52;13,8,44;13,3,44"
-- v9 deviation (as the Nidoran stage, FINDINGS v9; enabled by the parameter pace): the Route 2 grass of this path is
-- (8,48)-(8,51); if the walk up through it meets no encounter, pace (8,49) <-> (8,48) until the first one (at most 20
-- steps), then continue on the reference path (8,44) (3,44).
REFSTRAT_CHAIN_PIDGEY_PACE = ";13,8,48" .. string.rep(";13,8,49;13,8,48", 10)
REFSTRAT_CHAIN_PIDGEY_PRESS = {["1,18,8"] = "a:1", ["1,17,5"] = "a:1", ["13,7,61"] = "a:1", ["13,8,51"] = "a:1"}

-- Route 2 (after the Pidgey) -> gate (UUUUURUU) -> Viridian Forest reference path (MOON_FOREST key finding 4):
-- (17,47) U4 R4 U2 R4 U29 (25,12) [A: Antidote at (25,11)] U3 L8 D7 L4 U13 L6 D18 L1 D1 L4 U3 (2,19), talk Up.
-- A 4th field is the direction held while still on the previous map (doors are never observed on the source map).
REFSTRAT_CHAIN_FOREST_PATH = "13,8,44;13,3,44;50,4,2,up;50,5,2;51,17,43,up;51,21,43;51,21,41;51,25,41;51,25,12;51,25,9;51,17,9;51,17,16;51,13,16;51,13,3;51,7,3;51,7,21;51,6,21;51,6,22;51,2,22;51,2,19"
REFSTRAT_CHAIN_FOREST_PRESS = {["51,25,12"] = ":16,a:3,*90(:1),a:1"}   -- Antidote: A held 3 frames, A closes the text
-- Free mode only (chain already broken, the forest is no longer manipulated): v2-v7 grass-avoiding forest path with the
-- Antidote and the hidden Potion (1,18) from (1,19) - logged recovery, fewer wild battles for an unmanipulated forest.
REFSTRAT_CHAIN_FOREST_FREE = "13,8,44;13,3,44;50,4,2,up;50,5,2;51,17,43,up;51,26,43;51,26,34;51,25,34;51,25,32;51,27,32;51,27,20;51,25,20;51,25,12;51,25,9;51,17,9;51,17,16;51,13,16;51,13,3;51,7,3;51,7,22;51,1,22;51,1,19;51,2,19"

-- Mt. Moon manip (reference 17:10-19:44; G-MM gifvex path verified step by step, refstrat-v7 sources/MOON_FOREST.md B.2,
-- v8 sources/EARLY_ROUTE.md 3.3): SAVE on Route 3 (27,11) facing Down after the last Bug Catcher, power cycle, then
-- [1] Route 3/4 R8 U1 R2 U5 A R12 D5 R7 A R1 U2 R2 U10 R4 U10 R5 U (Mt. Moon door), 1F TM12 (5,32) / Rare Candy (35,31) /
-- Escape Rope (36,23), ladder (17,11); B1F small room; B2F TM01 (29,5); back to 1F; Moon Stone (2,2); ladder (5,5);
-- B1F; B2F path to (10,17) where the manipulated Paras appears. The 1F Super Nerd and all trainers are passed unseen.
-- Non-item A presses at the tiles the reference shows (MOON_FOREST B.2); those whose tiles are not resolved on the video
-- (B1F rows 7 and 10) are omitted. Each segment starts with a wait knob (offline search, PyBoy has its own boot timing).
-- Waypoints after a ladder/door carry the direction held onto the warp tile.
REFSTRAT_CHAIN_MOON = {
	{path = "14,35,11;14,35,10;14,37,10;14,37,5", press = {["14,37,5"] = "a:1"}},
	{path = "14,49,5;14,49,10;14,56,10", press = {["14,56,10"] = "a:1"}},
	{path = "14,57,10;14,57,8;14,59,8;14,59,0;15,9,16,up;15,13,16;15,13,6;15,18,6", splitAfter = true},
	{path = "59,14,35,up;59,14,29;59,9,29", press = {["59,9,29"] = "a:1"}},
	{path = "59,5,29;59,5,31", press = {["59,5,31"] = ":16,a:3,*90(:1),a:1"}, items = {["59,5,31"] = "Down"}},
	{path = "59,9,31;59,9,29;59,12,29", press = {["59,12,29"] = "a:1"}},
	{path = "59,14,29;59,14,22;59,21,22", press = {["59,21,22"] = "a:1"}},
	{path = "59,21,15;59,24,15;59,24,16;59,25,16;59,25,23", press = {["59,25,23"] = "a:1"}},
	{path = "59,25,31", press = {["59,25,31"] = "a:1"}},
	{path = "59,25,32;59,30,32;59,30,31;59,34,31", press = {["59,34,31"] = ":16,a:3,*90(:1),a:1"}, items = {["59,34,31"] = "Right"}},
	{path = "59,34,23;59,35,23", press = {["59,35,23"] = ":16,a:3,*90(:1),a:1"}, items = {["59,35,23"] = "Right"}},
	{path = "59,35,22;59,34,22;59,34,17", press = {["59,34,17"] = "a:1"}},
	{path = "59,34,11;59,31,11;59,31,3;59,25,3;59,25,5;59,24,5", press = {["59,24,5"] = "a:1"}},
	{path = "59,17,5;59,17,10;60,25,9,down"},
	{path = "60,17,9;60,17,10;61,25,9,down"},
	{path = "61,28,9;61,28,6;61,27,6", press = {["61,27,6"] = "a:1"}},
	{path = "61,27,5;61,28,5", press = {["61,28,5"] = ":16,a:3,*90(:1),a:1"}, items = {["61,28,5"] = "Right"}},
	{path = "61,28,7", press = {["61,28,7"] = "a:1"}},
	{path = "61,28,8;61,27,8", press = {["61,27,8"] = "a:1"}},
	{path = "61,25,8", press = {["61,25,8"] = "a:1"}},
	{path = "60,17,11,down"},
	{path = "60,25,11;60,25,10;59,17,11,up"},
	{path = "59,17,13;59,16,13;59,16,17"},
	{path = "59,9,17;59,9,16;59,8,16;59,8,11"},
	{path = "59,7,11;59,7,3;59,4,3;59,4,2;59,3,2", press = {["59,3,2"] = ":16,a:3,*90(:1),a:1"}, items = {["59,3,2"] = "Left"}},
	{path = "59,3,3", press = {["59,3,3"] = "a:1"}},
	{path = "59,3,5;59,4,5", press = {["59,4,5"] = "a:1"}},
	{path = "60,5,5,right"},
	{path = "60,5,6;60,7,6;60,7,16;60,10,16", press = {["60,10,16"] = "a:1"}},
	{path = "60,20,16;60,20,17;61,21,17,right"},
	{path = "61,23,17;61,23,14;61,24,14", press = {["61,24,14"] = "a:1"}},
	{path = "61,27,14;61,27,16;61,32,16;61,32,15", press = {["61,32,15"] = "a:1"}},
	{path = "61,33,15;61,33,14;61,34,14", press = {["61,34,14"] = "a:1"}},
	{path = "61,36,14;61,36,22", press = {["61,36,22"] = "a:1"}},
	{path = "61,32,22;61,32,29", press = {["61,32,29"] = "a:1"}},
	{path = "61,32,31;61,29,31", press = {["61,29,31"] = "a:1"}},
	{path = "61,17,31", press = {["61,17,31"] = "a:1"}},
	{path = "61,11,31;61,11,27", press = {["61,11,27"] = "a:1"}},
	{path = "61,11,25", press = {["61,11,25"] = "a:1"}},
	{path = "61,10,25;61,10,17" .. string.rep(";61,10,18;61,10,17", 6), expect = true},   -- deviation: pace (10,18)/(10,17) (FINDINGS)
}

-- v9: Surge's trash cans as the reference (41:41-42:11, v5 COMMENTARY: SAVE outside the gym after the Cut tree, reset,
-- CONTINUE, can 8 = bottom middle (5,11), then its left neighbour can 5 = (3,11)). pokered vermilion_gym_trash.asm:
-- the first lock is rolled at the Vermilion City map load after CONTINUE (Random & $0E), the second when can 8 opens
-- (Random, swap, AND 3, minus 1 -> neighbour list 5, 7, 11; 0 by the underflow bug), so the boot schedule (first) and
-- the frame of the A press on can 8 (s2) choose the cans. SAVE on Vermilion (12,20); door hint "up"; the gym entrance
-- (4,17) -> (4,16) -> (5,16) -> (5,12) facing up (no trainer sees this path; the Gym Guide stands at (4,14)).
REFSTRAT_CHAIN_SURGE_PATH8 = "92,4,16,up;92,5,16;92,5,12"
REFSTRAT_CHAIN_SURGE_PATH5 = "92,4,12;92,3,12"

-- Tuned parameters (offline search, experiments/refstrat-v8-2026-10-11/FINDINGS.md); nil = stage not enabled.
-- v9 (experiments/refstrat-v9-2026-10-11/FINDINGS.md V3-V4): early retuned on the v9 save content (Viridian NPCs reset by
-- the Route 22 re-entry): w2 = 100 (Pidgey L5 at the majority class), Pidgey pacing in the (8,48)-(8,51) grass (pace),
-- the reference level 5 required (pl = 5; review 1 #4: other levels break to the logged free mode), w4 = 40 (forest).
-- surge (V2): boot first = 48 -> first lock can 8; s2 = 10 -> second lock can 5.
-- early (search/early-193258.jsonl, 180-cell clock grid): Nidoran 150/180; Pidgey 106/150; forest without encounter
-- 50/106; Weedle T1 String Shot 42/50 (FINDINGS F2-F4).
-- moon (greedy search on save t3-1797000030 at clock 30:0, search/moon_greedy_log*.txt; FINDINGS F5): 8/30 phases on
-- three seeds' saves.
-- v12 (experiments/refstrat-v12-2026-10-12/FINDINGS.md M3): moon m38 = 23 (was 20) and pd = 25 (was 8) give the reference
-- Paras L10 at B2F (10,17), caught with one ball, at saved frames 4..7 (72/72 offline cells on 3 real saves); plv = 10
-- makes the timed chain require that level (other levels break to the logged free mode).
REFSTRAT_CHAIN_PARAMS = REFSTRAT_CHAIN_PARAMS or {moon = {stage = 1, m1 = 64, m8 = 2, m13 = 2, m14 = 16, m28 = 2, m38 = 23, plv = 10,
	m40 = 26, pd = 25}, early = {w1 = 62, nd = 10, w2 = 100, w3 = 0, w4 = 40, stage = 3, pace = 1, pl = 5,
	antidote = ":16,a:3,*90(:1),a:1", weedleIdAt = 300, weedle = "*268(b:1,:1),:2,a:1,:12,up:1,:8,a:1,*90(:1)"},
	surge = {stage = 1, first = 48, s1 = 0, s2 = 10}}

-- v56: "map,x,y=script|map,x,y=script" -> press table
function V56_PRESS(text)
	local t = {}
	for item in text:gmatch("[^|]+") do
		local k, v = item:match("^([^=]+)=(.*)$")
		if k then t[k] = v end
	end
	return t
end

-- v56 MANIP_FAST (experiments/build-2026-10-16/manip/REPORT.md): re-searched parameter sets that start moving right after
-- CONTINUE and drop fixed post-catch / switch idle. Per chain: MANIP_FAST_EARLY / _MOON / _SURGE (true/false) override
-- MANIP_FAST; unset = the v52 parameters above.
REFSTRAT_CHAIN_PARAMS_FAST = {early = {weedle = "*268(b:1,:1),:2,a:1,:12,up:1,:8,a:1,*90(:1)", weedleIdAt = 300, antidote = ":16,a:3,*90(:1),a:1", pl = 5, w4 = 52, w3 = 0, w2 = 100, w1 = 62, stage = 3, pace = 1, nd = 10, tail = 388}, moon = {m13 = 2, m1 = 64, m40 = 26, plv = 10, m14 = 16, pd = 25, m8 = 2, stage = 1, m28 = 2, m38 = 23, tail = 424}, surge = {first = 48, stage = 1, s2 = 10, s1 = 0, bu = 840, t8 = 92, u5 = 0, t5 = 70}}
REFSTRAT_CHAIN_GATES_FAST = {early = {good = {[3] = true}, badsec = {[42] = true, [43] = true, [44] = true}, cap = 260}}
function V56_FAST_ON(name)
	local v = rawget(_G, "MANIP_FAST_" .. name:upper())
	if v == nil then v = rawget(_G, "MANIP_FAST") end
	return v == true
end
for _, n in ipairs({"early", "moon", "surge"}) do
	if V56_FAST_ON(n) and REFSTRAT_CHAIN_PARAMS_FAST[n] then
		REFSTRAT_CHAIN_PARAMS[n] = REFSTRAT_CHAIN_PARAMS_FAST[n]
		print("refstrat v56 MANIP_FAST: chain " .. n .. " uses the fast parameter set")
	end
end

local function merged(name, over)
	local p = {}
	for k, v in pairs(REFSTRAT_CHAIN_PARAMS[name] or {}) do p[k] = v end
	if over then for k, v in pairs(over) do p[k] = v end end
	return p
end

-- Returns the list of segments (see S.refChain / tools/chainprog.py for the rules).
function REFSTRAT_CHAIN_BUILD(name, over)
	local p = merged(name, over)
	local prog = {}
	local function add(seg) prog[#prog + 1] = seg end
	if name == "early" then
		add({k = "boot", first = 30, period = 12, upto = p.bu or 840, stage = "nidoran"})
		add({k = "wait", n = p.w1, stage = "nidoran"})
		add({k = "walk", path = REFSTRAT_CHAIN_NIDO_PATH .. REFSTRAT_CHAIN_NIDO_PACE, press = p.npress and V56_PRESS(p.npress) or REFSTRAT_CHAIN_NIDO_PRESS, expect = true, stage = "nidoran"})
		add({k = "await", n = 40, stage = "nidoran"})
		local nd = p.nd or 0
		add({k = "battle", id = 3, level = 4, idAt = 4, capAt = 905 + nd, partyAt = 1448 + nd, party = 2,
			s = REFSTRAT_CHAIN_NIDO_INTRO .. ",:" .. tostring(nd) .. "," .. REFSTRAT_CHAIN_NIDO_CATCH, stage = "nidoran"})
		add({k = "split", stage = "nidoran"})
		add({k = "wait", n = p.w2, stage = "pidgey"})
		add({k = "walk", path = (p.pace or 0) > 0 and REFSTRAT_CHAIN_PIDGEY_PATH:gsub(";13,8,44;13,3,44$", REFSTRAT_CHAIN_PIDGEY_PACE .. ";13,8,44;13,3,44") or REFSTRAT_CHAIN_PIDGEY_PATH, press = p.ppress and V56_PRESS(p.ppress) or REFSTRAT_CHAIN_PIDGEY_PRESS, expect = true, stage = "pidgey"})
		add({k = "await", n = 40, stage = "pidgey"})
		local tail = p.tail or 650
		local s = REFSTRAT_CHAIN_CATCH_INTRO .. ",:" .. tostring(p.w3) .. "," .. REFSTRAT_CHAIN_CATCH_THROW .. ",*" .. tostring(tail) .. "(b:1,:1)"
		add({k = "battle", id = 36, level = (p.pl or 5) > 0 and (p.pl or 5) or nil, idAt = 4, partyAt = 585 + p.w3 + 2 * tail - 1, party = 3, s = s, stage = "pidgey"})
		add({k = "wait", n = p.w4 or 0, stage = "forest"})
		local press = REFSTRAT_CHAIN_FOREST_PRESS
		if p.antidote then press = {["51,25,12"] = p.antidote} end
		add({k = "walk", path = REFSTRAT_CHAIN_FOREST_PATH, press = press, items = {["51,25,12"] = "Up", ["51,1,19"] = "Up"},
			freePath = REFSTRAT_CHAIN_FOREST_FREE, stage = "forest"})
		add({k = "script", s = p.talk or ":16,a:3,*400(:1,b:1)", endOnBattle = true, final = true, stage = "forest"})
		-- Bug Catcher's Weedle L9: intro text, then turn 1 TAIL WHIP (FIGHT, Up, A) as the reference (8:22.13-8:22.60)
		if p.weedle then
			add({k = "battle", id = 112, level = 9, idAt = p.weedleIdAt or 400, s = p.weedle, stage = "forest"})
		end
	elseif name == "moon" then
		add({k = "boot", first = 30, period = 12, upto = p.bu or 840, stage = "moon"})
		for i, s in ipairs(REFSTRAT_CHAIN_MOON) do
			add({k = "wait", n = p["m" .. i] or 0, stage = "moon"})
			add({k = "walk", path = s.path, press = s.press, items = s.items, expect = s.expect, stage = "moon"})
			if s.splitAfter then add({k = "split", stage = "moon"}) end    -- split 4 (Route 3) at the Mt. Moon door
		end
		add({k = "await", n = 40, stage = "moon"})
		local tail = p.tail or 650
		local s = REFSTRAT_CHAIN_CATCH_INTRO .. ",:" .. tostring(p.pd or 0) .. "," .. REFSTRAT_CHAIN_CATCH_THROW .. ",*" .. tostring(tail) .. "(b:1,:1)"
		-- the manipulated Paras, caught with one ball; v12: level required by plv (= 10, the reference level)
		add({k = "battle", id = 109, level = p.plv, idAt = 4, partyAt = 585 + (p.pd or 0) + 2 * tail - 1, partyGrow = 1, s = s, stage = "moon"})
	elseif name == "surge" then
		add({k = "boot", first = p.first or 50, period = 12, upto = p.bu or 1000, stage = "surge"})
		add({k = "wait", n = p.s1 or 0, stage = "surge"})
		add({k = "walk", path = REFSTRAT_CHAIN_SURGE_PATH8, stage = "surge"})
		add({k = "wait", n = p.s2 or 16, stage = "surge"})
		-- can 8 (facing up after the walk): A, then B through the text (and the switch sound)
		add({k = "script", s = "a:2,*" .. tostring(p.t8 or 200) .. "(:1,b:1)", skipFree = true, stage = "surge"})
		add({k = "walk", path = REFSTRAT_CHAIN_SURGE_PATH5, stage = "surge"})
		-- can 5: turn Up against the can (solid), A, B through the text
		add({k = "script", s = "up:4,:" .. tostring(p.u5 or 16) .. ",a:2,*" .. tostring(p.t5 or 200) .. "(:1,b:1)", skipFree = true, stage = "surge"})
	end
	return prog
end
