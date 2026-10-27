local Utils = {}

local Memory = require "util.memory"
local Strategies
local Data = require "data.data"

local EMP = 1
local splitCheck = 0
local splitNum = 1

-- GLOBAL

function p(...)
	local string
	if #arg == 0 then
		string = arg[0]
	else
		string = ""
		for __,str in ipairs(arg) do
			if str == true then
				string = string.."\n"
			else
				string = string..str.." "
			end
		end
	end
	print(string)
end

-- GENERAL

function Utils.reset()
	splitCheck = 0
	splitNum = 1
end

function Utils.splitUpdate()
	splitNum = splitNum + 1
end

function Utils.dist(x1, y1, x2, y2)
	return math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2))
end


function Utils.match(needle, haystack)
	for __,val in ipairs(haystack) do
		if needle == val then
			return true
		end
	end
	return false
end


function Utils.capitalize(string)
	return string:sub(1, 1):upper()..string:sub(2)
end

function Utils.nextCircularIndex(index, direction, totalCount)
	local nextIndex = index + direction
	if nextIndex < 1 then
		nextIndex = totalCount
	elseif nextIndex > totalCount then
		nextIndex = 1
	end
	return nextIndex
end

function Utils.append(string, appendage, separator)
	if not string then
		return appendage
	end
	return string..separator..appendage
end


function Utils.pluralize(amount, description)
	if amount ~= 1 then
		description = description.."s"
	end
	return amount.." "..description
end

function Utils.random(items)
	return items[math.random(1, #items)]
end

-- GAME

function Utils.canPotionWith(potion, forDamage, curr_hp, max_hp)
	if curr_hp > max_hp - 3 then
		return false
	end
	local potion_hp
	if potion == "full_restore" then
		potion_hp = 9001
	elseif potion == "super_potion" then
		potion_hp = 50
	else
		potion_hp = 20
	end
	return math.min(curr_hp + potion_hp, max_hp) > forDamage
end

function Utils.ingame()
	return Memory.raw(0x020E) > 0
end

function Utils.drawText(x, y, message, right)
	if right then
		x = x - #message * 5
	end
	gui.text(x * EMP, y * EMP, message)
end

-- TIME


function Utils.init()
	Strategies = require("ai."..Data.gameName..".strategies")
end

return Utils
