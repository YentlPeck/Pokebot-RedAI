-- refstrat candidate route table (starts as an exact copy of the baseline route; edited per REFERENCE_STRATEGY.md)
-- Progress watchdog (loader.lua): IGT limit (s) by which split N must be reached. The inherited table assumes the
-- baseline route's split order and pace; development value: generous (2 h) everywhere. Evaluation value: see PLAN.md.
REFSTRAT_MILESTONES = REFSTRAT_MILESTONES or setmetatable({}, {__index = function() return 7200 end})

REFSTRAT_ROUTE = {

	-- Red's room
	{38, {3,6}, {s="refClockSync"}, {5,6}, {5,1}, {7,1}},   -- v11: clock tracker sync (first control in Red's room)
	-- Red's house
	{39, {7,1}, {7,6}, {3,6}, {3,8}},
	-- Into the Wild
	{0, {5,6}, {10,6}, {10,1}},
	-- Choose your character!
	{40, {5,3}, {c="a",a="Pallet Rival"}, {5,4}, {7,4}, {s="squirtleIChooseYou"}, {5,4}, {5,6}, {s="fightBulbasaur"}, {s="split"}, {5,12}},

-- 1: RIVAL 1

	-- Let's try this escape again
	{0, {12,12}, {c="a",a="Pallet Town"}, {c="refViridianExp"}, {c="encounters",limit=3}, {c="trackEncounters",area="route1"}, {9,12}, {9,2}, {10,2}, {10,-1}},
	-- First encounters
	{12, {10,35}, {10,30}, {8,30}, {8,24}, {12,24}, {12,20}, {9,20}, {9,14}, {14,14}, {s="dodgePalletBoy"}, {14,2}, {10,2}, {10,-1}},
	-- To the Mart
	{1, {20,35}, {20,28}, {19,28}, {19,20}, {29,20}, {29,19}},
	-- Viridian Mart
	{42, {2,5}, {3,5}, {3,8}},
	-- Backtracking
	{1, {29,20}, {c="encounters",limit=4}, {29,21}, {26,21}, {26,30}, {20,30}, {20,36}},
	-- Parkour
	{12, {10, 0}, {10,3}, {8,3}, {8,18}, {9,18}, {9,21}, {12,21}, {12,24}, {10,24}, {10,36}},
	-- To Oak's lab
	{0, {10,0}, {10,7}, {9,7}, {9,12}, {12,12}, {12,11}},
	-- Parcel delivery
	{40, {5,11}, {5,3}, {4,3}, {4,1}, {5,1}, {s="talk",dir="Down"}, {4,1}, {4,12}},
	-- Leaving home
	{0, {12,12}, {c="refViridianExp",backup=true}, {c="encounters",limit=5}, {9,12}, {9,2}, {10,2}, {10,-1}},
	-- The grass again!?
	{12, {10,35}, {10,30}, {8,30}, {8,24}, {12,24}, {12,20}, {9,20}, {9,14}, {14,14}, {s="dodgePalletBoy"}, {14,2}, {10,2}, {10,-1}},
	-- Back to the Mart
	{1, {20,35}, {20,28}, {19,28}, {19,20}, {29,20}, {29,19}},
	-- Viridian Mart redux
	{42, {3,7}, {3,5}, {2,5}, {s="refShopViridian"}, {3,5}, {3,8}}, -- reference 3 Poke Balls (5:36); v19: exactly 3
	-- Sidequest. v8: the reference Nidoran manip (GUIDES.md 5): SAVE on Viridian (7,18) facing Left, power cycle, then
	-- the post-reset CHAIN (lua/chain.lua, S.refChain): reference path with 7 A presses to the Route 22 grass (33,11),
	-- Nidoran L4 in one ball (nickname "A"), split, reference path through Viridian to the Route 2 grass, Pidgey L5 in one
	-- ball, gate, reference forest path (Antidote, no hidden Potion before the Bug Catcher), talk to him from (2,19).
	-- Before the save, logged RECOVERY steps that the reference does not take: Viridian Center heal (Squirtle below full
	-- HP), Route 22 EXP detour (Squirtle < 215 EXP) and the Viridian tree Potion; none changes the post-reset inputs.
	-- Replaces the v7 entries Route 22 (save at (38,9)), Route 2 manipWalk, gate and forest detour.
	-- v14 (FINDINGS F4): the Forest outcome class depends on Squirtle's exact HP at the save (offline: same save, HP 23/23
	-- -> reference outcome, 15/23 or 22/23 -> wild encounter). The full-HP heal check is repeated after the Route 22 EXP
	-- detour (which can leave Squirtle below full), so every save is made at full HP. Same logged recovery, same rule.
	-- v14 (implementation + protocol review 12:46, MATERIAL): the unchanged Forest criterion requires "no Viridian tree
	-- Potion" (the reference skips it); the v8 recovery {s="refTreePotion"} at (17,4) is removed (same tiles walked).
	{1, {29,20}, {c="trackEncounters",area="nidoran"}, {c="a",a="Nidoran grass"}, {s="refViridianHealIf", full=true}, {s="refSquirtleExpIf"}, {s="refViridianHealIf", full=true, after=true}, {18,20}, {18,16}, {18,6}, {s="dodgeViridianOldMan"}, {17,4}, {18,4}, {18,16}, {15,20}, {15,18}, {4,18}, {4,15}, {2,15}, {2,16}, {-1,16}},
	-- v9: Route 22 and straight back, so Viridian reloads its NPCs at their map-load state (v9 FINDINGS: the saved
	-- sprite state - the wandering Youngster (13,20) and old man (17,5) seen during the errands - decided whether the
	-- post-reset chain met the Nidoran); then (7,18) from the west, where no wandering NPC comes on screen, and a turn
	-- in place to face Left (reference save direction) before the SAVE.
	{33, {39,8}, {40,8}},
	{1, {0,16}, {2,16}, {2,15}, {4,15}, {4,18}, {7,18}, {s="refFaceAt", x=7, y=18, dir="Left"}, {s="refChain", name="early", rng=101}},

-- 2: NIDORAN (split inside the chain)

	-- Viridian Forest after the chain (in the Weedle battle, or just before it in free mode): fight, then the hidden
	-- Potion is taken as a logged recovery (kept for Brock; used at once only at <= 12 HP), exit north.
	{51, {2,19}, {c="a",a="Viridian Forest"}, {s="fightWeedle"}, {c="encounters",limit=nil}, {1,19}, {s="refForestPotionIf"}, {1,16}, {c="potion",b=false}, {s="equipForBrock",anti=true}, {1,5}, {s="equipForBrock"}, {1,-1}},
	-- Forest exit
	{47, {4,7}, {s="exitForest"}, {4,1}, {5,1}, {5,0}},
	-- Road to Pewter City
	{13, {3,11}, {c="a",a="Pewter City"}, {3,8}, {8,8}, {8,-1}},
	-- Pewter City
	{2, {18,35}, {18,22}, {19,22}, {19,13}, {10,13}, {10,18}, {16,18}, {16,17}},
	-- Brock
	{54, {4,13}, {c="a",a="Brock's Gym"}, {4,8}, {1,8}, {1,4}, {4,4}, {4,2}, {s="talk",dir="Up"}, {s="fightBrock"}, {s="splitBrock"}, {s="changeSpeed", speed=AFTER_BROCK_SPEED, extra="We have a run going"}, {4,14}},

-- 3: BROCK

	-- To Pewter Mart
	{2, {16,18}, {c="potion",b=true}, {10,18}, {10,13}, {21,13}, {21,18}, {23,18}, {23,17}},
	-- Pewter Mart. v6: OPTIONS (battle style SET) two tiles in, as the reference (11:51; [C] "two tiles in the mart
	-- because of audio transition; it's the fastest spot") and the WR guide ("one or two steps in"); the inherited
	-- engine set it on Route 3.
	{56, {3,7}, {3,6}, {3,5}, {s="battleModeSet"}, {2,5}, {s="refShopPewter"}, {2,6}, {3,6}, {3,8}},
	-- Leaving Pewter City
	{2, {23,18}, {40,18}},
	-- Route 3
	{14, {0,10}, {c="a",a="Route 3"}, {c="refCatchFlierIfMissing"}, {c="pp",on=true}, {c="trackEncounters",area="route3"}, {8,10}, {8,8}, {11,8}, {11,6}, {s="bugCatcher"}, {11,4}, {12,4}, {c="a",a="Shorts Kid"}, {s="potionBeforeShorts"}, {13,4}, {s="talk",dir="Right"}, {s="shortsKid"}, {s="tweetBrock"}, {13,5}, {c="a",a="Route 3"}, {s="potionBeforeCocoons"}, {18,5}, {s="talk",dir="Right"}, {s="swapMove",move="horn_attack",to=0}, {18,6}, {22,6}, {22,5}, {23,5}, {s="potion",hp=4}, {24,5}, {s="talk",dir="Down"}, {s="fightMetapod"}, {27,5}, {27,9}, {s="potion",hp=20,yolo=14}, {s="refFlierBackupWest"}, {s="refRoute3SaveTile"}, {s="refChain", name="moon", rng=103}},
	-- v8: Route 3 SAVE at (27,11) facing Down + power cycle + the Mt. Moon CHAIN (lua/chain.lua REFSTRAT_CHAIN_MOON: the
	-- reference/G-MM path over Route 3/4 and through 1F, B1F, B2F with TM12, Rare Candy, Escape Rope, TM01 and Moon Stone,
	-- no 1F Super Nerd; split 4 at the Mt. Moon door) ending on B2F (10,17) with the Paras (free mode: same path, engine
	-- encounter handling). Replaces the v7 entries Route 4 and Mt. Moon 1F/B1F/B2F up to (10,17).
-- 4: ROUTE 3 (split inside the moon chain)

	-- B2F after the chain (reference 20:01-23:23): Potions to full after the Paras (20:02-20:11), the Rocket by sight on the
	-- step Right to (11,17), then Up to (12,16) and the menu (21:12.77-22:11.03): Rare Candy (L15 -> 16, evolves), TM12
	-- Water Gun over Tackle, Moon Stone, TM01 Mega Punch over Leer; Super Nerd; Helix Fossil. Each menu step is a no-op
	-- unless its state holds (candy only at exactly L15); the repeat after the Super Nerd is the logged recovery for a
	-- Nidoran that reached the menu at another level (refMoonMenuCheck). v8 RECOVERY: in-battle emergency Potions stay
	-- enabled for the Rocket (reference: none; v8 v1: 4 of 5 L14 Nidorans died there); refMoonMenuCheck logs any use.
	{61, {10,17}, {c="a",a="Mt. Moon"}, {c="trackEncounters",area="moon"}, {c="refCatch", catch={{name="paras"}}}, {c="allowDeath",on=false}, {s="potion",hp=99}, {s="refMoonPotionMark"}, {12,17}, {12,16}, {s="refMoonMenuCheck"}, {s="refCandyEvolve"}, {s="refTeach",move="water_gun",replace="tackle"}, {s="refMoonStone"}, {s="refTeach",move="mega_punch",poke="nidoking",replace="leer"}, {12,9}, {s="talk",dir="Up"}, {s="fightGrimer"}, {s="refCandyEvolve"}, {s="refTeach",move="water_gun",replace="tackle"}, {s="refMoonStone"}, {s="refTeach",move="mega_punch",poke="nidoking",replace="leer"}, {13,9}, {13,7}, {s="dialogue",dir="Up"}, {13,5}, {12,5}, {12,4}, {3,4}, {3,7}, {5,7}},
	-- Mt. Moon escape
	{60, {23,3}, {27,3}},

-- 5: MT. MOON

	-- To Cerulean
	{15, {24,6}, {s="reportMtMoon"}, {s="split"}, {s="changeSpeed", speed=AFTER_MOON_SPEED, extra="Things are getting serious"}, {c="trackEncounters",area=nil}, {24,8}, {35,8}, {35,10}, {61,10}, {61,8}, {79,8}, {79,10}, {90,10}},
	-- Enter Cerulean
	{3, {0,18}, {c="a",a="Cerulean"}, {14,18}, {s="dodgeCerulean"}, {19,18}, {19,17}},
	-- Cerulean Center
	{64, {3,7}, {3,3}, {s="dialogue",dir="Up"}, {3,8}},
	-- v11: Bike Shop clerk for instant text (reference 24:09-24:22, after the Center)
	{3, {19,18}, {16,18}, {16,26}, {13,26}, {13,25}},
	{66, {3,7}, {3,4}, {4,4}, {s="refBikeClerk"}, {4,4}, {3,4}, {3,7}, {3,8}},
	-- To the house
	{3, {13,26}, {16,26}, {16,18}, {s="dodgeCerulean",left=true}, {8,16}, {8,12}, {9,12}, {9,11}},
	-- In the house
	{230, {2,7}, {2,0}},
	-- Outback
	{3, {9,9}, {9,8}, {14,8}, {s="take",dir="Right"}, {9,8}, {9,10}},
	-- Out the house
	{230, {2,1}, {2,8}},
	-- Rival 2
	{3, {9,12}, {c="a",a="Cerulean Rival"}, {21,12}, {21,6}, {s="rivalSandAttack"}, {s="refPreNuggetCenter"}, {21,-1}},
	-- Nugget bridge
	{35, {11,35}, {s="refInstantTextLog",at="Nugget Bridge"}, {c="a",a="Nugget Bridge"}, {11,32}, {s="talk",dir="Up"}, {s="hornAttackCaterpie"}, {10,32}, {10,29}, {s="potion",hp=12,yolo=10}, {s="talk",dir="Up"}, {11,29}, {11,27}, {s="rareCandyEarly",chain=true}, {s="potion",hp=10,yolo=8}, {11,26}, {s="talk",dir="Up"}, {s="swapThrash"}, {10,26}, {10,24}, {s="teachThrash",chain=true}, {s="potion",hp=4}, {10,23}, {s="talk",dir="Up"}, {s="swapThrash"}, {11,23}, {11,21}, {s="teachThrash",chain=true}, {s="potionForMankey"}, {11,20}, {s="talk",dir="Up"}, {s="swapThrash"}, {s="redbarMankey"}, {10,20}, {10,19}, {s="teachThrash"}, {10,15}, {s="learnThrash"}, {s="swapThrash"}, {s="waitToFight"}, {s="teachThrash"}, {s="split"}, {10,8}, {20,8}},

-- 6: NUGGET BRIDGE

	-- To Bill's
	-- v4: reference Route 25 trainers (30:05-32:28): Hiker Onix L17 (13,7) by sight at (14,7), Lass Nidoran M/F (18,8)
	-- by talk, Hiker Geodude x3 + Machop L13 (23,9) by sight at (23,8), Lass Oddish/Pidgey/Oddish (37,4) by talk.
	-- Avoids Hiker Machop/Geodude L15 (8,4) and Jr. Trainer M (24,4), and the Elixer/Ether pickups the reference
	-- skipped. EXP +1351 instead of +915 -> L23 at Bill's (ledger: experiments/refstrat-v4-2026-10-11/FINDINGS.md).
	{36, {0,8}, {9,8}, {9,7}, {11,7}, {11,9}, {14,9}, {14,7}, {14,6}, {15,6}, {15,4}, {17,4}, {17,7}, {18,7}, {s="talk",dir="Down"}, {19,7}, {19,8}, {23,8}, {25,8}, {25,6}, {32,6}, {32,4}, {36,4}, {s="talk",dir="Right"}, {36,5}, {38,5}, {38,4}, {45,4}, {45,3}},
	-- Save Bill
	{88, {2,7}, {2,5}, {5,5}, {s="dialogue",dir="Right"}, {1,5}, {s="interact",dir="Up"}, {4,5}, {s="talkToBill"}, {s="waitToTalk"}, {s="refUseIf",item="rare_candy",poke="nidoking",all=true}, {s="refNidokingStats"}, {s="refBillPotions",chain=true}, {s="item",item="escape_rope"}},
	-- Reference order (33:23-36:23): Escape Rope -> burgled house -> Rocket (TM28) -> back through the house -> gym
	-- (Jr. Trainer F, Misty) -> burgled house again -> east side -> Route 5. v11: Bike Shop talks added (instant text).
	-- v11: second Bike Shop clerk talk (reference 33:30-33:42, after Bill: instant text again after Bill's menu)
	{3, {19,18}, {16,18}, {16,26}, {13,26}, {13,25}},
	{66, {3,7}, {3,4}, {4,4}, {s="refBikeClerk"}, {4,4}, {3,4}, {3,7}, {3,8}},
	{3, {13,26}, {c="a",a="Cerulean Rocket"}, {16,26}, {16,18}, {17,18}, {17,16}, {8,16}, {8,12}, {27,12}, {27,11}},
	{62, {2,7}, {2,2}, {3,2}, {3,0}},
	{3, {27,9}, {28,9}, {s="potionBeforeRocket"}, {30,9}, {s="announceMachop"}, {29,9}, {27,9}, {s="refWarpDir",dir="Down"}},
	{62, {3,0}, {3,2}, {2,2}, {2,7}},
	{3, {27,11}, {27,13}, {11,13}, {11,14}, {8,14}, {8,19}, {16,19}, {16,18}, {19,18}, {s="refMaybeHeal",map=3,door={19,17},center=64,frac=1.0,mistyFloor=true}, {19,20}, {30,20}, {30,19}},
	-- Misty
	{65, {4,13}, {s="refInstantTextLog",at="Misty gym"}, {c="a",a="Misty's Gym"}, {c="potion",b=false}, {4,8}, {2,8}, {2,5}, {7,5}, {7,3}, {6,3}, {5,3}, {s="waitToFight"}, {s="refUseIf",item="rare_candy",poke="nidoking",all=true}, {s="refNidokingStats"}, {s="refMistyPrep"}, {5,2}, {s="talk",dir="Left"}, {s="fightMisty"}, {s="split"}, {s="tweetMisty"}, {5,3}, {7,3}, {7,5}, {5,5}, {5,14}},

-- 7: MISTY

	-- v19 edit C: after Misty, Cerulean Center recovery (row 17; same trigger as the Route 5 Potion step) and the
	-- conditional Mart (RB2, Potion floor 1 / Balls for the Oddish fallback), both at the Center door the route passes
	{3, {30,20}, {22,20}, {22,18}, {19,18}, {s="refMaybeHeal",map=3,door={19,17},center=64,postMisty=true}, {s="refMaybeMart",min=0}, {17,18}, {17,16}, {8,16}, {8,12}, {27,12}, {27,11}},
	{62, {2,7}, {2,2}, {3,2}, {3,0}},
	{3, {27,9}, {33,9}, {33,18}, {36,18}, {36,31}, {25,31}, {25,36}},
	-- Out of Cerulean
	{16, {15,0}, {c="potion",b=true,yolo=true}, {s="potion",hp=50,yolo=40}, {15,28}, {17,28}, {17,27}},
	-- Underground entrance
	{71, {3,7}, {3,4}, {4,4}},
	-- Underground to Vermilion
	{119, {5,4}, {4,4}, {s="jingleSkip"}, {2,4}, {2,41}},
	-- Underground exit
	{74, {4,4}, {3,8}},
	-- Oddish
	{17, {17,14}, {c="a",a="Vermilion City"}, {c="catchOddish"}, {17,15}, {s="potion",hp=10,yolo=7}, {17,19}, {s="catchOddish"}, {11,29}, {s="potion",hp=10,yolo=7}, {11,29}, {s="waitToFight",dir="Down"}, {10,29}, {10,30}, {s="potionBeforeRaticate"}, {10,31}, {9,31}, {9,36}},
	-- Enter Vermilion
	{5, {19,0}, {c="disableCatch"}, {19,6}, {21,6}, {21,14}, {23,14}, {23,13}},
	-- Vermilion mart
	{91, {3,7}, {3,5}, {2,5}, {s="refShopVermilion"}, {3,5}, {3,8}},
	-- To S.S. Anne
	{5, {23,14}, {30,14}, {30,26}, {18,26}, {18,31}},
	-- Mew
	{94, {14,0}, {c="a",a="S.S. Anne"}, {14,3}},
	-- First deck
	{95, {27,0}, {27,1}, {26,1}, {26,7}, {2,7}, {2,6}},
	-- Rival 3
	{96, {2,4}, {2,11}, {3,11}, {3,12}, {37,12}, {37,9}, {s="swap",item=2,dest="potion",chain=true}, {s="potion",hp=25,yolo=19,chain=true}, {s="teach",move="bubblebeam",replace="tackle"}, {37,8}, {s="rivalSandAttack"}, {36,8}, {36,4}},
	-- Old man Cut
	{101, {0,7}, {0,4}, {4,4}, {4,3}, {s="talk",dir="Up"}, {4,5}, {0,5}, {0,7}},
	-- Second deck out
	{96, {36,4}, {s="guess",game="trash",enabled=true}, {36,12}, {3,12}, {3,11}, {2,11}, {2,4}},
	-- First deck out
	{95, {2,6}, {2,7}, {26,7}, {26,-1}},
	-- Departure
	{94, {14,2}, {s="epicCutscene"}},
	-- To Surge
	{5, {18,29}, {18,26}, {30,26}, {30,14}, {23,14}, {s="refVermilionRB3"}, {15,14}, {15,17}, {s="potionBeforeSurge"}, {s="swap",item="repel",dest=0,chain=true}, {s="teach",move="cut",poke={"oddish","paras"},chain=true}, {s="teach",move="dig",poke={"paras","squirtle"},chain=true}, {s="skill",move="cut",done=0x0D4D}, {15,20}, {12,20}, {s="refChain", name="surge", rng=105}},
	-- Trashcans. v9: the SAVE at (12,20) + power cycle + the 'surge' chain (lua/chain.lua: cans 8 then 5 as the
	-- reference 41:41-42:11) end on (3,12) in the gym; refSurgeVerify checks the visible lock outcome (fallbacks logged).
	{92, {3,12}, {c="a",a="Surge's Gym"}, {s="refSurgeVerify"}, {4,6}, {4,3}, {5,3}, {5,2}, {s="talk",dir="Up"}, {s="fightSurge"}, {s="split"}, {s="tweetSurge"}, {4,2}, {4,13}, {5,13}, {5,18}},

-- 8: SURGE

	-- To bicycle house
	{5, {12,20}, {c="a",a="Bicycle Shop"}, {15,20}, {15,19}, {s="skill",move="cut",done=0x0D4D}, {15,14}, {9,14}, {9,13}},
	-- Bicycle cert
	{90, {2,7}, {2,5}, {0,5}, {0,1}, {2,1}, {s="dialogue",dir="Right"}, {s="skill",move="dig",map=90}},
	-- Cerulean warp
	{3, {19,18}, {19,23}, {16,23}, {16,26}, {13,26}, {13,25}},
	-- Bicycle shop
	{66, {2,7}, {2,3}, {4,3}, {4,2}, {s="procureBicycle"}, {4,7}, {3,7}, {3,8}},
	-- Bicycle out of Cerulean
	{3, {13,26}, {s="swap",item="bicycle",dest=1,chain=true}, {s="teach",move="thunderbolt",replace="horn_attack",chain=true}, {s="bicycle"}, {19,26}, {19,27}, {s="skill",move="cut",done=0x0D4D}, {19,29}, {36,29}, {36,16}, {40,16}},
	-- TPP's Bane
	{20, {0,8}, {c="a",a="Route 9"}, {4,8}, {s="skill",move="cut",done=0x0C17,val=2}, {13,8}, {13,9}, {s="talk",dir="Down"}, {s="fourTurnThrash"}, {12,9}, {12,12}, {23,12}, {23,11}, {29,11}, {29,12}, {41,12}, {41,10}, {40,10}, {40,9}, {s="talk",dir="Up"}, {s="announceVenonat"}, {41,9}, {41,6}, {39,6}, {39,4}, {45,4}, {45,3}, {51,3}, {51,8}, {60,8}},
	-- To the cave
	{21, {0,8}, {3,8}, {3,10}, {13,10}, {13,15}, {14,15}, {14,26}, {3,26}, {3,18}, {7,18}, {s="item",item="repel"}, {8,18}, {8,17}},
	-- Rock Tunnel
	{82, {15,3}, {c="a",a="Rock Tunnel"}, {c="potion",b=false}, {15,6}, {23,6}, {23,7}, {s="talk",dir="Down"}, {s="redbarCubone"}, {22,7}, {22,10}, {37,10}, {37,3}},
	-- B1
	{232, {33,25}, {33,30}, {27,30}, {s="talk",dir="Left"}, {27,31}, {14,31}, {14,29}, {s="potion",hp=6,yolo=0}, {s="talk",dir="Up"}, {s="announceOddish"}, {17,29}, {17,24}, {25,24}, {25,16}, {37,16}, {37,11}, {s="item",item="repel",chain=true}, {s="healParalysis"}, {37,3}, {27,3}},
	-- B2
	{82, {5,3}, {5,9}, {11,9}, {11,14}, {17,14}, {17,11}},
	-- B1
	{232, {23,11}, {14,11}, {14,17}, {8,17}, {8,10}, {7,10}, {s="talk",dir="Left"}, {7,11}, {5,11}, {s="item",item="repel"}, {5,3}, {3,3}},
	-- Out of the Tunnel
	{82, {37,17}, {32,17}, {32,23}, {37,23}, {37,28}, {28,28}, {26,24}, {23,24}, {s="talk",dir="Left"}, {23,27}, {15,27}, {15,33}},
	-- To Lavender Town
	{21, {8,54}, {c="a",a="Lavender Town"}, {15,54}, {15,53}, {s="refHidden",item="max_ether",x=15,y=53,dir="Right"}, {15,65}, {11,65}, {11,69}, {6,69}, {6,72}},
	-- Through Lavender
	{4, {6,0}, {6,6}, {0,6}, {0,8}, {-1,8}},
	-- Leave Lavender
	{19, {59,8}, {52,8}, {52,13}, {47,13}, {s="talk",dir="Left"}, {47,14}, {42,14}, {42,7}, {40,7}, {40,6}, {29,6}, {29,7}, {23,7}, {23,12}, {14,12}, {14,4}, {13,4}, {13,3}},
	-- Underground entrance
	{80, {3,7}, {3,6}, {4,6}, {4,4}},
	-- Underground
	{121, {47,2}, {s="bicycle"}, {47,5}, {22,5}, {s="undergroundElixer"}, {2,5}},
	-- Underground exit
	{77, {4,4}, {4,8}},
	-- To Celadon
	{18, {5,14}, {s="bicycle"}, {8,14}, {8,8}, {4,8}, {4,3}, {-1,3}},
	-- Celadon
	{6, {49,11}, {c="a",a="Celadon Mart"}, {14,11}, {14,14}, {10,14}, {10,13}},
	-- F1: Department store
	{122, {16,7}, {c="potion",b=true,yolo=true}, {c="pp",on=true}, {16,3}, {12,3}, {12,1}},
	-- F2
	{123, {12,2}, {8,2}, {8,5}, {6,5}, {s="shopTM07"}, {5,5}, {s="refShopRepels"}, {9,5}, {s="dodgeDepartment"}, {15,2}, {16,2}, {16,1}},
	-- F3
	{124, {16,2}, {12,2}, {12,1}},
	-- F4: Poke Doll
	{125, {12,2}, {10,2}, {10,5}, {5,5}, {s="shopPokeDoll"}, {11,5}, {11,2}, {16,2}, {16,1}},
	-- F5
	{136, {16,2}, {12,2}, {12,1}},
	-- Roof
	{126, {15,3}, {12,3}, {s="refVendSoda"}, {6,3}, {6,4}, {s="giveWater"}, {6,4}, {7,3}, {12,3}, {s="shopExtraWater"}, {15,3}, {15,2}},
	-- F5: Buffs
	{136, {12,2}, {8,2}, {8,5}, {5,5}, {s="refShopBuffs"}, {1,5}, {1,1}},
	-- Elevator
	{127, {1,3}, {1,2}, {3,2}, {3,1}, {s="deptElevator"}, {2,1}, {2,4}},
	-- F1: Exit department store
	{122, {1,2}, {1,6}, {2,6}, {2,8}},
	-- Leave Celadon
	{6, {8,14}, {s="bicycle"}, {8,15}, {2,15}, {2,18}, {-1,18}},
	-- Cut out of Celadon
	{27, {39,10}, {34,10}, {s="skill",move="cut",dir="Up",done=0x0D4D}, {34,6}, {27,6}, {27,4}, {23,4}},
	-- Old man's hall
	{186, {7,2}, {-1,2}},
	-- To the Fly house
	{27, {17,4}, {c="a",a="HM02 Fly"}, {s="refFreeSlot"}, {10,4}, {10,6}, {7,6}, {7,5}},
	-- Fly house
	{188, {2,7}, {2,4}, {s="talk",dir="Up"}, {2,5}, {s="split"}, {2,8}},

-- 9: FLY

	-- Fly to Lavender
	{27, {7,6}, {s="swap",item="super_repel",dest=1,chain=true}, {s="potion",hp=10,chain=true}, {s="teach",move="horn_drill",replace="bubblebeam",chain=true}, {s="item",item="super_repel",chain=true}, {s="swap",item="x_accuracy",dest=2,chain=true}, {s="teach",move="fly",poke={"spearow","pidgey","pidgeotto"},chain=true}, {s="teach",move="rock_slide",replace="poison_sting",chain=true}, {s="fly",dest="lavender",map=4}},
	-- To the tower
	{4, {3,6}, {c="a",a="Pokemon Tower"}, {14,6}, {14,5}},
	-- Pokemon Tower
	{142, {10,17}, {10,10}, {18,10}, {18,9}},
	-- F2: Rival
	{143, {18,9}, {c="thrash",disable=true}, {18,7}, {16,7}, {16,5}, {15,5}, {s="lavenderRival"}, {5,5}, {5,8}, {3,8}, {3,9}},
	-- F3
	{144, {3,9}, {3,10}, {6,10}, {6,13}, {8,13}, {8,6}, {17,6}, {17,9}, {18,9}},
	-- F4
	{145, {18,9}, {c="allowDeath",on=true}, {c="potion",b=false}, {18,7}, {16,7}, {s="talk",dir="Left"}, {s="digFight"}, {16,9}, {c="potion",b=true,yolo=true}, {14,9}, {14,10}, {13,10}, {s="take",dir="Left"}, {14,10}, {14,8}, {11,8}, {11,9}, {10,9}, {10,12}, {7,12}, {7,11}, {4,11}, {4,10}, {3,10}, {3,9}},
	-- F5
	{146, {3,9}, {4,9}, {4,11}, {s="take",dir="Down"}, {4,6}, {13,6}, {13,9}, {9,9}, {9,12}, {14,12}, {14,10}, {18,10}, {c="allowDeath",on=false}, {18,9}},
	-- F6
 	{147, {18,9}, {18,7}, {15,7}, {15,3}, {11,3}, {11,5}, {10,5}, {s="interact",dir="Left"}, {10,6}, {6,6}, {6,7}, {s="interact",dir="Down"}, {6,14}, {10,14}, {10,16}, {s="pokeDoll"}, {9,16}},
	-- F7: Top
	{148, {9,16}, {10,16}, {10,9}, {s="fightX",x="accuracy"}, {c="thrash",disable=false}, {10,7}, {s="thunderboltFirst"}, {10,4}, {s="interact",dir="Up"}},
	-- Old man's house
	{149, {3,7}, {3,6}, {2,6}, {2,1}, {s="talk",dir="Right"}, {2,8}},

-- 10: POKéFLUTE

	-- Lavender -> Celadon
	{4, {7,10}, {s="split"}, {s="fly",dest="celadon",map=6}},
	-- To Celadon Center
	{6, {41,10}, {41,9}},
	-- Celadon Center
	{133, {3,7}, {3,3}, {s="dialogue",dir="Up"}, {3,8}},
	-- Reference order (1:00:56-1:07:36): Celadon heal -> drink for the guard -> Silph Co. first -> Dig to Celadon,
	-- then Snorlax / Cycling Road / Safari (below). Surf is taught after the Safari (HM03), not on Silph 10F.
	-- Celadon again
	{6, {41,10}, {s="bicycle"}, {41,11}, {50,11}},
	-- To Saffron
	{18, {0,3}, {c="a",a="Saffron City"}, {4,3}, {4,9}, {10,9}, {10,10}, {12,10}},
	-- Thirsty guard
	{76, {0,4}, {6,4}},
	-- Saffron entry
	{18, {18,10}, {s="bicycle"}, {20,10}},
	-- Saffron City
	{10, {0,18}, {3,18}, {3,22}, {18,22}, {18,21}},
	-- Silph Co. v7: the REFERENCE path (sources/SILPH.md rows 1-37, timer 1:01:53-1:07:49.5, frame-matched positions):
	-- stairs 1F->5F; 5F hidden Elixer (12,3) facing Left; walk y=4/x=8 and TALK to the Arbok Rocket (X Acc + HD); two 9F
	-- pad bounces around the beaten Rocket (Card Key between them); 5F/3F card-key doors; 7F rival; 11F: Elixer on the
	-- arrival pad, 11F Rocket (X Acc), Giovanni (X Acc); then back by pads 11F->7F->3F, 3F elevator to 9F (the
	-- reference's choice; the WR guide says 10F) and 9F stairs to 10F for TM26 + Rare Candy (Carbos skipped), Dig.
	-- Replaces the inherited elevator-first path (10F Machoke Rocket, Carbos, Earthquake taught on 10F, 9F corridor,
	-- Rare Candy / Potion before Giovanni, Dig from 11F). Earthquake is now taught at the Safari gate (map 190).
	{181, {10,17}, {c="a",a="Silph Co."}, {10,13}, {26,13}, {26,0}},
	{207, {24,1}, {26,1}, {26,0}},
	{208, {26,1}, {24,1}, {24,0}},
	{209, {24,1}, {26,1}, {26,0}},
	{210, {26,1}, {26,3}, {13,3}, {s="refFreeSlot"}, {s="refHidden",item="elixer",x=13,y=3,dir="Left"}, {13,4}, {8,4}, {8,15}, {s="talk",dir="Down"}, {s="refFightX",x="accuracy",move="horn_drill",reserve=9,label="Silph 5F Arbok Rocket"}, {9,15}},
	-- bounce 1 (the beaten Rocket at (8,16) blocks the corridor; arriving on the pad is the only way to (9,16))
	{233, {17,15}, {17,14}, {17,15}},
	{210, {9,15}, {9,16}, {20,16}, {s="take",dir="Right"}, {9,16}, {9,15}},
	-- bounce 2
	{233, {17,15}, {17,14}, {17,15}},
	{210, {9,15}, {9,13}, {8,13}, {s="interact",dir="Left"}, {6,13}, {6,16}, {3,16}, {3,15}},
	{208, {3,15}, {4,15}, {18,15}, {18,9}, {s="interact",dir="Left"}, {16,9}, {16,11}, {11,11}},
	-- Rival 5
	{212, {5,3}, {c="a",a="Silph Rival"}, {5,2}, {4,2}, {3,2}, {c="potion",b=false}, {s="silphRival"}, {3,7}, {c="potion",b=true,yolo=true}, {5,7}},
	-- Giovanni (11F): Elixer on the arrival pad (reference 1:05:04; G hp-strats "1-77 HP: PP item before Rocket")
	{235, {3,2}, {c="a",a="Silph Giovanni"}, {s="refRestorePP",moves={{"horn_drill","max"}},prefer={"elixer","max_ether","ether"}}, {2,2}, {2,16}, {s="talk",dir="Right"}, {s="refFightX",x="accuracy",move="horn_drill",reserve=7,label="Silph 11F Rocket",byOpponent={cubone="bubblebeam"}}, {2,15}, {6,15}, {s="refRecoveryPotion",hp=17,why="Giovanni below 17 HP (reference 25/123, no heal)"}, {6,14}, {s="interact",dir="Up"}, {6,13}, {s="fightX",x="accuracy"}, {s="fightSilphGiovanni"}, {s="split"}, {6,14}, {3,14}, {3,2}},
	-- after Giovanni every Silph trainer is gone; the boardroom has no walking exit: pads 11F->7F->3F, 3F elevator
	{212, {5,7}, {4,7}, {3,7}, {3,3}, {4,3}, {5,3}},
	{208, {11,11}, {12,11}, {16,11}, {16,9}, {18,9}, {18,7}, {20,7}, {20,0}},
	{236, {1,3}, {1,2}, {3,2}, {3,1}, {s="refSilphElevator",index=8}, {2,1}, {2,4}},
	{233, {18,1}, {14,1}, {14,0}},
	{234, {8,1}, {3,1}, {3,9}, {1,9}, {1,12}, {s="take",dir="Right"}, {1,13}, {1,15}, {3,15}, {3,14}, {s="take",dir="Right"}, {s="skill",move="dig",map=234}},

	-- Leave Celadon
	{6, {41,10}, {c="a",a="Snorlax"}, {s="item",item="super_repel",chain=true}, {s="bicycle"}, {41,11}, {14,11}, {14,14}, {2,14}, {2,18}, {-1,18}},
	-- トトロだ！
	{27, {39,10}, {27,10}, {s="swapXSpeeds"}, {s="playPokeFlute"}, {23,10}},
	-- Snorlax pass
	{186, {7,8}, {-1,8}},
	-- Bicycle road
	{27, {17,10}, {c="a",a="Bicycle Road"}, {s="refFreeSlot"}, {12,10}, {12,13}, {11,13}, {11,18}},
	-- Forced down inputs
	{28, {11,0}, {11,5}, {15,5}, {15,12}, {s="drivebyRareCandy"}, {15,14}, {18,14}, {18,64}, {s="refHidden",item="pp_up",x=17,y=71,dir="Down",slope=true}, {18,122}, {13,122}, {13,143}},
	-- Cycling road exit
	{29, {13,0}, {13,8}, {34,8}},
	-- Exit building
	-- v7: TM26 Earthquake over Rock Slide here, after the PP Up (reference 1:10:00, G-WR "Post Cycling Road Menu ...
	-- Use PPUP on Horn Drill, teach TM26 over slot 2"); it used to be taught on Silph 10F.
	{190, {0,4}, {s="refPPUp",move="horn_drill"}, {s="refTeach",move="earthquake",replace="rock_slide",poke="nidoking"}, {8,4}},
	-- Enter Safari City
	{29, {40,8}, {s="item",item="super_repel",chain=true}, {s="teach",move="ice_beam",replace="rock_slide",chain=true}, {s="bicycle"}, {50,8}},
	-- Safari City
	-- v19 edit A: the v18 Fuchsia Mart Super Potion top-up is removed (the reference buys nothing after Celadon); the
	-- v14-v17 path to the Safari gate is restored unchanged.
	{7, {0,16}, {c="a",a="Safari Zone"}, {3,16}, {3,20}, {23,20}, {23,14}, {29,14}, {29,15}, {35,15}, {35,8}, {37,8}, {37,2}, {22,2}, {22,4}, {18,4}, {18,3}},
	-- Safari entrance
	{156, {3,5}, {3,2}, {4,2}, {s="dialogue",dir="Right"}},
	-- Safari 1
	{220, {15,25}, {s="bicycle"}, {15,16}, {28,16}, {28,11}, {30,11}},
	-- Safari 2. v7: the inherited conditional detours safariCarbos (speed-DV rule) and extraFullRestore (no Full Restore
	-- in the bag) are removed: the reference takes neither (Safari only for Surf + Gold Teeth; WR guide: no Carbos). In
	-- 21 v6 games that reached these maps neither detour ever fired.
	-- v7 note: {s="item",item="carbos"} below is kept on purpose: no Carbos is ever picked up any more, the step only
	-- closes the item menu left open by the chained Super Repel / toss steps (removing it untested risks a stall).
	{217, {0,23}, {4,23}, {4,24}, {20,24}, {20,20}, {12,20}, {12,22}, {11,22}, {10,22}, {s="item",item="super_repel",chain=true}, {s="tossInSafari"}, {s="item",item="carbos",poke="nidoking"}, {9,22}, {9,8}, {12,8}, {12,6}, {17,6}, {17,8}, {20,8}, {20,3}, {7,3}, {7,5}, {-1,5}},
	-- Safari 3
	{218, {39,31}, {22,31}, {22,22}, {16,22}, {16,28}, {13,28}, {13,9}, {28,9}, {28,3}, {3,3}, {3,36}},
	-- Safari 4
	{219, {21,0}, {21,5}, {19,5}, {19,6}, {s="interact",dir="Down"}, {19,5}, {7,5}, {7,6}, {3,6}, {3,3}},
	-- Warden
	{222, {2,7}, {2,6}, {3,6}, {3,4}, {s="talk",dir="Up"}, {3,8}},
	-- Safari Warp
	{219, {3,4}, {s="teach",move="surf",poke="squirtle",replace="tail_whip"}, {s="skill",move="dig",map=219}},
-- 11: SILPH CO.

	-- Fly to Fuschia
	{6, {41,10}, {s="fly",dest="fuchsia",map=7}},
	-- To Koga
	{7, {19,28}, {c="a",a="Koga's Gym"}, {5,28}, {5,27}},
	-- Koga
	{157, {4,17}, {4,16}, {9,16}, {9,9}, {7,9}, {s="talk",dir="Up"}, {9,9}, {9,1}, {1,1}, {1,2}, {s="elixer",move="earthquake",min=2,chain=true}, {s="potionBeforeHypno"}, {1,3}, {2,3}, {2,5}, {1,5}, {c="potion",b=false}, {1,7}, {s="fightHypno"}, {1,9}, {2,9}, {s="elixer",move="earthquake",min=4}, {4,9}, {s="talk",dir="Down"}, {s="fightKoga"}, {s="split"}, {1,9}, {1,5}, {2,5}, {2,3}, {1,3}, {1,1}, {9,1}, {9,16}, {5,16}, {5,18}},

-- 12: KOGA

	-- To the Warden
	{7, {5,28}, {s="bicycle"}, {6,28}, {6,30}, {24,30}, {30,30}, {30,28}, {27,28}, {27,27}},
	-- HM04 Strength
	{155, {4,7}, {4,6}, {2,6}, {2,4}, {s="talk",dir="Up"}, {4,4}, {4,8}},
	-- Fly home
	{7, {27,28}, {s="fly",dest="pallet",map=0}},
	-- Pallet to Cinnabar
	--TODO combine RC for Carbos
	{0, {5,6}, {s="item",item="super_repel",chain=true}, {s="item",item="rare_candy",poke="nidoking",all=true,chain=true}, {s="bicycle"}, {c="allowDeath",on=false}, {3,6}, {s="dodgeGirl"}, {3,17}, {s="skill",move="surf",dir="Right",x=4}, {4,18}},
	-- To Cinnabar
	{32, {4,0}, {4,14}, {3,14}, {3,90}},
	-- Enter Cinnabar Mansion
	{8, {3,0}, {c="a",a="Cinnabar Mansion"}, {3,4}, {6,4}, {6,3}},
	-- F1
	{165, {5,27}, {5,10}},
	-- F2
	{214, {5,11}, {10,11}, {10,5}, {6,5}, {6,1}},
	-- F3
	{215, {6,2}, {11,2}, {11,6}, {10,6}, {s="dialogue",dir="Up"}, {14,6}, {14,11}, {16,11}, {16,14}},
	-- F1 drop
	-- v7: cinnabarCarbos (conditional Carbos detour, never taken by the reference) replaced by its own skip waypoint
	{165, {16,14}, {16,16}, {13,16}, {13,20}, {21,20}, {21,23}},
	-- B1
	--TODO menu cancel for RC
	-- v7 note: the {s="item",item="carbos"} step below only closes the chained Super Repel menu (no Carbos exists).
	{216, {23,22}, {23,15}, {21,15}, {s="item",item="super_repel",chain=true}, {s="item",item="carbos",poke="nidoking"}, {17,15}, {17,19}, {18,19}, {18,23}, {17,23}, {17,26}, {18,26}, {s="dialogue",dir="Up"}, {19,26}, {s="take",dir="Up"}, {s="refTeach",move="blizzard",replace="bubblebeam"}, {14,26}, {14,22}, {12,22}, {12,15}, {24,15}, {24,18}, {26,18}, {26,6}, {24,6}, {24,4}, {20,4}, {s="dialogue",dir="Up"}, {24,4}, {24,6}, {12,6}, {12,2}, {11,2}, {s="refSkipPickup",why="Mansion B1F item ball (reference candy skip)"}, {12,2}, {12,7}, {4,7}, {4,9}, {2,9}, {s="refSkipPickup",why="Mansion B1F item ball (reference candy skip)"}, {5,9}, {5,10}, {s="refTeach",move="blizzard",replace="bubblebeam"}, {s="refMakeSpace"}, {s="teach",move="strength",poke="squirtle",replace="tackle",chain=true}, {s="item",item="rare_candy",all=true,poke="nidoking"}, {5,12}, {s="take",dir="Down"}, {5,12}, {s="skill",move="dig",map=216}},
	-- Celadon once again
	-- v19 edit E1: Celadon Center recovery after the Mansion (row 23b; trigger HP < 70 = the Cinnabar step's target)
	{6, {41,10}, {s="refMaybeHeal",map=6,door={41,9},center=133,postMansion=true}, {s="bicycle"}, {41,13}, {36,13}, {36,23}, {25,23}, {25,30}, {35,30}, {35,31}, {s="skill",move="cut",dir="Down",done=0x0D4D}, {35,34}, {5,34}, {5,29}, {12,29}, {12,27}},
	-- Erika
	{134, {4,17}, {c="a",a="Erika's Gym"}, {4,16}, {1,16}, {1,9}, {0,9}, {0,4}, {1,4}, {s="skill",move="cut",done=0x0D4D}, {4,4}, {s="talk",dir="Up"}, {s="fightErika"}, {s="split"}, {5,4}, {5,6}, {s="skill",move="cut",dir="Down",done=0x0D4D}, {5,18}},

-- 13: ERIKA

	-- Fly to Cinnabar
	{6, {12,28}, {s="fly",dest="cinnabar",map=8}},
	-- Cinnabar
	{8, {11,12}, {s="refElixerIf",moves={horn_drill=4,earthquake=4},chain=true}, {s="potion",hp=70,chain=true}, {s="bicycle"}, {18,12}, {18,3}},
	-- Cinnabar Gym
	{166, {16,17}, {c="a",a="Blaine's Gym"}, {16,14}, {18,14}, {18,10}, {15,10}, {15,8}, {s="dialogue",dir="Up"}, {16,8}, {16,7}, {18,7}, {18,1}, {12,1}, {12,2}, {10,2}, {s="dialogue",dir="Up",decline=true}, {12,2}, {12,7}, {10,7}, {10,8}, {9,8}, {s="dialogue",dir="Up",decline=true}, {9,11}, {12,11}, {12,13}, {10,13}, {10,14}, {9,14}, {s="dialogue",dir="Up",decline=true}, {9,16}, {1,16}, {1,14}, {s="dialogue",dir="Up"}, {2,14}, {2,13}, {4,13}, {4,9}, {1,9}, {1,8}, {s="dialogue",dir="Up",decline=true}, {2,8}, {2,7}, {4,7}, {4,5}, {3,5}, {3,4}, {c="potion",b=false}, {s="talk",dir="Up"}, {s="refFightX",x="accuracy",move="horn_drill",reserve=5,label="Blaine"}, {s="split"}, {s="skill",move="dig",map=166}},

-- 14: BLAINE

	-- Celadon too many times
	{6, {41,10}, {c="potion",b=true,yolo=true}, {s="bicycle"}, {41,11}, {50,11}},
	-- Exit Celadon
	{18, {0,3}, {4,3}, {4,9}, {10,9}, {10,10}, {12,10}},
	-- Saffron gate
	{76, {0,4}, {c="a",a="Saffron City"}, {6,4}},
	-- Saffron edge
	{18, {18,10}, {s="elixer",move="earthquake",min=4,chain=true}, {s="potion",hp=60,chain=true}, {s="bicycle"}, {20,10}},
	-- Saffron again
	{10, {0,18}, {3,18}, {3,6}, {31,6}, {31,4}, {34,4}, {34,3}},
	-- Sabrina
	{178, {8,17}, {c="a",a="Sabrina's Gym"}, {8,16}, {11,16}, {11,15}, {16,17}, {16,15}, {15,15}, {18,3}, {18,5}, {15,5}, {1,5}, {11,11}, {11,8}, {10,8}, {s="waitToFight",dir="Left"}, {s="split"}, {11,8}, {11,11}, {s="refSabrinaNoElixer"}, {s="skill",move="dig",map=178}},

-- 15: SABRINA

	-- Celadon
	{6, {41,10}, {s="fly",dest="viridian",map=1}},
	-- Viridian again
	{1, {23,26}, {s="potion",hp=80,forced="potion",chain=true}, {s="bicycle"}, {19,26}, {19,4}, {27,4}, {27,3}, {34,3}, {34,8}, {32,8}, {32,7}},
	-- Giovanni Gym
	{45, {16,17}, {c="potion",b=false}, {c="a",a="Giovanni's Gym"}, {16,16}, {14,16}, {14,9}, {13,9}, {13,7}, {15,7}, {15,4}, {12,4}, {12,5}, {10,5}, {c="a",a="Machoke"}, {10,4}, {s="fightGiovanniMachoke"}, {10,5}, {13,5}, {13,4}, {15,4}, {15,7}, {13,7}, {13,11}, {14,11}, {14,16}, {16,16}, {16,18}},
	-- Reset Gym
	-- v18 edit M: reference Elixer at the gym entrance after the Blackbelt, before Giovanni (1:26:07)
	{1, {32,8}, {c="a",a="Giovanni's Gym"}, {s="refViridianElixer"}, {32,7}},
	-- Giovanni
	{45, {16,17}, {c="potion",b=false}, {16,16}, {14,16}, {14,9}, {13,9}, {13,7}, {15,7}, {15,4}, {12,4}, {12,5}, {10,5}, {10,2}, {7,2}, {7,4}, {2,4}, {s="checkGiovanni"}, {2,2}, {s="talk",dir="Up"}, {s="fightGiovanni"}, {s="split"}, {2,4}, {7,4}, {7,2}, {10,2}, {10,5}, {12,5}, {12,4}, {15,4}, {15,7}, {13,7}, {13,11}, {14,11}, {14,16}, {16,16}, {16,18}},

-- 16: GIOVANNI

	-- Leave Viridian
	{1, {32,8}, {s="potion",hp=130,chain=true}, {s="bicycle"}, {32,12}, {17,12}, {17,16}, {16,16}, {16,17}, {-1,17}},
	-- To Pokemon League
	{33, {39,9}, {c="a",a="Viridian Rival"}, {35,9}, {35,12}, {31,12}, {31,5}, {29,5}, {s="viridianRival"}, {16,5}, {16,12}, {5,12}, {5,10}, {11,10}, {11,6}, {8,6}, {8,5}},
	-- Pokemon League 1
	{193, {4,7}, {4,0}},
	-- PL 2 (Route 23). v7: the inherited {s="checkEther"} step is removed: it is an empty placeholder in the upstream
	-- engine ("-- checkEther" comment only, INVALID STRATEGY at runtime). Reference/WR guide: no PP item and no Max
	-- Ether pickup here ("Do not pick Max Ether and do not use any PP item"); the following ether / tossInVictoryRoad /
	-- grabMaxEther steps are inherited RECOVERY branches (act only when the engine predicts an Elite Four Center) and
	-- are logged by S.refRecoveryLog wrappers (lua/strategies.lua).
	{34, {7,139}, {s="ether",max=true,chain=true}, {s="tossInVictoryRoad"}, {s="bicycle"}, {7,132}, {14,132}, {14,124}, {9,124}, {9,116}, {10,116}, {10,104}, {s="skill",move="surf",y=103}, {10,92}, {7,92}, {7,90}, {s="grabMaxEther"}, {7,72}, {8,72}, {8,71}, {s="item",item="super_repel",chain=true}, {s="bicycle"}, {8,66}, {10,66}, {10,57}, {12,57}, {12,48}, {6,48}, {6,32}, {4,32}, {4,31}},
	-- Victory Road
	{108, {8,17}, {c="a",a="Victory Road"}, {s="tweetVictoryRoad"}, {8,16}, {4,16}, {4,14}, {5,14}, {s="skill",move="strength"}, {5,15}, {4,15}, {4,16}, {7,16}, {s="push",dir="Right",x=0x0255,y=0x0254}, {7,17}, {9,17}, {9,15}, {8,15}, {8,14}, {15,14}, {15,15}, {16,15}, {16,14}, {s="push",dir="Up",x=0x0255,y=0x0254}, {14,14}, {14,12}, {16,12}, {16,11}, {17,11}, {17,12}, {14,12}, {14,14}, {8,14}, {8,16}, {5,16}, {5,12}, {11,12}, {11,6}, {7,6}, {7,8}, {3,8}, {3,5}, {2,5}, {2,1}, {1,1}},
	-- F2
	{194, {0,8}, {0,9}, {3,9}, {3,13}, {5,13}, {5,14}, {s="item",item="super_repel",chain=true}, {s="skill",move="strength"}, {4,14}, {4,13}, {3,13}, {3,15}, {4,15}, {4,16}, {3,16}, {s="push",dir="Left",x=0x02B5,y=0x02B4}, {3,11}, {5,11}, {5,8}, {14,8}, {14,14}, {21,14}, {21,16}, {28,16}, {28,11}, {23,11}, {23,7}},
	-- F3
	{198, {23,7}, {23,6}, {22,6}, {22,4}, {s="skill",move="strength"}, {22,2}, {23,2}, {23,1}, {7,1}, {7,0}, {6,0}, {6,1}, {7,1}, {7,2}, {3,2}, {3,1}, {2,1}, {2,4}, {1,4}, {1,5}, {2,5}, {2,4}, {4,4}, {4,2}, {7,2}, {7,1}, {20,1}, {20,6}, {17,6}, {17,4}, {9,4}, {9,10}, {5,10}, {5,8}, {1,8}, {1,15}, {11,15}, {11,16}, {20,16}, {20,15}, {23,15}},
	-- F2
	{194, {22,16}, {s="item",item="super_repel",chain=true}, {s="potionBeforeLorelei",chain=true}, {s="skill",move="strength"}, {s="bicycle"}, {22,17}, {24,17}, {24,16}, {11,16}, {s="push",dir="Left",x=0x02D5,y=0x02D4}, {21,16}, {21,14}, {25,14}},
	-- F3
	{198, {27,15}, {27,8}, {26,8}},
	-- F2 Exit
	{194, {27,7}, {30,7}},
	-- Victory end
	{34, {14,32}, {18,32}, {18,20}, {14,20}, {14,10}, {13,10}, {13,6}, {10,6}, {10,-1}},
	-- Elite Four entrance
	{9, {10,17}, {c="a",a="Elite Four"}, {10,5}},
	-- Last Center
	{174, {7,11}, {15,9}, {15,8}, {s="depositPokemon"}, {7,8}, {7,7}, {s="refCenterSkip"}, {4,7}, {3,7}, {3,2}, {8,2}, {8,0}},

-- 17: LORELEI

	-- Lorelei
	{245, {s="changeSpeed", speed=E4_SPEED, extra="Enjoy the show"}, {4,5}, {s="refBirdToSlot1"}, {c="a",a="Lorelei"}, {c="potion",b=false}, {4,2}, {s="talk",dir="Right"}, {s="lorelei"}, {s="split"}, {4,0}},
	-- Bruno
	{246, {4,5}, {c="a",a="Bruno"}, {s="refRestorePP",moves={{"horn_drill",5}},prefer={"max_ether","ether","elixer"}}, {4,2}, {s="talk",dir="Right"}, {s="bruno"}, {s="split"}, {4,0}},
	-- Agatha
	{247, {4,5}, {c="a",a="Agatha"}, {s="refAgathaSuper"}, {s="refRecoveryPotion",hp=113,why="Agatha inherited survival threshold"}, {4,2}, {s="talk",dir="Right"}, {s="agatha"}, {s="split"}, {4,1}, {4,0}},
	-- Lance
	{113, {6,11}, {c="a",a="Lance"}, {s="refRestorePP",moves={{"blizzard","max"},{"horn_drill","max"}},prefer={"elixer","max_ether","ether"}}, {s="refRestoreBlizzard"}, {s="prepareForLance"}, {s="refCloseMenu"}, {6,2}, {s="lance"}, {s="split"}, {5,2}, {5,1}, {s="prepareForBlue"}, {5,-1}},
	-- Blue
	{120, {4,3}, {c="a",a="Blue"}, {s="blue"}, {3,0}},
	-- Champion
	{118, {4,2}, {c="a",a="Champion"}, {s="champion"}}

}




-- v22 (experiments/route-fix-v22-2026-10-14): route switches, default off = the v21 route
local function v22entry(map, x, y, mark)
	for i, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == map and e[2][1] == x and e[2][2] == y then
			local ok = mark == nil
			for _, t in ipairs(e) do if type(t) == "table" and t.s == mark then ok = true end end
			if ok then return i, e end
		end
	end
	error("v22 route: entry "..map.." ("..x..","..y..") not found")
end
local function v22index(e, pred)
	for k, t in ipairs(e) do if type(t) == "table" and pred(t) then return k end end
	error("v22 route: step not found")
end
if ROUTE_MISTY_DIRECT then
	-- after the Rocket fight (30,9): refMistyDirect decides; "no Center" -> walks to the gym itself and skips the house
	-- entries, "Center" -> returns at once and the v21 steps follow ({29,9}, house, Center door)
	local __, e = v22entry(3, 27, 9, "announceMachop")
	table.insert(e, v22index(e, function(t) return t.s == "announceMachop" end) + 1, {s = "refMistyDirect"})
end
if SHIP_FIRST then
	-- v58 (experiments/target-policy-2026-10-17/make_v58.py): v22 ROUTE_SHIP_FIRST ported. Vermilion: straight to the
	-- ship (the Mart entry and the Mart-exit entry are removed)
	local iv, ev = v22entry(5, 19, 0)
	assert(ev[#ev][1] == 23 and ev[#ev][2] == 13)
	ev[#ev] = nil
	for _, t in ipairs({{30,14}, {30,26}, {18,26}, {18,31}, {s = "refInstantTextLog", at = "Vermilion (ship first)"}}) do ev[#ev + 1] = t end
	local im = v22entry(91, 3, 7, "refShopVermilion")
	assert(im == iv + 1)
	table.remove(REFSTRAT_ROUTE, im)
	local it = v22entry(5, 23, 14)
	assert(it == iv + 1 and REFSTRAT_ROUTE[it][3][1] == 30)
	table.remove(REFSTRAT_ROUTE, it)
	-- rival: no swap / BubbleBeam teach before the fight; the conditional Potion closes its own menu
	local __, er = v22entry(96, 2, 4, "rivalSandAttack")
	table.remove(er, v22index(er, function(t) return t.s == "swap" end))
	table.remove(er, v22index(er, function(t) return t.s == "teach" and t.move == "bubblebeam" end))
	local kp = v22index(er, function(t) return t.s == "potion" end)
	er[kp].chain = nil
	er[kp].refShipIT = true   -- v58 SHIP_IT_GAMBLE_HP marker (S.potion wrapper in the v58 block)
	table.insert(er, kp + 1, {s = "refInstantTextLog", at = "S.S. Anne rival"})
	-- after the ship: reference Mart list, then the swap and BubbleBeam join the Cut/Dig teach chain
	local __, es = v22entry(5, 18, 29, "refVermilionRB3")
	table.insert(es, v22index(es, function(t) return t.s == "refVermilionRB3" end), {s = "refShopVermilionLate"})
	local kr = v22index(es, function(t) return t.s == "swap" and t.item == "repel" end)
	table.insert(es, kr, {s = "swap", item = 2, dest = "potion", chain = true})
	table.insert(es, kr + 2, {s = "teach", move = "bubblebeam", replace = "tackle", chain = true})
end



if EARLY_NO_NORTH then
	local ev
	for i, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 1 and e[2][1] == 29 and e[2][2] == 20 and type(e[3]) == "table" and e[3].c == "trackEncounters" then ev = e end
	end
	assert(ev, "v23: Viridian save entry not found")
	local a, b
	for j, t in ipairs(ev) do
		if type(t) == "table" and t[1] == 18 and t[2] == 20 then a = a or j end
		if type(t) == "table" and t[1] == 15 and t[2] == 20 then b = j end
	end
	assert(a and b and b > a, "v23: north detour steps not found")
	for _ = a, b - 1 do table.remove(ev, a) end   -- (18,20) (18,16) (18,6) dodge (17,4) (18,4) (18,16) removed; (15,20) kept
end


-- v24 (experiments/hp-policy-v24-2026-10-14): HPM_T also sets the Route 5 Potion step's target (default off = v23)
if HPM_T then
	local found
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 16 and e[2][1] == 15 and e[2][2] == 0 then
			for _, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and t.hp == 50 then t.hp = HPM_T; t.yolo = math.min(t.yolo or 40, HPM_T); found = true end
			end
		end
	end
	assert(found, "v24: Route 5 Potion step not found")
end
if SHIP_POTION_HP then
	local found
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 96 and e[2][1] == 2 and e[2][2] == 4 then
			for _, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and t.hp == 25 then t.hp = SHIP_POTION_HP; t.yolo = SHIP_POTION_HP; found = true end
			end
		end
	end
	assert(found, "v24: S.S. Anne rival Potion step not found")
end


-- v26 (experiments/late-v26-2026-10-14): LATE_RED, default off = v25
if LATE_RED then
	local function entry(map, x, y)
		for _, e in ipairs(REFSTRAT_ROUTE) do if e[1] == map and e[2][1] == x and e[2][2] == y then return e end end
		error("v26: entry " .. map .. " (" .. x .. "," .. y .. ") not found")
	end
	-- Mansion B1F: Full Restore pickup after the first (12,22)
	local b1 = entry(216, 23, 22)   -- unique (checked: one B1F entry with this origin)
	local k
	for j, t in ipairs(b1) do if type(t) == "table" and t[1] == 12 and t[2] == 22 then k = j break end end
	assert(k, "v26: (12,22) not found on B1F")
	if not MANSION_FR_SKIP then   -- v59: the record skips this Full Restore (7.87 s detour)
		table.insert(b1, k + 1, {2, 22}); table.insert(b1, k + 2, {s = "take", dir = "Left"}); table.insert(b1, k + 3, {12, 22})
	end
	-- Cinnabar 70-HP and Saffron 60-HP Potion steps off (red HP through Blaine / Sabrina)
	-- (several entries can share a map and origin: search all of them for the step)
	for _, spec in ipairs({{8, 11, 12, 70}, {18, 18, 10, 60}}) do
		local found = 0
		for _, e in ipairs(REFSTRAT_ROUTE) do
			if e[1] == spec[1] and e[2][1] == spec[2] and e[2][2] == spec[3] then
				for _, t in ipairs(e) do if type(t) == "table" and t.s == "potion" and t.hp == spec[4] then t.hp = 0; t.yolo = 0; found = found + 1 end end
			end
		end
		assert(found == 1, "v26: potion step " .. spec[4] .. " found " .. found .. " times")
	end
	-- Viridian: banked Full Restore before the forced-Potion step
	local done = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 1 and e[2][1] == 23 and e[2][2] == 26 then
			for j, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and t.hp == 80 and t.forced == "potion" then table.insert(e, j, {s = "refLateFR"}); done = done + 1; break end
			end
		end
	end
	assert(done == 1, "v26: Viridian potion step found " .. done .. " times")
end
-- v35 RED_LATE: close the red-HP window (and heal) on entering Bruno's room
if RED_LATE then
	local done = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 246 and e[2][1] == 4 and e[2][2] == 5 then table.insert(e, 4, {s = "refRedEnd"}); done = done + 1 end
	end
	assert(done == 1, "v35: Bruno entry found " .. done .. " times")
end
-- v43 RED_BRUNO (experiments/overnight-2026-10-16/redmap): the window may stay open through Bruno; Agatha's room closes it
if RED_LATE and RED_BRUNO then
	local done = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 247 and e[2][1] == 4 and e[2][2] == 5 then table.insert(e, 4, {s = "refRedEnd", agatha = true}); done = done + 1 end
	end
	assert(done == 1, "v43: Agatha entry found " .. done .. " times")
end

-- v50 errand cuts (Sol ERRANDS.md), default off
local function v50entry(map, x, y)
	local found
	for _, e in ipairs(REFSTRAT_ROUTE) do if e[1] == map and e[2][1] == x and e[2][2] == y then assert(not found, "v50: duplicate entry"); found = e end end
	return assert(found, "v50: entry " .. map .. " not found")
end
local function v50replace(e, old, new)   -- old/new: lists of tiles ({x,y}) or "skip" (= the refSkipPickup step)
	local function same(t, o)
		if o == "skip" then return type(t) == "table" and t.s == "refSkipPickup" end
		return type(t) == "table" and t[1] == o[1] and t[2] == o[2] and t.s == nil
	end
	for i = 1, #e - #old + 1 do
		local ok = true
		for k = 1, #old do if not same(e[i + k - 1], old[k]) then ok = false break end end
		if ok then
			for _ = 1, #old do table.remove(e, i) end
			for k = #new, 1, -1 do table.insert(e, i, new[k]) end
			return
		end
	end
	error("v50: sequence not found")
end
if MANSION_SPUR_CUT then
	local e = v50entry(216, 23, 22)
	v50replace(e, {{12,6}, {12,2}, {11,2}, "skip", {12,2}, {12,7}}, {{12,6}, {12,7}})
	v50replace(e, {{4,7}, {4,9}, {2,9}, "skip", {5,9}}, {{4,7}, {4,9}, {5,9}})
end
if SKIP_INDIGO_PC then
	local e = v50entry(174, 7, 11)
	assert(type(e[3]) == "table" and e[3][1] == 15 and e[3][2] == 9 and e[5].s == "depositPokemon" and e[6][1] == 7 and e[6][2] == 8, "v50: Indigo row changed")
	for _ = 1, 4 do table.remove(e, 3) end   -- {15,9} {15,8} depositPokemon {7,8}; keeps {7,11} -> {7,7}
end
-- v52 LAVENDER_FLOOR (DIAG9 #2): mark the Fly-to-Lavender potion step (target HP 10); S.potion raises it to the Tower
-- rival Pidgeotto's max non-critical hit + 1 when a plain Potion is in the bag
if LAVENDER_FLOOR then
	local e, done = v50entry(27, 7, 6), 0
	for _, t in ipairs(e) do
		if type(t) == "table" and t.s == "potion" and t.hp == 10 then t.refLavenderFloor = true; done = done + 1 end
	end
	assert(done == 1, "v52: Lavender potion step found " .. done .. " times")
end

-- MENU_FIX2 (experiments/target-policy-2026-10-17/menus/RESEARCH.md), default off = the v58 route. START-menu chaining
-- and bag-order fixes OUTSIDE the timed RNG chains. Post-Surge: MENU_FIX2 = true enables PPUP, MANSION, SURF and LANCE;
-- MENU_FIX2_<NAME> = true / false overrides one. Pre-Surge (MOON, BILL) only with their own switch: they shift every
-- unmanipulated random event between that menu and the Surge save (the timed chains themselves are untouched).
local function mf2(name, preSurge)
	local v = rawget(_G, "MENU_FIX2_" .. name)
	if v == nil and not preSurge then v = rawget(_G, "MENU_FIX2") end
	return v == true
end
local function mf2entry(map, x, y, pred)   -- the one entry with this origin (and, if given, a step matching pred)
	local found
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == map and e[2][1] == x and e[2][2] == y then
			local ok = pred == nil
			for _, t in ipairs(e) do if pred and type(t) == "table" and t.s and pred(t) then ok = true end end
			if ok then assert(not found, "MENU_FIX2: duplicate entry " .. map); found = e end
		end
	end
	return assert(found, "MENU_FIX2: entry " .. map .. " (" .. x .. "," .. y .. ") not found")
end
local function mf2step(e, pred)
	for k = 2, #e do local t = e[k]; if type(t) == "table" and t.s and pred(t) then return k, t end end
	error("MENU_FIX2: step not found in entry " .. e[1])
end
-- (1) Safari gate (map 190): PP Up keeps the bag open for TM26 -> one START session instead of two
if mf2("PPUP") then
	local e = mf2entry(190, 0, 4)
	local k, t = mf2step(e, function(t) return t.s == "refPPUp" end)
	assert(e[k + 1].s == "refTeach" and e[k + 1].move == "earthquake", "MENU_FIX2: Safari gate steps changed")
	t.chain = true
	table.insert(e, k + 2, {s = "refMf2Close"})   -- closes the bag if the Earthquake step had nothing to teach
end
-- (2) Mansion B1F (5,10): Strength (HM04, kept in the bag) first and chained, then Blizzard (TM14, used up: pokered
-- RemoveItemFromInventory resets the bag cursor and scroll to the top). Before: Blizzard 18 scroll steps, close,
-- reopen, Strength 17 steps, and the post-Mansion Celadon bicycle scrolled 18 steps back up from HM04. After:
-- Strength 17, Blizzard 1, bicycle 0.
if mf2("MANSION") then
	local e = mf2entry(216, 23, 22)
	local k = mf2step(e, function(t) return t.s == "refMakeSpace" end)
	local b, m, s = e[k - 1], e[k], e[k + 1]
	assert(b.s == "refTeach" and b.move == "blizzard" and s.s == "teach" and s.move == "strength" and s.chain,
		"MENU_FIX2: Mansion steps changed")
	e[k - 1], e[k], e[k + 1] = s, b, m        -- teach strength (chain) -> refTeach blizzard (closes) -> refMakeSpace
end
-- (3) Surf: taught in the Pallet Super Repel / Rare Candy menu (the record's order) instead of its own menu at the
-- Safari exit. Bag: Super Repel (1) -> HM03 (bottom) -> Rare Candy (3 up) -> Bicycle; the Safari exit only Digs.
if mf2("SURF") then
	local w = mf2entry(219, 3, 4)
	local k, t = mf2step(w, function(t) return t.s == "teach" and t.move == "surf" end)
	table.remove(w, k)
	local p = mf2entry(0, 5, 6, function(t) return t.s == "item" and t.item == "rare_candy" end)
	local kr = mf2step(p, function(t) return t.s == "item" and t.item == "rare_candy" end)
	assert(p[kr - 1].s == "item" and p[kr - 1].item == "super_repel" and p[kr - 1].chain, "MENU_FIX2: Pallet steps changed")
	assert(type(p[kr + 1]) == "table" and p[kr + 1].s == "bicycle", "MENU_FIX2: Pallet bicycle step changed")
	t.chain = true
	table.insert(p, kr, t)                    -- super_repel -> teach surf (chain) -> rare_candy (chain) -> bicycle
end
-- (4) Lance's room: the PP items keep the bag open for prepareForLance's chained Super Potion; refCloseMenu closes
if mf2("LANCE") then
	local e = mf2entry(113, 6, 11)
	local k = mf2step(e, function(t) return t.s == "refRestorePP" end)
	assert(e[k + 1].s == "refRestoreBlizzard" and e[k + 2].s == "prepareForLance" and e[k + 3].s == "refCloseMenu",
		"MENU_FIX2: Lance steps changed")
	e[k].chain, e[k + 1].chain = true, true
end
-- (5) PRE-SURGE, own switch only: Mt. Moon B2F menu, first pass: Rare Candy -> TM12 -> Moon Stone -> TM01 in one START
-- session (TM01 closes; refMf2Close after it if TM01 had nothing to do). The post-Nerd repeat is unchanged.
if mf2("MOON", true) then
	local e = mf2entry(61, 10, 17)
	local k = mf2step(e, function(t) return t.s == "refCandyEvolve" end)
	assert(e[k + 1].s == "refTeach" and e[k + 1].move == "water_gun" and e[k + 2].s == "refMoonStone"
		and e[k + 3].s == "refTeach" and e[k + 3].move == "mega_punch", "MENU_FIX2: Moon steps changed")
	e[k].chain, e[k + 1].chain, e[k + 2].chain = true, true, true
	table.insert(e, k + 4, {s = "refMf2Close"})
end
-- (6) PRE-SURGE, own switch only: Bill's house, the Rare Candies keep the bag open for refBillPotions (chain) and the
-- Escape Rope (which closes the menu itself)
if mf2("BILL", true) then
	local e = mf2entry(88, 2, 7)
	local k, t = mf2step(e, function(t) return t.s == "refUseIf" and t.item == "rare_candy" end)
	assert(e[k + 2].s == "refBillPotions" and e[k + 2].chain and e[k + 3].s == "item" and e[k + 3].item == "escape_rope",
		"MENU_FIX2: Bill steps changed")
	t.chain = true
end

-- v62 IT_REFRESH (experiments/ship-it-2026-10-17, owner 17 Oct: S.S. Anne rival fix), default off = v60 route. A
-- Cerulean Pokemon Center (nurse YES/NO) or Mart (list menu) ends the Bike Shop instant text: 126 + 17 of 336 v60 Surge
-- arrivals lost it there (time-analysis-2026-10-17/it_rival.py). After those optional visits refBikeRefresh talks to the
-- Bike Shop clerk again (only if the flag is off), as the community route does ("Get instant text from the bike shop
-- again", pastebin.com/EGbBXsTK), so the text stays instant through Route 6, the S.S. Anne rival and the captain.
if IT_REFRESH then
	local function entry(map, x, y, pred)
		local found
		for _, e in ipairs(REFSTRAT_ROUTE) do
			if e[1] == map and e[2][1] == x and e[2][2] == y then
				for k, t in ipairs(e) do if type(t) == "table" and t.s and pred(t) then assert(not found, "v62: duplicate"); found = {e, k} end end
			end
		end
		return assert(found, "v62: entry " .. map .. " (" .. x .. "," .. y .. ") not found")
	end
	-- row 16 (before Misty): after the conditional Center at (19,17)
	local a = entry(3, 27, 11, function(t) return t.s == "refMaybeHeal" and t.mistyFloor end)
	table.insert(a[1], a[2] + 1, {s = "refBikeRefresh", at = "row 16"})
	-- row 17 (after Misty): after the conditional Center and Mart
	local b = entry(3, 30, 20, function(t) return t.s == "refMaybeMart" end)
	assert(b[1][b[2] - 1].s == "refMaybeHeal" and b[1][b[2] - 1].postMisty, "v62: row 17 steps changed")
	table.insert(b[1], b[2] + 1, {s = "refBikeRefresh", at = "row 17"})
end

-- v63 R3_RISK (experiments/risk-v63-2026-10-17, owner 17 Oct: "V62 is play too safe. Make it more risky."; Sol RISK1
-- rank 1), default off = v62 route. Route 3 exit Potion step (27,9): target 20 -> 14 (the step's own yolo value).
if R3_RISK then
	local found = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 14 and e[2][1] == 0 and e[2][2] == 10 then
			for _, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and t.hp == 20 and t.yolo == 14 then t.hp = 14; found = found + 1 end
			end
		end
	end
	assert(found == 1, "v63: Route 3 exit Potion step found " .. found .. " times")
end

-- v64 PARAS_RED (experiments/v64-2026-10-18, Sol TIME2 rank 3, owner 18 Oct): default off = v63 route. The Route 3
-- exit Potion step (27,9) heals only at <= PARAS_RED_HP (default 6; v63: 20, or 14 with R3_RISK), so runs keep low HP
-- into the Paras catch. The bot heals to full right after the catch (reference row 10), so only the Paras fight and the
-- Mt. Moon entrance are played low.
if PARAS_RED then
	local found = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 14 and e[2][1] == 0 and e[2][2] == 10 then
			for _, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and (t.hp == 20 or t.hp == 14) and t.yolo == 14 then
					t.hp = PARAS_RED_HP or 6; t.yolo = PARAS_RED_HP or 6; found = found + 1
				end
			end
		end
	end
	assert(found == 1, "v64: Route 3 exit Potion step found " .. found .. " times")
end

-- v65 BRIDGE_IT_REFRESH (experiments/v65-2026-10-19, owner 19 Oct "Yes you may build v65 like that"; finding:
-- experiments/misty-surge-audit-2026-10-19/REPORT.md). Default off = v64 route. After the Cerulean rival and the
-- pre-Bridge Center check, {s="refBikeRefreshBridge"} talks to the Bike Shop clerk again if instant text is off.
if BRIDGE_IT_REFRESH then
	local found
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 3 and e[2][1] == 9 and e[2][2] == 12 then
			for k, t in ipairs(e) do
				if type(t) == "table" and t.s == "refPreNuggetCenter" then assert(not found, "v65: duplicate"); found = {e, k} end
			end
		end
	end
	assert(found, "v65: refPreNuggetCenter step not found")
	assert(found[1][found[2] - 1].s == "rivalSandAttack", "v65: Cerulean rival steps changed")
	table.insert(found[1], found[2] + 1, {s = "refBikeRefreshBridge"})
end

-- v77 PARAS_RED2 (experiments/v77-2026-10-21, PM 22 Oct): default off = v75 route. The Route 3 exit Potion step
-- (27,9) runs S.refParasRed2Potion: no heal when the lead is already red, else the same Potion step as before.
-- (v64 PARAS_RED, dropped 18 Oct, also kept non-red runs low and kept the long catch script.)
if PARAS_RED2 then
	local found = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 14 and e[2][1] == 0 and e[2][2] == 10 then
			for _, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and t.yolo == 14 and (t.hp == 20 or t.hp == 14) then
					t.s = "refParasRed2Potion"; found = found + 1
				end
			end
		end
	end
	assert(found == 1, "v77: Route 3 exit Potion step found " .. found .. " times")
end
-- v77 R9_WAIT (team/scout/ROUTE9.md idea 3): default off = v75 route. Marks the Route 9 Jr. Trainer F talk step
-- (map 20, the talk before fourTurnThrash); S.talk may idle a few frames there (strategies.lua).
if R9_WAIT then
	local found = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 20 and e[2][1] == 0 and e[2][2] == 8 then
			for k, t in ipairs(e) do
				if type(t) == "table" and t.s == "talk" and t.dir == "Down" and type(e[k + 1]) == "table" and e[k + 1].s == "fourTurnThrash" then
					t.v77wait = true; found = found + 1
				end
			end
		end
	end
	assert(found == 1, "v77: Route 9 trainer talk step found " .. found .. " times")
end

-- v78 ROUTE22_REPEL (experiments/v78-2026-10-22/PLAN.md, scout LATEGAME_2026-10-22): default off = v77 route. Leaving
-- Viridian (map 1 (32,8)): one Super Repel, chained between the potion step and the bicycle, so the Route 22 grass
-- (x 30-33, wild level 2-5 < the lead) gives no wild fight. The extra Super Repel is bought at Celadon 2F (strategies.lua).
if ROUTE22_REPEL then
	local found = 0
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 1 and e[2][1] == 32 and e[2][2] == 8 then
			for k, t in ipairs(e) do
				if type(t) == "table" and t.s == "potion" and t.hp == 130 and t.chain and type(e[k + 1]) == "table" and e[k + 1].s == "bicycle" then
					table.insert(e, k + 1, {s = "item", item = "super_repel", chain = true, v78r22 = true}); found = found + 1
					break
				end
			end
		end
	end
	assert(found == 1, "v78: Viridian exit potion + bicycle steps found " .. found .. " times")
end

-- v86 (experiments/v86-2026-10-23): LAVENDER_LATE_HP. Defer the Celadon Horn Drill TM to Pokemon Tower 6F (before the
-- walk to the Marowak tile) so the Lavender rival is fought without X Accuracy. Default off = v83 route unchanged.
if LAVENDER_LATE_HP then
	local e27, e147
	for _, e in ipairs(REFSTRAT_ROUTE) do
		if e[1] == 27 and e[2][1] == 7 and e[2][2] == 6 then assert(not e27, "v86: two map 27 (7,6) rows"); e27 = e end
		if e[1] == 147 and e[2][1] == 18 and e[2][2] == 9 then assert(not e147, "v86: two map 147 (18,9) rows"); e147 = e end
	end
	assert(e27 and e147, "v86: map 27 / 147 row not found")
	local n = 0
	for _, t in ipairs(e27) do
		if type(t) == "table" and t.s == "teach" and t.move == "horn_drill" then t.s = "v86DrillCeladon"; n = n + 1 end
	end
	assert(n == 1, "v86: Celadon Horn Drill teach step count " .. n)
	local k
	for j, t in ipairs(e147) do
		if type(t) == "table" and t.s == "pokeDoll" then assert(not k, "v86: two pokeDoll steps"); k = j end
	end
	assert(k, "v86: pokeDoll step not found")
	-- v89: the walk to (10,16) starts the Marowak ghost battle; teach before it, at (10,14)
	assert(type(e147[k - 1]) == "table" and e147[k - 1][1] == 10 and e147[k - 1][2] == 16, "v89: (10,16) not before pokeDoll")
	assert(type(e147[k - 2]) == "table" and e147[k - 2][1] == 10 and e147[k - 2][2] == 14, "v89: (10,14) not before (10,16)")
	table.insert(e147, k - 1, {s = "v86DrillLate"})
end
