local Arp={}

-- https://monome.org/docs/norns/reference/lib/sequins
local Sequins=require 'sequins'

-- initializer for arpeggio
function Arp:new(o)
  o=o or {} -- create object if user does not provide one
  setmetatable(o,self)
  self.__index=self
  o:init()
  if o.menu==true then
    o:make_menu()
  end
  return o
end

function Arp:make_menu()
  -- TODO: add menu
end

function Arp:init()
  -- define time signature
  self.time_signature=2
  self.time_signatures={"1/32","1/16","1/16T","1/8","1/8T","1/4","1/2","1"}
  self.time_divisions={1/32,1/16,1/12,1/8,1/6,1/4,1/2,1}

  -- define duration (number of 1/16th notes)
  self.duration=8

  -- define length multiplier
  -- which will increase the arpeggio over more octaves
  self.length=1

  -- define possible shapes
  self.shape=1
  self.shapes={"up","down","up-down","down-up","converge","diverge","converge-diverge","diverge-converge","random"}

  -- define possible modes
  self.mode=1
  self.modes={"12","+12,-12","+7,+9,-5","2,4,5,7,9"}

  -- define the trigger that will trigger the mode
  self.trigger=1
  self.triggers={"none","first","last","each"}

  -- the original notes
  self.notes={}

  -- the sequins sequence
  self.seq=nil
end

function Arp:sequencer_init()
  local lattice=include("mx.synths/lib/lattice")
  self.lattice=lattice:new{}
  local division=1/8 -- TODO make this configurable
  local note_off_offset = 0.5 -- TODO make this configurable (note length)

  local notes_on = {} -- keeps track of which notes are on
  self.pattern_note_on=self.lattice:new_pattern{
    action=function(t)
      -- trigger next note in sequence
      if self.note_on~=nil then
        local note_new=self:next()
        if note_new~=nil then
          notes_on[note_new]=true
          self.note_on(note_new)
        end
      end
    end,
    division=division,
  }
  self.pattern_note_off=self.lattice:new_pattern{
    action=function(t)
      -- trigger next note in sequence
      if self.note_off~=nil then
        for note,_ in pairs(notes_on) do
          self.note_off(note)
          notes_on[note]=nil
        end
      end
    end,
    division=division,
    offset=note_off_offset,
  }
end

function Arp:sequencer_start()
  if not self.sequencer_started then
    self.lattice:hard_restart()
  end
  self.sequencer_started=true
end

function Arp:sequencer_stop()
  self.lattice:stop()
  self.sequencer_started=false
end

function Arp:refresh()
  self.seq=nil
  if #self.notes==0 then
    do return end
  end

  -- define the root
  local root=self.notes[1]

  -- hold the temporary sequence
  local s={}

  -- first setup the basic sequence
  -- with arbitrary number of octaves
  for octave=0,4 do
    for i,n in ipairs(self.notes) do
      table.insert(s,n+(octave*12))
    end
  end

  -- truncate the sequence to the length
  local notes_total=math.floor(self.length*#self.notes)
  if notes_total==0 then
    do return end
  end
  s={table.unpack(s,1,notes_total)}

  -- create reverse table
  local s_reverse={}
  for i=#s,1,-1 do
    table.insert(s_reverse,s[i])
  end

  -- create the sequence based on the shapes
  if self.shapes[self.shape]=="down" then
    -- down
    -- 1 2 3 4 5 becomes
    -- 5 4 3 2 1
    s=s_reverse
  elseif self.shapes[self.shape]=="up-down" then
    -- up-down
    -- 1 2 3 4 5 becomes
    -- 1 2 3 4 5 4 3 2
    for i,n in ipairs(s_reverse) do
      if i>1 and i<#s_reverse then
        table.insert(s,n)
      end
    end
  elseif self.shapes[self.shape]=="down-up" then
    -- down-up
    -- 1 2 3 4 5 become
    -- 5 4 3 2 1 2 3 4
    local s2={}
    for _,n in ipairs(s_reverse) do
      table.insert(s2,n)
    end
    for i,n in ipairs(s) do
      if i>1 and i<#s_reverse then
        table.insert(s2,n)
      end
    end
    s=s2
  end

  -- now "s" has the basic sequence
  -- add the special notes based on root
  if self.triggers[self.trigger]~="none" then
    local ss=Sequins{root+12}
    if self.modes[self.mode]=="+12,-12" then
      ss=Sequins{root+12,root-12}
    elseif self.modes[self.mode]=="+7,+9,-5" then
      ss=Sequins{root+7,root+9,root-5}
    elseif self.modes[self.mode]=="2,4,5,7,9" then
      ss=Sequins{root+2,root+4,root+5,root+7,root+9}
    end
    local s2={}
    for i,n in ipairs(s) do
      table.insert(s2,n)
      if i==1 and self.triggers[self.trigger]=="first" then
        table.insert(s2,ss)
      elseif i==#s and self.triggers[self.trigger]=="last" then
        table.insert(s2,ss)
      elseif self.triggers[self.trigger]=="each" then
        table.insert(s2,ss)
      end
    end
    s=s2
  end

  -- convert to a sequins
  if self.seq==nil then
    self.seq=Sequins(s)
  else
    self.seq:settable(s)
  end
end

function Arp:next()
  if self.seq~=nil then
    do return self.seq() end
  end
end

function Arp:contains(note)
  for i,n in ipairs(self.notes) do
    if note==n then
      do return i end
    end
  end
end

function Arp:add(note)
  if self:contains(note) then
    self:remove(note)
  end
  table.insert(self.notes,note)
  self:refresh()
  print("Arp: added "..note)
end

function Arp:remove(note)
  local notes={}
  for i,n in ipairs(self.notes) do
    if n~=note then
      table.insert(notes,n)
    end
  end
  self.notes=notes
  self:refresh()
  print("Arp: removed "..note)
end

-- local arp=Arp:new()
-- arp.length=2
-- arp.shape=3 -- up down
-- arp.trigger=2 -- trigger the mode after the first note
-- arp.mode=2 -- when triggered play a +12/-12 octave
-- arp:add(0)
-- arp:add(3)
-- arp:add(5)
-- arp:remove(3)
-- arp:add(7)
-- for i,n in ipairs(arp.seq) do
--   print(i,n)
-- end
-- local ss=""
-- for i=1,20 do
--   ss=ss.." "..arp:next()
-- end
-- print(ss)

-- local s=Sequins{1,1,1}
-- local seq=Sequins{1,s,3,s}
-- for i=1,6 do
--   print(seq())
-- end
-- seq:settable({1,2,3,4})
-- for i=1,5 do
--   print(seq())
-- end

return Arp