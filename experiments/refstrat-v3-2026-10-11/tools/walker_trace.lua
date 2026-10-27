-- Diagnostic overlay (research only, never part of a candidate stack): logs the route walker's private state.
-- Globals: REFTRACE_FROM, REFTRACE_TO (frames), REFTRACE_EVERY (frames between lines, default 1).
-- Lines: "WT frame map pos pathIdx stepIdx #path tile strategy battle textbox menu" + strategy transitions "WS".
do
	local Walk = require "action.walk"
	local Memory = require "util.memory"
	local Player = require "util.player"
	local Textbox = require "action.textbox"
	local Menu = require "util.menu"
	local origTraverse = Walk.traverse
	local function up(fn, name)
		local i = 1
		while true do
			local n, v = debug.getupvalue(fn, i)
			if not n then return nil end
			if n == name then return v end
			i = i + 1
		end
	end
	local function tileText(t)
		if type(t) ~= "table" then return tostring(t) end
		if t.s then return "s=" .. t.s end
		if t.c then return "c=" .. t.c end
		return "{" .. tostring(t[1]) .. "," .. tostring(t[2]) .. "}"
	end
	local lastStrategy
	local function log(tag)
		local f = emu.framecount()
		local from, to, every = REFTRACE_FROM or 0, REFTRACE_TO or 0, REFTRACE_EVERY or 1
		if f < from or f > to or (f - from) % every ~= 0 then return end
		local px, py = Player.position()
		local path, stepIdx, pathIdx = up(origTraverse, "path"), up(origTraverse, "stepIdx"), up(origTraverse, "pathIdx")
		local tile = path and stepIdx and path[stepIdx]
		print(string.format("WT%s f=%d map=%d pos=%d,%d pathIdx=%s stepIdx=%s n=%s tile=%s strat=%s battle=%d text=%s menu=%s",
			tag, f, Memory.value("game", "map"), px, py, tostring(pathIdx), tostring(stepIdx), tostring(path and #path),
			tileText(tile), tostring(Walk.strategy and Walk.strategy.s), Memory.value("game", "battle"),
			tostring(Textbox.isActive()), tostring(Menu.isOpened())))
	end
	Walk.traverse = function(region)
		local r = origTraverse(region)
		log("")
		return r
	end
	local exec = Strategies.execute
	Strategies.execute = function(data)
		local r = exec(data)
		if data.s ~= lastStrategy or r then
			local f = emu.framecount()
			if f >= (REFTRACE_FROM or 0) and f <= (REFTRACE_TO or 0) then
				local px, py = Player.position()
				print(string.format("WS f=%d strategy=%s returned=%s pos=%d,%d", f, tostring(data.s), tostring(r), px, py))
			end
			lastStrategy = data.s
		end
		return r
	end
	print("walker_trace loaded")
end
