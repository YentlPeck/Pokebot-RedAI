-- Menu input latency, whole game (blue-v14 already does the first part from Bruno on).
-- 1. Menu.select confirms with a one-frame A instead of a two-frame A. The
--    same-button release frame in util/input.lua is kept, so a repeated A still
--    gets its release frame, and selection only happens once the row matches.
-- 2. Cursor moves always tap (press, release, press) instead of holding the
--    direction, which otherwise waits for the game's 30-frame auto-repeat delay.
-- Same menus, same choices; controller input only.
-- 3. If a confirm is requested again for the same menu state within a few frames
--    (the one-frame A fell into a redraw delay), hold A for three frames instead.
do
	local Menu = require "util.menu"
	local Input = require "util.input"
	local Memory = require "util.memory"
	local selecting = false
	local lastConfirm, lastFrame = nil, -100
	local originalSelect = Menu.select
	local originalPress = Input.press
	local originalBalance = Menu.balance
	local originalSidle = Menu.sidle
	local function menuState()
		return Memory.value("menu", "main")..","..Menu.getCol()..","..Memory.value("menu", "row")..","
			..Memory.value("menu", "scroll_offset")..","..Memory.value("battle", "menu")
	end
	Input.press = function(button, frames, walk)
		if selecting and button == "A" and frames == 2 then
			local state, now = menuState(), emu.framecount()
			if state == lastConfirm and now - lastFrame <= 8 then
				frames = 3
			else
				frames = 1
			end
			lastConfirm, lastFrame = state, now
		end
		return originalPress(button, frames, walk)
	end
	Menu.select = function(...)
		selecting = true
		local value = originalSelect(unpack(arg))
		selecting = false
		return value
	end
	Menu.balance = function(current, desired, inverted, looping, throttle)
		return originalBalance(current, desired, inverted, looping, true)
	end
	Menu.sidle = function(current, desired, looping, throttle)
		return originalSidle(current, desired, looping, true)
	end
	print("Upgrade loaded: menu-taps-v101, one-frame confirms and tapped cursor moves")
end
