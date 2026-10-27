-- No changes until Brock's final Pokemon has fainted. Faster closing dialogue.
do
 local Input=require "util.input"
 local Memory=require "util.memory"
 local press,exec=Input.press,Strategies.execute
 local current
 Strategies.execute=function(data) current=data.s;return exec(data) end
 Input.press=function(button,frames,walk)
  if current=="fightBrock" and button=="A" and frames==nil and Memory.value("battle","menu")==95
   and Memory.value("battle","opponent_id")==34 and Memory.double("battle","opponent_hp")==0
   and Memory.value("battle","text")~=20 then return Input.cancel() end
  return press(button,frames,walk)
 end
end
