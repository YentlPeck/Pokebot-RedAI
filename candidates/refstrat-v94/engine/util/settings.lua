local Settings = {}

local Textbox = require "action.textbox"
local Strategies = require "ai.strategies"

local Data = require "data.data"

local Bridge = require "util.bridge"
local Input = require "util.input"
local Memory = require "util.memory"
local Menu = require "util.menu"

local START_WAIT = 99

local settings_menu
settings_menu = 94

local desired = {}
desired.text_speed = 1
desired.battle_animation = 10
desired.battle_style = 10

local function isEnabled(name)

	return Memory.value("setting", name) == desired[name]
end

-- PUBLIC

function Settings.set(...)
	for __,name in ipairs(arg) do
		if not isEnabled(name) then
			if Menu.open(settings_menu, 1) then
				Menu.setOption(name, desired[name])
			end
			return false
		end
	end
	return Menu.cancel(settings_menu)
end

function Settings.startNewAdventure()
	local startMenu, withBattleStyle
	if Data.gameName ~= "red" then
		withBattleStyle = "battle_style"
	end
	startMenu = Memory.value("player", "name") ~= 0
	if startMenu and Menu.getCol() ~= 0 then
		if Settings.set("text_speed", "battle_animation", withBattleStyle) then
			Menu.select(0)
		end
	elseif math.random(0, START_WAIT) == 0 then
		Input.press("Start", 2)
	end
end

function Settings.choosePlayerNames()
	local name
	if Memory.value("player", "name2") == 80 then
		name = Data.gameName == "red" and "E" or "W"
	else
		name = "B"
	end
	Textbox.name(name, true)
end

function Settings.pollForResponse(forcedName)
	local response = Bridge.process()
	if not INTERNAL or Strategies.replay then
		response = forcedName
	elseif response then
		response = tonumber(response)
		Data.run.voted_for_name = true
	end
	if response then
		Bridge.polling = false
		Textbox.setName(response)
	end
end

return Settings
