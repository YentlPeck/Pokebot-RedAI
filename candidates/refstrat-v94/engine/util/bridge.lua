local Bridge = {polling = false}
local Utils = require "util.utils"
local function noop() end
function Bridge.init() end
function Bridge.tweet() if STREAMING_MODE then return true end end
function Bridge.pollForName() Bridge.polling = true end
function Bridge.chatRandom(...) return Bridge.chat(Utils.random(arg)) end
function Bridge.chat() return true end
Bridge.time = noop
function Bridge.stats() return true end
Bridge.command = noop
Bridge.comparisonTime = noop
Bridge.process = noop
Bridge.input = noop
Bridge.caught = noop
Bridge.hp = noop
Bridge.liveSplit = noop
function Bridge.split(finished) Utils.splitUpdate() end
Bridge.pausegametime = noop
Bridge.encounter = noop
Bridge.report = noop
Bridge.guessing = noop
Bridge.guessResults = noop
Bridge.moonResults = noop
Bridge.reset = noop
Bridge.close = noop
return Bridge
