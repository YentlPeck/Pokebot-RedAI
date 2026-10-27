-- v71 AGATHA_XSPC: decide once per battle (3+ X Specials: Lance and YOLO Lance keep 2; Blizzard PP left)
REFSTRAT_V71_XSPC_GO = function()
    if REFSTRAT_V71_XSPC_BID ~= REFSTRAT_BATTLE_ID then
        REFSTRAT_V71_XSPC_BID = REFSTRAT_BATTLE_ID
        local Inventory = require "storage.inventory"
        local xs, bp = Inventory.count("x_special"), Battle.pp("blizzard")
        REFSTRAT_V71_XSPC_OK = xs >= 3 and bp > 0
        print("refstrat v71 AGATHA_XSPC: X Special " .. xs .. ", Blizzard PP " .. bp .. " -> "
            .. (REFSTRAT_V71_XSPC_OK and "X Special instead of X Speed" or "keep X Speed (v69)"))
    end
    return REFSTRAT_V71_XSPC_OK
end
-- Agatha: keep the speed boost and recovery, omit prophylactic X Accuracy.
-- All actions still use the original controller/menu/item interfaces.
-- Applied only to this battle; original source remains pristine.
do
    local Combat = require "ai.combat"
    local Control = require "ai.control"
    local Inventory = require "storage.inventory"
    local Pokemon = require "storage.pokemon"
    local Memory = require "util.memory"

    -- BEGIN_PURE_AGATHA_FIX
    -- v52 AGATHA_FIX decision (DIAG9 #1: a Super Potion to 53 HP before the first Gengar's 56 Night Shade; repeated Supers
    -- while confused). s.hp/s.maxHP; s.worst = opponent's worst next non-critical hit (Night Shade = its level);
    -- s.selfHit = Gen 1 confusion self-hit; s.confused; s.tick = poison damage; s.supers/s.fulls in the bag; s.reserve =
    -- Full Restores kept for after Lance; s.sureKO = not confused, we move first and the best move's minimum roll KOs;
    -- s.healed = healing items already spent on this opponent Pokemon. Returns item (or nil = attack), reason, need.
    REFSTRAT_AGATHA_DECIDE = function(s)
        local need = s.worst + s.tick + (s.confused and s.selfHit or 0) + 1
        if s.hp >= need then return nil, "safe", need end
        if s.sureKO and not s.confused then return nil, "attack: sure KO before the opponent moves", need end
        local superHP = math.min(s.maxHP, s.hp + 50)
        local superOK = s.supers > 0 and superHP >= need
        if superOK and superHP - s.worst - s.tick >= need then return "super_potion", "Super survives two hits", need end
        local frOK = s.fulls > 0 and s.maxHP >= need
        if frOK and s.fulls > s.reserve then return "full_restore", "Super insufficient", need end
        if superOK and s.healed == 0 then return "super_potion", "Super survives the next hit (once per opponent)", need end
        if frOK and s.hp <= s.worst + s.tick then return "full_restore", "next hit kills: reserve Full Restore", need end
        return nil, superOK and "attack: another Super would be net-negative" or "attack: no allowed item survives", need
    end
    -- pokered core.asm HandleSelfConfusionDamage: 40 power, own Attack vs own Defense, no type/STAB/random, no critical
    REFSTRAT_AGATHA_SELFHIT = function(L, att, def)
        local floor = math.floor
        if att > 255 or def > 255 then att = floor(att / 4); def = floor(def / 4) end
        att, def = math.max(1, att), math.max(1, def)
        return math.min(997, floor(floor(floor(2 * L / 5 + 2) * att * 40 / def) / 50)) + 2
    end
    -- END_PURE_AGATHA_FIX

    local function w(a) return Memory.raw(a) * 256 + Memory.raw(a + 1) end
    REFSTRAT_AGATHA_FIX_ITEM = function()
        if Memory.raw(0x1014) ~= Pokemon.getID("nidoking") or w(0x0FE6) == 0 then return nil end
        local ours, enemy = Combat.activePokemon()
        local hp, maxHP = w(0x1015), w(0x1023)
        local worst = 0
        for _, m in ipairs(enemy.moves or {}) do
            local d = 0
            if m.id == 101 or m.id == 69 then d = enemy.level or 0       -- Night Shade / Seismic Toss: damage = level
            elseif m.id == 82 then d = 40                                -- Dragon Rage
            elseif m.id ~= 138 then local _, mx = Combat.calcRange(m, enemy, ours); d = mx or 0 end   -- not Dream Eater (asleep -> flute)
            if d > worst then worst = d end
        end
        local status = Memory.raw(0x1018)
        local confused = Combat.isConfused()
        local tick = 0
        if math.floor(status / 8) % 2 == 1 then                          -- poisoned; Toxic = wPlayerBattleStatus3 bit 0, counter $D06C
            tick = math.max(1, math.floor(maxHP / 16))
            if Memory.raw(0x1064) % 2 == 1 then tick = tick * (Memory.raw(0x106C) + 1) end
        end
        local sureKO = false
        if not confused and math.floor(status / 64) % 2 == 0 and w(0x1029) > w(0x0FFA) and w(0x1025) < 256 and w(0x102B) < 256 then
            local bm = Combat.bestMove()
            sureKO = (bm and (bm.damage or 0) >= w(0x0FE6) and (bm.accuracy or 100) >= 100) and true or false
        end
        local ekey = tostring(REFSTRAT_BATTLE_ID) .. ":" .. Memory.raw(0x0FE5) .. ":" .. Memory.raw(0x0FE8)
        local supers, fulls = Inventory.count("super_potion"), Inventory.count("full_restore")
        local st = REFSTRAT_AGATHA_FIX_ST
        if not st or st.ekey ~= ekey then st = {ekey = ekey, items = supers + fulls}; REFSTRAT_AGATHA_FIX_ST = st end
        local s = {hp = hp, maxHP = maxHP, worst = worst, tick = tick, confused = confused,
            selfHit = REFSTRAT_AGATHA_SELFHIT(Memory.raw(0x1022), w(0x1025), w(0x1027)), supers = supers, fulls = fulls,
            reserve = AGATHA_FIX_FR_RESERVE or 1, sureKO = sureKO, healed = math.max(0, st.items - supers - fulls)}
        local item, why, need = REFSTRAT_AGATHA_DECIDE(s)
        local key = ekey .. ":" .. hp .. ":" .. tostring(confused) .. ":" .. tostring(item)
        if (item or hp < need) and REFSTRAT_AGATHA_FIX_LOG ~= key then
            REFSTRAT_AGATHA_FIX_LOG = key
            print(string.format("refstrat AGATHA_FIX: hp %d/%d worst %d self %d tick %d%s need %d (Super %d, FR %d, reserve %d, healed %d) -> %s (%s)",
                hp, maxHP, worst, s.selfHit, tick, confused and " confused" or "", need, supers, fulls, s.reserve, s.healed, tostring(item or "attack"), why))
        end
        return item
    end

    Strategies.functions.agatha = function()
        if Strategies.trainerBattle() then
            if Combat.isSleeping() then
                Inventory.use("pokeflute", nil, true)
                return false
            end
            if AGATHA_FIX and not Control.yolo then   -- v52: survival-checked heal (replaces AGATHA_SAFE and the Gengar heal)
                local item = REFSTRAT_AGATHA_FIX_ITEM()
                if item then
                    Inventory.use(item, nil, true)
                    return false
                end
            elseif AGATHA_SAFE and not Control.yolo then   -- v27: confusion-aware heal, also after X Speed
                local hp = Pokemon.info("nidoking", "hp")
                if (Combat.isConfused() and hp <= 80) or hp <= 56 then
                    local potion = Inventory.contains("super_potion", "full_restore")
                    if potion then
                        local key = tostring(REFSTRAT_BATTLE_ID) .. ":" .. hp
                        if REFSTRAT_AGATHA_SAFE_LOG ~= key then
                            REFSTRAT_AGATHA_SAFE_LOG = key
                            print("refstrat AGATHA_SAFE: heal " .. potion .. " at hp " .. hp .. (Combat.isConfused() and " (confused)" or ""))
                        end
                        Inventory.use(potion, nil, true)
                        return false
                    end
                end
            end
            if Pokemon.isOpponent("gengar") then
                -- refstrat-v18 edit S: decision logging (pass-through REFSTRAT_SCRIPT)
                local hp = Pokemon.info("nidoking", "hp")
                local trig = not Control.yolo and hp <= 56 and not Strategies.isPrepared("x_speed")
                if not trig and REFSTRAT_SCRIPT then REFSTRAT_SCRIPT("agatha-v1-gengar", false, false, nil, "hp "..tostring(hp).." (<= 56, not yolo, X Speed not set: false)") end
                if not AGATHA_FIX and not Control.yolo and Pokemon.info("nidoking", "hp") <= 56
                    and not Strategies.isPrepared("x_speed") then
                    local potion = Inventory.contains("full_restore", "super_potion")
                    if (REFSTRAT_SCRIPT and REFSTRAT_SCRIPT("agatha-v1-gengar", potion, true, potion, "hp "..tostring(hp))) or (not REFSTRAT_SCRIPT and potion) then
                        Inventory.use(potion, nil, true)
                        return false
                    end
                end
                -- v71 (experiments/v71-2026-10-20). Gengar 1 (137) moves before us (132) with or without X Speed;
                -- X Speed only stops Gengar 2 (146) from moving first, and costs a turn.
                -- AGATHA_XSPC: X Special on that turn instead (Blizzard then knocks out Golbat in one hit).
                -- AGATHA_NO_XS: no item at all.
                if AGATHA_XBOTH and REFSTRAT_V71_XSPC_GO() then   -- v72 build 2
                    if not Strategies.prepare("x_speed", "x_special") then return false end
                elseif AGATHA_XSPC and REFSTRAT_V71_XSPC_GO() then
                    if not Strategies.prepare("x_special") then return false end
                elseif AGATHA_NO_XS then
                    local key = tostring(REFSTRAT_BATTLE_ID)
                    if REFSTRAT_V71_XS_LOG ~= key then
                        REFSTRAT_V71_XS_LOG = key
                        print("refstrat v71 AGATHA_NO_XS: no X Speed against Gengar (v69 would use one)")
                    end
                elseif not Strategies.prepare("x_speed") then
                    return false
                end
            end
            -- Restore accuracy if an opponent actually lowered it.
            if Combat.sandAttacked() and not Strategies.prepare("x_accuracy") then
                return false
            end
            if (AGATHA_XSPC or AGATHA_XBOTH) and REFSTRAT_V71_XSPC_BID == REFSTRAT_BATTLE_ID and REFSTRAT_V71_XSPC_OK and Pokemon.isOpponent("golbat")
                and Battle.pp("blizzard") > 0 and Strategies.isPrepared("x_special") then
                if REFSTRAT_V71_BLIZ_LOG ~= tostring(REFSTRAT_BATTLE_ID) then
                    REFSTRAT_V71_BLIZ_LOG = tostring(REFSTRAT_BATTLE_ID)
                    print("refstrat v71 AGATHA_XSPC: Blizzard on Golbat after X Special (v69 would use Thunderbolt)")
                end
                Battle.automate("blizzard")
            else
                Battle.automate()
            end
        elseif Strategies.status.foughtTrainer then
            return true
        end
    end
    print("Upgrade loaded: agatha-v1, reactive accuracy setup")
end

-- v72 AGATHA_HEAL2 (experiments/v72-2026-10-20): wraps REFSTRAT_AGATHA_DECIDE (looked up at call time).
do
    local Memory = require "util.memory"
    local function w(a) return Memory.raw(a) * 256 + Memory.raw(a + 1) end
    local prevDecide = REFSTRAT_AGATHA_DECIDE
    assert(prevDecide, "v72: REFSTRAT_AGATHA_DECIDE not found")
    REFSTRAT_AGATHA_DECIDE = function(s)
        local item, why, need = prevDecide(s)
        if not AGATHA_HEAL2 or item or s.healed == 0 or s.hp >= need then return item, why, need end
        if w(0x0FFA) < w(0x1029) then return item, why, need end      -- we move first: keep the v71 rule
        local t = {}
        for k, v in pairs(s) do t[k] = v end
        t.healed = 0
        local item2, why2, need2 = prevDecide(t)
        if item2 then
            local key = tostring(REFSTRAT_BATTLE_ID) .. ":" .. s.hp .. ":" .. tostring(item2)   -- build 3: log once
            if REFSTRAT_V72_HEAL2_LOG ~= key then
                REFSTRAT_V72_HEAL2_LOG = key
                print(string.format("refstrat v72 AGATHA_HEAL2: hp %d, opponent moves first (speed %d >= %d) -> %s again (v71: attack)",
                    s.hp, w(0x0FFA), w(0x1029), item2))
            end
            return item2, why2 .. " [v72: opponent moves first, heal again]", need2
        end
        return item, why, need
    end
end
