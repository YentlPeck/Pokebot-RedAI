local Battle = {}

local Textbox = require "action.textbox"

local Combat = require "ai.combat"
local Control = require "ai.control"

local Memory = require "util.memory"
local Menu = require "util.menu"
local Input = require "util.input"
local Utils = require "util.utils"

local Inventory = require "storage.inventory"
local Pokemon = require "storage.pokemon"

-- HELPERS

local function potionsForHit(potion, curr_hp, max_hp)
	if not potion then
		return
	end
	local ours, killAmount = Combat.inKillRange()
	if ours then
		if Control.yolo and killAmount > 6 and killAmount == curr_hp then
			return false
		end
		return Utils.canPotionWith(potion, killAmount, curr_hp, max_hp)
	end
end

-- refstrat-v18: one decision line per threatened battle turn. Turn key: map, opponent, opponent HP, our HP, PP sum,
-- healing-item total, encounter b and committed-turn count a (the count, not the state values, separates turns).
local function refTurnKey(curr_hp)
	local pp = 0
	for i = 0, 3 do pp = pp + Memory.raw(0x102D + i) % 64 end
	local items = 0
	for _, it in ipairs({"potion", "super_potion", "hyper_potion", "full_restore"}) do items = items + Inventory.count(it) end
	return Memory.value("game", "map")..":"..tostring(Memory.value("battle", "opponent_id"))..":"..tostring(Memory.double("battle", "opponent_hp"))
		..":"..curr_hp..":pp"..pp..":items"..items..":b"..tostring(REFSTRAT_BATTLE_ID or 0)..":a"..tostring(REFSTRAT_ACTION_CYCLE or 0)
end
REFSTRAT_TURN_KEY = refTurnKey
-- edit L3: an opportunity exists only while the game waits for our action (main battle menu 94, move list 106 or item
-- list 233, no battle text); recover() is also evaluated during animations and text, where no action is chosen
function REFSTRAT_ACTION_PENDING()
	if Memory.value("battle", "text") == 1 then return false end
	local m = Memory.value("battle", "menu")
	return m == 94 or m == 106 or m == 233
end
-- edit O..AA: encounter id and committed-turn count (logging state only). The decision at each main-menu return after
-- battle text uses the chosen battle-menu entry (wBattleAndStartSavedMenuItem), the move list, other menus, the run
-- counter, the message prefix and the state signature below on every frame of the interval (tools/edit_c10_aa.py).
local function refSignature()
	local bag = 0
	for i = 0, Memory.raw(0x131D) - 1 do bag = bag + Memory.raw(0x131F + 2 * i) end
	-- edit W3: party HP total and the active party slot (a sacrificial switch-in that faints changes the party HP even
	-- when the returning Pokemon's HP is unchanged)
	local party = 0
	for i = 0, Memory.raw(0x1163) - 1 do party = party + Memory.raw(0x116B + 44 * i + 1) * 256 + Memory.raw(0x116B + 44 * i + 2) end
	-- edit Z: run attempts (wNumRunAttempts) are not part of the signature (FIGHT clears them); see escapeSeen (edit AD)
	return bag..":"..Memory.raw(0x1014)..":"..Memory.raw(0x1018)..":"..Combat.hp()..":"..tostring(Memory.double("battle", "opponent_hp"))
		..":"..party..":"..Memory.raw(0x0C2F)..":"..Memory.raw(0x0FE5)   -- edit AB: + enemy species
end
do
	-- edit X/Y/Z/AA: committed-turn tracker (see tools/edit_c10_aa.py). Per interval between main-menu returns:
	-- moveSeen/gap94 = move list shown and main-menu frames since; otherMenu = another menu (bag, party) since;
	-- changed = some frame off the menus had a state signature different from the turn's base (lastSig).
	local sawText, moveSeen, gap94, lastSig = true, false, 0, nil
	local otherMenu, otherAtText, savedAtText = false, false, nil
	local refusal, oakText, changed = false, false, false
	local prevRuns, escapeSeen = 0, false   -- edit AD: per-frame run-counter increase = failed escape
	-- edit V: called by the adapter after every emulated frame (refstrat_adapter.py advance)
	function REFSTRAT_FRAME_OBSERVE()
		local battleState = Memory.value("game", "battle")
		local inb = battleState and battleState > 0
		if inb and not REFSTRAT_INB then
			REFSTRAT_BATTLE_ID = (REFSTRAT_BATTLE_ID or 0) + 1
			REFSTRAT_ACTION_CYCLE = 0
			sawText, moveSeen, gap94, lastSig = true, false, 0, nil
			otherMenu, otherAtText, savedAtText = false, false, nil
			refusal, oakText, changed = false, false, false
			prevRuns, escapeSeen = Memory.raw(0x1120), false
		end
		REFSTRAT_INB = inb
		if not inb then return end
		local runs = Memory.raw(0x1120)
		if runs > prevRuns then escapeSeen = true end
		prevRuns = runs
		local text = Memory.value("battle", "text") == 1
		local m = Memory.value("battle", "menu")
		local onMenu = (not text) and (m == 94 or m == 106)
		if lastSig and not onMenu and not changed and refSignature() ~= lastSig then changed = true end
		-- edit AB: a message box counts as battle text only once it shows a character (PrintEmptyString redraws are blank)
		local c1, c2, c3 = Memory.raw(0x04B9), Memory.raw(0x04BA), Memory.raw(0x04BB)
		-- a blank message box before any character (a redraw, or a message about to print) is neutral: neither text nor a
		-- menu observation
		if text and c1 == 0x7F and not sawText then return end
		if text then
			if not sawText then
				otherAtText, savedAtText = otherMenu, Memory.raw(0x0C2D)
				refusal, oakText = false, false
			end
			sawText = true
			-- message prefix on every text frame (letters appear one by one)
			if c1 == 141 and c2 == 174 and c3 == 231 then refusal = true end     -- "No!" (trainer RUN refusal)
			if c1 == 0x8E and c2 == 0x80 and c3 == 0x8A then oakText = true end  -- "OAK" (item use refused)
		elseif m == 106 then
			-- move list (after text: a rejected no-PP / disabled move, not a turn)
			sawText, moveSeen, gap94, otherMenu = false, true, 0, false
		elseif m == 94 then
			if sawText then
				local sig = refSignature()
				local reason, committed = nil, false
				local escaped = escapeSeen
				local safari = Memory.raw(0x105A) == 2
				local fight = savedAtText == 0 and not otherAtText and not safari and not refusal
				if lastSig == nil or sig ~= lastSig or changed or escaped or fight then
					committed = true
				elseif savedAtText == 1 and otherAtText and not oakText then
					committed, reason = true, "item used without a state change (text is not the 'OAK: ... not the time' refusal)"
				elseif safari then
					-- edit AC: Safari menus (BALL/BAIT/ROCK/RUN) have other meanings; an action without a state change is flagged
					committed, reason = true, "Safari battle action without a state change"
				end
				if committed then
					REFSTRAT_ACTION_CYCLE = (REFSTRAT_ACTION_CYCLE or 0) + 1
					print("refstrat TURN b="..REFSTRAT_BATTLE_ID.." t="..REFSTRAT_ACTION_CYCLE)
					if reason then print("refstrat TURN-AMBIGUOUS b="..REFSTRAT_BATTLE_ID.." t="..REFSTRAT_ACTION_CYCLE.." reason="..reason) end
				end
				sawText, moveSeen, gap94 = false, false, 0
				otherMenu, otherAtText, savedAtText = false, false, nil
				refusal, oakText, changed, escapeSeen = false, false, false, false
				lastSig = sig
			else
				gap94 = gap94 + 1
				if gap94 >= 3 then moveSeen = false end
			end
		elseif m == 233 and sawText and Memory.value("battle", "text") ~= 1 then
			-- edit AB: back in the bag list after text (failed item use): a fresh interval inside the same bag visit
			sawText, refusal, oakText, otherMenu = false, false, false, true
		elseif not sawText then
			otherMenu = true
		end
	end
end
-- edit P: pass-through decision logger for the engine's scripted in-battle heals (returns `result` unchanged)
function REFSTRAT_SCRIPT(site, result, trigger, item, detail)
	if REFSTRAT_ACTION_PENDING() then
		local d = result and ("heal "..tostring(item)) or (trigger and "no heal (no item)" or "no heal (trigger false)")
		local key = refTurnKey(Combat.hp())
		local k = site.."|"..key.."|"..d
		if REFSTRAT_SCRIPT_LAST ~= k then
			REFSTRAT_SCRIPT_LAST = k
			local info = debug and debug.getinfo and debug.getinfo(2, "Sl")
			local src = tostring(info and info.short_src):gsub("\\", "/"):gsub('[%s"%[%]]', '')
			local caller = info and ((src:match("([^/]+/[^/]+)$") or src)..":"..tostring(info.currentline)) or "?"
			print("refstrat SCRIPT-OPP site="..site.." turn="..key.." hp "..Combat.hp().."/"..Combat.maxHP().." strategy="..tostring(REFSTRAT_CUR_STRATEGY)
				.." caller="..caller.." trigger="..tostring(detail).." -> "..d)
		end
	end
	return result
end
local function refOpportunity(curr_hp, max_hp, decision)
	if not REFSTRAT_ACTION_PENDING() then return end
	local key = refTurnKey(curr_hp)
	-- edit L2: a decision that changes within the same turn (the strategy re-enables healing) is logged again
	if REFSTRAT_RECOVER_TURN ~= key.."|"..decision then
		REFSTRAT_RECOVER_TURN = key.."|"..decision
		print("refstrat RECOVER-OPP turn="..key.." hp "..curr_hp.."/"..max_hp.." strategy="..tostring(REFSTRAT_CUR_STRATEGY).." -> "..decision)
	end
end

local function recover()
	if not Control.canRecover() then
		local curr_hp, max_hp = Combat.hp(), Combat.maxHP()
		if curr_hp > 0 and curr_hp < max_hp and Combat.inKillRange() then
			refOpportunity(curr_hp, max_hp, "no heal (in-battle healing disabled: strategy switch, yolo or not the main fighter)")
		end
	else
		local curr_hp = Combat.hp()
		if curr_hp > 0 then
			local max_hp = Combat.maxHP()
			if curr_hp < max_hp then
				local first, second
				if Control.preferredPotion == "full" then
					first, second = "full_restore", "super_potion"
					if max_hp - curr_hp > 54 then
						first = "full_restore"
						second = "super_potion"
					else
						first = "super_potion"
						second = "full_restore"
					end
				else
					if Control.preferredPotion == "super" or max_hp - curr_hp > 22 then
						first = "super_potion"
						second = "potion"
					else
						first = "potion"
						second = "super_potion"
					end
				end
				local potion = Inventory.contains(first, second)
				local heal = potionsForHit(potion, curr_hp, max_hp)
				if heal and RISK_HEAL and Combat.koProbability and not (RISK_HEAL_CONF and Combat.isConfused()) then   -- v44 conf fix   -- v35 = v25 RISK_HEAL: skip unlikely-KO heals
					local pko = Combat.koProbability()
					if pko < RISK_HEAL then
						local key = tostring(REFSTRAT_BATTLE_ID) .. ":" .. curr_hp
						if REFSTRAT_RISKHEAL_LOG ~= key then
							REFSTRAT_RISKHEAL_LOG = key
							print(string.format("refstrat RISKHEAL: skip in-battle heal, KO chance %.2f < %.2f (hp %d/%d)", pko, RISK_HEAL, curr_hp, max_hp))
						end
						heal = false
					end
				end
				if Combat.inKillRange() then
					refOpportunity(curr_hp, max_hp, heal and ("RECOVERY heal "..tostring(potion))
						or (potion and "no heal (the item does not survive the hit)" or "no heal (no healing item)"))
				end
				if heal then
					-- refstrat-v16: logged RECOVERY (trigger: the opponent can KO this turn and the item survives the hit)
					local map = Memory.value("game", "map")
					local key = map..":"..curr_hp..":"..tostring(potion)
					if REFSTRAT_RECOVER_LOG ~= key then
						REFSTRAT_RECOVER_LOG = key
						print("refstrat RECOVERY in-battle heal (trigger: opponent can KO this turn, "..tostring(potion).." survives it): map "
							..map.." hp "..curr_hp.."/"..max_hp)
					end
					REFSTRAT_ITEM_SOURCE = "recover"
					Inventory.use(potion, nil, true)
					REFSTRAT_ITEM_SOURCE = nil
					return true
				end
			end
		end
	end
	if Combat.isParalyzed() and not Control.canDie() then
		local heals = Inventory.contains("paralyze_heal", "full_restore")
		-- refstrat-v18 (cycle 2): before the League the Full Restore (reference: after Lance) is not spent on paralysis;
		-- every paralysis decision is logged once per battle turn (attribution of in-battle item use)
		local map = Memory.value("game", "map")
		local LEAGUE = REFSTRAT_LEAGUE_MAPS or {}
		if heals == "full_restore" and not LEAGUE[map] then heals = nil end
		local key = refTurnKey(Combat.hp())
		if REFSTRAT_PARA_TURN ~= key and REFSTRAT_ACTION_PENDING() then   -- edit Y2: only while the game waits for our action
			REFSTRAT_PARA_TURN = key
			print("refstrat PARALYSIS-OPP turn="..key.." strategy="..tostring(REFSTRAT_CUR_STRATEGY).." -> "..(heals and ("RECOVERY cure "..heals) or "no cure (no Parlyz Heal; Full Restore kept for after Lance)"))
		end
		if heals then
			REFSTRAT_ITEM_SOURCE = "paralysis"
			Inventory.use(heals, nil, true)
			REFSTRAT_ITEM_SOURCE = nil
			return true
		end
	end
end

local function openBattleMenu()
	if Memory.value("battle", "text") == 1 then
		Input.cancel()
		return false
	end
	local battleMenu = Memory.value("battle", "menu")
	local col = Menu.getCol()
	if battleMenu == 106 or (battleMenu == 94 and col == 5) then
		return true
	elseif Menu.onBattleSelect(battleMenu) then
		local rowSelected = Memory.value("menu", "row")
		if col == 9 then
			if rowSelected == 1 then
				Input.press("Up")
			else
				Input.press("A")
			end
		else
			Input.press("Left")
		end
	else
		Input.press("B")
	end
end

local function attack(attackIndex)
	if not Battle.opponentAlive() then
		Input.cancel()
	elseif openBattleMenu() then
		Menu.select(attackIndex, true, false, false, false, 3)
	end
end

-- refstrat-v5 fix (ENGINE_CHANGES.md #1): usable PP = low 6 bits (the top 2 bits count PP Ups; an exhausted Horn
-- Drill with one PP Up is byte 64 = 0 usable). In battle the battle copy is current; outside battle it can be stale
-- (e.g. after a TM), so the lead's party data is used.
print("refstrat-v9 private engine loaded (ENGINE_CHANGES.md)")
local function movePP(name)
	if Memory.value("game", "battle") > 0 then
		local midx = Pokemon.battleMove(name)
		if not midx then
			return 0
		end
		return Memory.raw(0x102C + midx) % 64
	end
	local slot = Pokemon.moveIndex(name)
	if not slot then
		return 0
	end
	return Memory.raw(0x116B + 28 + slot) % 64
end
Battle.pp = movePP

-- UTILS

function Battle.swapMove(move, toIndex)
	toIndex = toIndex + 1
	if openBattleMenu() then
		local moveIndex = Pokemon.battleMove(move)
		if not moveIndex or moveIndex == toIndex then
			return true
		end
		local selection = Memory.value("menu", "selection_mode")
		local swapSelect
		if selection == toIndex then
			swapSelect = moveIndex
		else
			swapSelect = toIndex
		end
		local menuSize = Memory.raw(0x101F) == 0 and 3 or 4
		if Menu.select(swapSelect, true, false, nil, true, menuSize) then
			Input.press("Select")
		end
	end
end

function Battle.isActive()
	return Memory.value("game", "battle") > 0
end

function Battle.isTrainer()
	return Memory.value("game", "battle") == 2
end

function Battle.opponent()
	return Pokemon.getName(Memory.value("battle", "opponent_id"))
end

function Battle.deployed()
	return Pokemon.getName(Memory.value("battle", "our_id"))
end

function Battle.opponentAlive()
	return Memory.double("battle", "opponent_hp") > 0
end

function Battle.damaged(factor)
	if not factor then
		factor = 1
	end
	return Combat.hp() * factor < Combat.maxHP()
end

function Battle.opponentDamaged(factor)
	if not factor then
		factor = 1
	end
	return Memory.double("battle", "opponent_hp") * factor < Memory.double("battle", "opponent_max_hp")
end

-- HANDLE

function Battle.run()
	if not Battle.opponentAlive() then
		Input.cancel()
	elseif not Menu.onBattleSelect() then
		if Memory.value("menu", "text_length") == 127 then
			Input.press("B")
		else
			Input.cancel()
		end
	elseif Textbox.handle() then
		local selected = Memory.value("menu", "selection")
		if selected == 239 then
			Input.press("A", 2)
		elseif selected == 233 then
			Input.press("Right")
		else
			Input.escape()
		end
	end
end

function Battle.handle()
	if not Control.shouldCatch() then
		if Control.shouldFight() then
			Battle.fight()
		else
			Battle.run()
		end
	end
end

function Battle.handleWild(battleStatus)
	if not battleStatus then
		battleStatus = Memory.value("game", "battle")
	end
	if battleStatus ~= 1 then
		return true
	end
	Battle.handle()
end

function Battle.fight(move)
	local moveIndex
	if move then
		local disableCheck
		if type(move) == "string" then
			disableCheck = move
			moveIndex = Pokemon.battleMove(move)
		else
			disableCheck = move.id
			Battle.accurateAttack = move.accuracy == 100
			moveIndex = move.midx
		end
		if Combat.isDisabled(disableCheck) then
			move = nil
		end
	end
	if not move then
		move = Combat.bestMove()
		if move then
			Battle.accurateAttack = move.accuracy == 100
			moveIndex = move.midx
		else
			moveIndex = nil
		end
	end

	if moveIndex then
		attack(moveIndex)
	elseif Memory.value("menu", "text_length") == 127 then
		Input.press("B")
	else
		Input.cancel()
	end
end

function Battle.swap(target)
	if Menu.onPokemonSelect() then
		if Menu.getCol() == 0 then
			Pokemon.select(target)
		else
			Input.press("A")
		end
	elseif Menu.onBattleSelect() then
		local selected = Memory.value("menu", "selection")
		if selected == 199 then
			Input.press("A", 2)
		elseif Menu.getCol() == 9 then
			Input.press("Right", 0)
		else
			Input.press("Up", 0)
		end
	else
		Input.cancel()
	end
end

function Battle.automate(moveName, skipBuffs)
	if not recover() then
		local state = Memory.value("game", "battle")
		if state == 0 then
			Input.cancel()
		else
			if moveName and movePP(moveName) == 0 then
				moveName = nil
			end
			if state == 1 then
				if Control.shouldFight() then
					Battle.fight(moveName, skipBuffs)
				else
					Battle.run()
				end
			elseif state == 2 then
				Battle.fight(moveName, skipBuffs)
			end
		end
	end
end

-- SACRIFICE

function Battle.sacrifice(...)
	local sacrifice = Pokemon.getSacrifice(...)
	if sacrifice then
		Battle.swap(sacrifice)
		return true
	end
	return false
end

function Battle.redeployNidoking()
	if Pokemon.isDeployed("nidoking") then
		Control.ignoreMiss = false
		return false
	end
	Control.ignoreMiss = true
	if Menu.onPokemonSelect() then
		Pokemon.select("nidoking")
	elseif Menu.canCloseMessage() and Menu.getCol() == 1 then
		Input.press("A")
	else
		local forced
		local __, turns = Combat.bestMove()
		if turns == 1 then
			if Pokemon.isDeployed("spearow") then
				forced = "growl"
			elseif Pokemon.isDeployed("squirtle") then
				forced = "tail_whip"
			else
				forced = "sand_attack"
			end
		end
		Battle.automate(forced)
	end
	return true
end

return Battle
