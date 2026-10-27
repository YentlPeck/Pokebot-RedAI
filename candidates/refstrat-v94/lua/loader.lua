-- refstrat loader: installs the candidate's own route table, strategies, encounter controls and
-- progress milestones on top of the shared PokeBot engine (Walk/Battle/Menu/Input/Inventory/Pokemon).
-- Load order (campaign --patch): route.lua, strategies.lua, loader.lua.
do
	local Paths = require "data.red.paths"
	assert(REFSTRAT_ROUTE, "refstrat: route.lua must be loaded before loader.lua")
	for k in pairs(Paths) do Paths[k] = nil end
	for i, v in ipairs(REFSTRAT_ROUTE) do Paths[i] = v end

	-- Encounter/catch/fight controls ({c="..."} route entries) live in a local table of ai/control.lua.
	local Control = require "ai.control"
	local i = 1
	while REFSTRAT_CONTROLS do
		local name, value = debug.getupvalue(Control.set, i)
		if not name then error("refstrat: controlFunctions not found") end
		if name == "controlFunctions" then
			for k, f in pairs(REFSTRAT_CONTROLS) do value[k] = f end
			break
		end
		i = i + 1
	end

	-- Strategies ({s="..."} route entries).
	for k, f in pairs(REFSTRAT_STRATEGIES or {}) do Strategies.functions[k] = f end

	-- Progress watchdog: replace the inherited split-number time table with candidate milestones.
	if REFSTRAT_MILESTONES then
		local Utils = require "util.utils"
		local Memory = require "util.memory"
		local counter, splits = 0, 0
		local originalUpdate = Utils.splitUpdate
		Utils.splitUpdate = function()
			splits = splits + 1
			return originalUpdate()
		end
		Utils.splitCheck = function()
			counter = counter + 1
			if counter < 600 then return end
			counter = 0
			local limit = REFSTRAT_MILESTONES[splits + 1]
			if limit and Utils.igt() > limit then
				p("refstrat watchdog: no split "..(splits + 1).." by "..limit.." s IGT; restarting", true)
				Strategies.reboot()
			end
		end
	end
	print("Upgrade loaded: refstrat loader (route entries "..#Paths..")")
end

-- v83: enforce the exact active next-split pace, using only runner frame counts.
do
	local Utils = require "util.utils"
	local prev = Utils.splitCheck
	assert(prev, "v83: splitCheck not found")
	Utils.splitCheck = function(...)
		if not EARLY_PACE_RESET then return prev(...) end
		if port_next_split_pace then
			local elapsed, limit, nextSplit = port_next_split_pace()
			if elapsed ~= nil and limit ~= nil and elapsed > limit then
				print("refstrat v83 EARLY_PACE_RESET: split " .. nextSplit ..
					" elapsed=" .. string.format("%.17g", elapsed) ..
					" > pace=" .. string.format("%.17g", limit))
				return Strategies.reboot()
			end
		end
		return prev(...)
	end
end
