------------------
-- this module play generic missions encoded in a json data format
-- @module MissionPlayer
-- ----------------
--
local maxHealth, tmp
local json=VFS.Include("LuaUI/Widgets/libs/LuaJSON/dkjson.lua")
local lang = Spring.GetModOptions()["language"] -- get the language
local jsonPartName = Spring.GetModOptions()["missionname"]
local replacements={}
replacements["gray"] = "\255\100\100\100"

local ctx={}
--ctx is a table containing main variables and functions (cf end of file). 
--ctx passed as a "context" when loading custom code from the user (script actions). 
--This way, the user can get and set values related to the game 

ctx.debugLevel=1 -- in order to filter Spring Echo between 0 (all) and 10 (none)
ctx.armySpring={}--table to store created spring units externalId (number or string)->SpringId (number)
ctx.armyExternal={}--table to store created spring units SpringId (number)->externalId (number)
ctx.groupOfUnits={}--table to store group of units externalIdGroups-> list of externalIdUnits
ctx.groupOfUndeletedUnits={}--same as ctx.groupOfUnits except that units are never deleted (usefull to count kills)
ctx.armyInformations={}--table to store information on units externalId->Informations
ctx.messages={}--associative array messageId->message type
ctx.conditions={}--associative array idCond->condition
ctx.events={}--associative array idEvent->event
ctx.orderedEventsId={}--associative array order->idEvent
ctx.variables={}--associative array variable->value Need to be global so that it can be updated by using loadstring
ctx.zones={}--associative array idZone->zone
ctx.kills={}
ctx.timeUntilPeace=5 -- how much time in seconds of inactivity to declare that an attack is no more
ctx.attackedUnits={}
ctx.attackingUnits={}
ctx.recordCreatedUnits=false
ctx.refreshPeriod=10 -- must be between 1 and 16. The higher the less cpu involved. 
ctx.actionStack={} -- action to be applied on game state, allows to handle table composed by the indexes delay and actId
ctx.success=nil -- when this global variable change (with event of type "end"), the game ends (= victory or defeat)
ctx.outputstate=nil -- if various success or defeat states exist, outputstate can store this information. May be used later such as in AppliqManager to enable adaptative scenarisation
ctx.canUpdate=false
ctx.mission=nil -- the full json describing the mission
ctx.startingFrame=5 -- added delay before starting game. Used to avoid counting twice units placed at start
ctx.globalIndexOfCreatedUnits=0 -- count the number of created units. Both in-game (constructor) and event-related (action of creation) 
ctx.speedFactor=1 -- placeHolder to store current speed
-- the next one is a bit different
ctx.customInformations={}--dedicated for storing information related to the execution of scripts described in "script" actions editor

-- Brainless copy-pasta from http://lua-users.org/wiki/SortedIteration, 
-- in order to sort events by order of execution
-- 1/3
local function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
end

-- Brainless copy-pasta from http://lua-users.org/wiki/SortedIteration, 
-- in order to sort events by order of execution
-- 2/3
local function orderedNext(t, state)
    -- Equivalent of the next function, but returns the keys in the alphabetic
    -- order. We use a temporary ordered key table that is stored in the
    -- table being iterated.

    key = nil
    --print("orderedNext: state = "..tostring(state) )
    if state == nil then
        -- the first time, generate the index
        t.__orderedIndex = __genOrderedIndex( t )
        key = t.__orderedIndex[1]
    else
        -- fetch the next value
        for i = 1,table.getn(t.__orderedIndex) do
            if t.__orderedIndex[i] == state then
                key = t.__orderedIndex[i+1]
            end
        end
    end

    if key then
        return key, t[key]
    end

    -- no more value to return, cleanup
    t.__orderedIndex = nil
    return
end

-- Brainless copy-pasta from http://lua-users.org/wiki/SortedIteration, 
-- in order to sort events by order of execution
-- 3/3
local function orderedPairs(t)
    -- Equivalent of the pairs() function on tables. Allows to iterate
    -- in order
    return orderedNext, t, nil
end


local function EchoDebug(message,level)
  local level=level or 10
  if(level >= ctx.debugLevel)then
    Spring.Echo(message)
  end
end

-------------------------------------
-- Load codegiven an environnement (table of variables that can be accessed and changed)
-- This function ensure compatibility (setfenv is dropped from lua 5.2)
-- Shamelessly taken from http://stackoverflow.com/questions/9268954/lua-pass-context-into-loadstring
-------------------------------------
local function load_code(code)
    if setfenv and loadstring then
        local f = assert(loadstring(code))
        setfenv(f,ctx)
        return f()
    else
        local f=assert(load(code, nil,"t",ctx))
        return f()
    end
end

local function intersection(list1,list2)
  local inters={}
  if list1==nil then return nil end
  if list2==nil then return nil end
  for i,el in pairs(list1)do
    for i2,el2 in pairs(list2)do
      if(el==el2)then
        table.insert(inters,el)
        break
      end
    end
  end
  return inters
end

-- warning, if intersection is non void, duplicates will occur.
local function union(list1,list2)
  local union={}
  if (list1~=nil) then
    for i,el in pairs(list1)do
      table.insert(union,el)
    end
  end  
  if (list2~=nil) then
    for i,el in pairs(list2)do
      table.insert(union,el)
    end
  end
  return union
end

-- must give a number, string under the form of "8", "3" or v1+v2-3
local function computeReference(expression)
  EchoDebug("compute expression : "..expression)
  if(expression==nil or expression=="") then return expression end
  local n1=tonumber(expression)
  if(n1~=nil)then return n1 end

  for v,value in pairs(ctx.variables)do
    expression=string.gsub(expression, v, tostring(value))
  end
  EchoDebug("expression before execution : "..expression)
  local executableStatement="return("..expression..")"
  return load_code(executableStatement)
end

-------------------------------------
-- Compare an expression to a numerical value, a verbal "mode" being given 
-- @return boolean
-------------------------------------
local function compareValue_Verbal(reference,maxRef,value,mode)
  EchoDebug(json.encode{reference,maxRef,value,mode},1)
  reference=computeReference(reference)
  if(mode=="atmost")then return (value<=reference)      
  elseif(mode=="atleast")then  return (value>=reference)    
  elseif(mode=="exactly")then return (reference==value)  
  elseif(mode=="all")then return (maxRef==value)
  end
end

-------------------------------------
-- Compare numerical values, a numerical "mode" being given 
-- @return boolean
-------------------------------------
local function compareValue_Numerical(v1,v2,mode) 
  v1 = tonumber(v1)
  v2 = tonumber(v2)
  if(mode==">") then return v1>v2  end
  if(mode==">=")then return v1>=v2 end
  if(mode=="<") then return v1<v2  end
  if(mode=="<=")then return v1<=v2 end
  if(mode=="==")then return v1==v2 end
  if(mode=="!=")then return v1~=v2 end
end 

-------------------------------------
-- Make an operation, a numerical "operator" being given 
-- @return number
-------------------------------------
local function makeOperation(v1,v2,operation)
  if(operation=="*")then return v1*v2 end
  if(operation=="+")then return v1+v2 end
  if(operation=="-")then return v1-v2 end
  if(operation=="/")then
    if(v2~=0)then return v1/v2 end
    else
      EchoDebug("division by 0 replaced by division by 1",4)
      return v1
    end
  if(operation=="%")then return v1 - math.floor(v1/v2)*v1 end
end

-------------------------------------
-- Deep copy of tables 
-- @return table
-------------------------------------
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-------------------------------------
-- Convert delay in seconds into delay in number of frames
-- @return delay in number of frames
-------------------------------------
local function secondesToFrames(delaySec)
  return delaySec*16 -- As Sync code is updated 16 times by seconds
end


-------------------------------------
-- Simple faction to get spring code given its string representation
-- @return faction code, related to factions described in txt files (such as Mission1.txt)
-------------------------------------
local function getFactionCode(factionType)
  if(factionType=="PLAYER") then
    return 0
  elseif (factionType=="ALLY") then
    return 1
  elseif (factionType=="ENNEMY") then
    return 2
  end
end

-------------------------------------
-- Return string litteral representation of a boolean 
-------------------------------------
local function boolAsString(booleanValue)
  if (booleanValue) then
    return "true"
  else
    return "false"
   end
end 

-------------------------------------
-- Get a message from a message table
-- If the message is not unique (a list), taking one by random
-------------------------------------
local function getAMessage(messageTable) 
  if(messageTable[1]==nil) then
    return messageTable
  else
    return messageTable[math.random(#messageTable)]
  end
end

-------------------------------------
-- Indicates if a point is inside a zone (disk or rectangle)
-- @return boolean
-------------------------------------
local function isXZInsideZone(x,z,zoneId)
  local zone=ctx.zones[zoneId]
  if(zone==nil)then
    EchoDebug(string.format("%s not found. ZoneLists : %s",zoneId,json.encode(ctx.zones)),5)
  end
  if(zone.type=="Rectangle") then
    local center_x=zone.center_xz.x
    local center_z=zone.center_xz.z
    if(center_x+zone.demiLargeur<x)then return false end -- uncommon formatting but multiline looks better IMHO
    if(center_x-zone.demiLargeur>x)then return false end
    if(center_z+zone.demiLongueur<z)then return false end
    if(center_z-zone.demiLongueur>z)then return false end
    return true
  elseif(zone.type=="Disk") then
    local center_x=zone.center_xz.x
    local center_z=zone.center_xz.z
    local apart=((center_x-x)*(center_x-x))/((zone.a)*(zone.a))
    local bpart=((center_z-z)*(center_z-z))/((zone.b)*(zone.b))
    return (apart+bpart<1)
  end
end

-------------------------------------
-- Indicates if an unit is inside a zone (disk or rectangle)
-- @return boolean
-------------------------------------
local function isUnitInZone(springUnit,idZone)
  local x, y, z = Spring.GetUnitPosition(springUnit)
  return isXZInsideZone(x,z,idZone)
end

-------------------------------------
-- draw a position randomly drawn within a zone
-- @return table with x,z attributes 
-------------------------------------
local function getARandomPositionInZone(idZone)
  if(ctx.zones[idZone]~=nil) then
    local zone=ctx.zones[idZone]
    local posit={}
    local center_x=zone.center_xz.x
    local center_z=zone.center_xz.z
    if(zone.type=="Disk") then
      while true do -- rejection method to draw random points from ellipse (drawn from rectangle and accepted if inside ellipse
        local x=math.random(center_x-zone.a, center_x+zone.a)
        local z=math.random(center_z-zone.b, center_z+zone.b)
        if(isXZInsideZone(x,z,idZone))then
          posit["x"]=x
          posit["z"]=z
          return posit
        end
      end
    elseif(zone.type=="Rectangle") then
      local x=math.random(center_x-zone.demiLargeur, center_x+zone.demiLargeur)
      local z=math.random(center_z-zone.demiLongueur, center_z+zone.demiLongueur)
      posit["x"]=x
      posit["z"]=z
      return posit
    end 
  end   
end

-------------------------------------
-- Extract position from parameters
-- Sometimes a zone is given and getARandomPositionInZone will be called
-------------------------------------
local function extractPosition(tablePosOrMaybeJustZoneId)
  if(type(tablePosOrMaybeJustZoneId)=="number")then
    return getARandomPositionInZone(tablePosOrMaybeJustZoneId)
  else
    return tablePosOrMaybeJustZoneId
  end
end
-------------------------------------
-- Write letter on map giving its position
-- Only O,W,N,S,E implemented
------------------------------------- 
local function writeLetter(x, y, z, letter)
  if letter == "O" then
    -- write letter
    Spring.MarkerAddLine(x-5, y, z-8, x+5, y, z-8)
    Spring.MarkerAddLine(x+5, y, z-8, x+5, y, z+8)
    Spring.MarkerAddLine(x+5, y, z+8, x-5, y, z+8)
    Spring.MarkerAddLine(x-5, y, z+8, x-5, y, z-8)
  elseif letter == "W" then
    -- write letter
    Spring.MarkerAddLine(x-5, y, z-8, x-2.5, y, z+8)
    Spring.MarkerAddLine(x-2.5, y, z+8, x, y, z)
    Spring.MarkerAddLine(x, y, z, x+2.5, y, z+8)
    Spring.MarkerAddLine(x+2.5, y, z+8, x+5, y, z-8)
  elseif letter == "N" then
    -- write letter
    Spring.MarkerAddLine(x-5, y, z+8, x-5, y, z-8)
    Spring.MarkerAddLine(x-5, y, z-8, x+5, y, z+8)
    Spring.MarkerAddLine(x+5, y, z+8, x+5, y, z-8)
  elseif letter == "S" then
    -- write letter
    Spring.MarkerAddLine(x+5, y, z-8, x-5, y, z-8)
    Spring.MarkerAddLine(x-5, y, z-8, x-5, y, z)
    Spring.MarkerAddLine(x-5, y, z, x+5, y, z)
    Spring.MarkerAddLine(x+5, y, z, x+5, y, z+8)
    Spring.MarkerAddLine(x+5, y, z+8, x-5, y, z+8)
  elseif letter == "E" then
    -- write letter
    Spring.MarkerAddLine(x+5, y, z-8, x-5, y, z-8)
    Spring.MarkerAddLine(x-5, y, z-8, x-5, y, z+8)
    Spring.MarkerAddLine(x-5, y, z+8, x+5, y, z+8)
    Spring.MarkerAddLine(x-5, y, z, x, y, z)
  end
end

-------------------------------------
-- Write sign on map at given position
-- Only + and - are implemented
-------------------------------------
local function writeSign(x, y, z, sign)
  if sign == "+" then
    Spring.MarkerAddLine(x-5, y, z, x+5, y, z)
    Spring.MarkerAddLine(x, y, z-5, x, y, z+5)
  elseif sign == "-" then
    Spring.MarkerAddLine(x-5, y, z, x+5, y, z)
  end
end

-------------------------------------
-- show message on map 
-- instead of directly printing the message, replacements are made
-- to allow special elements such as colors. A global table, replacements is used to this effect
-------------------------------------
local function showMessage(content)
  local contentList=string.gmatch(content, '([^%.%.]+)') --split according the two dots (..) separator
  local message=""
  for chunk in contentList do
    if replacements[chunk]~=nil then
      message=message..replacements[chunk]
    else
      message=message..chunk
    end
  end
  Script.LuaRules.showMessage(message, false, 500)
end

-------------------------------------
-- Show Briefing, this function can be called from outside
-- For this reason all the json files must have a message with id BRIEFING
-------------------------------------
local function ShowBriefing ()
  --Spring.Echo(json.encode(mission))
  showMessage(getAMessage(ctx.messages["briefing"]))-- convention all json files have briefing attribute
end

local function registerUnit(springId,externalId,reduction,autoHeal)
    ctx.armySpring[externalId]=springId
    ctx.armyExternal[springId]=externalId
    -- default values if not given
    local reduction=reduction or 1
    local autoHeal=autoHeal or (ctx.mission.description.autoHeal=="enabled")
    
    ctx.armyInformations[externalId]={}
    local h=Spring.GetUnitHealth(springId)*reduction
    ctx.armyInformations[externalId].health=h
    if(reduction~=1)then
      Spring.SetUnitHealth(springId,h)
    end
    ctx.armyInformations[externalId].previousHealth=ctx.armyInformations[externalId].health
    ctx.armyInformations[externalId].autoHeal = UnitDefs[Spring.GetUnitDefID(springId)]["autoHeal"]
    ctx.armyInformations[externalId].idleAutoHeal = UnitDefs[Spring.GetUnitDefID(springId)]["idleAutoHeal"]
    ctx.armyInformations[externalId].autoHealStatus=autoHeal
    --Spring.Echo(ctx.armyInformations[externalId].autoHealStatus)
    ctx.armyInformations[externalId].isUnderAttack=false
    ctx.armyInformations[externalId].isAttacking=false
end

local function isInGroup(externalId,gp,testOnExternalsOnly)
  EchoDebug("is in group ->"..json.encode(gp),0)
  local isAlreadyStored=false
  if(gp==nil)then
    EchoDebug("group is nil in function isInGroup, this should not occur")
    return false, nil
  end
  if(testOnExternalsOnly)then
    for i = 1,table.getn(gp) do
      if(externalId==gp[i]) then return true,i end
    end
  else
    local spId=ctx.armySpring[externalId]
    for i = 1,table.getn(gp) do
      if(spId==ctx.armySpring[gp[i]]) then return true,i end
    end    
  end
  return false,nil
end

local function getGroupsOfUnit(externalId, testOnExternalsOnly, groupToCheck)
  local groupToCheck = groupToCheck or ctx.groupOfUnits
  local groups={}
  for indexGroup,g in pairs(groupToCheck)do
    local inGp,_ = isInGroup(externalId,g,testOnExternalsOnly)
    if(inGp)then
      table.insert(groups,indexGroup)
    end
  end
  return groups
end
 
local function removeUnitFromGroups(externalId,groups,testOnExternalsOnly)
  local testOnExternalsOnly=testOnExternalsOnly or true 
  for g,group in pairs(groups) do
    if(ctx.groupOfUnits[group]~=nil) then 
      local _,i=isInGroup(externalId,ctx.groupOfUnits[group],testOnExternalsOnly)
      if(i~=nil)then table.remove(ctx.groupOfUnits[group],i) end
    end
  end
end

local function addUnitToGroups_groupToStoreSpecified(externalId,groups,testOnExternalsOnly,groupToStore)
  local testOnExternalsOnly=testOnExternalsOnly or true 
  -- usefull to check redundancy at a deeper level because, when it comes about unit creation
  -- units can have a different external id (e.g "Action1_0","createdUnit_1") for the same spring id  
  for g,group in pairs(groups) do
      -- create group if not existing
    if(groupToStore[group]==nil) then
      groupToStore[group]={}
    end   
    -- store in group if not already stored
    local isAlreadyStored,_=isInGroup(externalId,groupToStore[group],testOnExternalsOnly)
    if(not isAlreadyStored)then   
      table.insert(groupToStore[group],externalId)
    end
  end
end

-- add Unit to specified groups
-- side effect : add the unit to the overarching group : "team_all".
local function addUnitToGroups(externalId,groups,testOnExternalsOnly)
  table.insert(groups,"team_all")
  addUnitToGroups_groupToStoreSpecified(externalId,groups,testOnExternalsOnly,ctx.groupOfUnits)
  addUnitToGroups_groupToStoreSpecified(externalId,groups,testOnExternalsOnly,ctx.groupOfUndeletedUnits)
end  

local function addUnitsToGroups(units,groups,testOnExternalsOnly)
  for u,unit in pairs(units) do
    addUnitToGroups(unit,groups,testOnExternalsOnly)
  end
end

local function unitSetParamsToUnitsExternal(param)
  local index = param.type..'_'..tostring(param.value)
  local units = ctx.groupOfUnits[index]
  if(ctx.groupOfUnits[index] == nil)then
    EchoDebug("warning. This index gave nothing : "..index,7)
  end
  return units
end
   
-------------------------------------
-- Check if a condition, expressed as a string describing boolean condition where variables
-- are related to conditions in the json files.
-------------------------------------
local function isTriggerable(event)
  --Spring.Echo(json.encode(ctx.conditions))
  local trigger=event.trigger
  if(trigger=="")then   -- empty string => create trigger by cunjunction (ands) of all conditions
  -- step 1 : write the trigger
    for c,cond in pairs(event.listOfInvolvedConditions) do
      trigger=trigger..cond.." and "
    end
    trigger=string.sub(trigger,1,-5) -- drop the last "and"
  end
  for c,cond in pairs(event.listOfInvolvedConditions) do
    -- second step : conditions are replaced to their boolean values.
    local valueCond=ctx.conditions[cond.."_"..tostring(event.id)]
    trigger=string.gsub(trigger, cond, boolAsString(valueCond["currentlyValid"]))
  end
  -- third step : turn the string in return statement
  local executableStatement="return("..trigger..")"
  local f = loadstring(executableStatement)
   -- fourth step : loadstring is used to create the function.
  return(f())
end

-------------------------------------
-- Extract the list of units related to a condition
-- If we are in the context of action, it's possible that a list
-- has already been compiled from previous condition checking process
-- in this case, units_extracted is an index for this list
-------------------------------------
local function extractListOfUnitsImpliedByCondition(conditionParams,groupToCheck)
  local groupToCheck = groupToCheck or ctx.groupOfUnits
  --EchoDebug("debug : "..tostring(id))
  --Spring.Echo("extract process")
  --Spring.Echo(json.encode(conditionParams))
  --Spring.Echo(json.encode(ctx.groupOfUnits))
  
  if(conditionParams["units_extracted"]~=nil)then 
  -- when units_extracted exists, this means we are in the context of action.
  -- and that uniset has been set at the moment of the execution of the event
    return conditionParams["units_extracted"]
  end
  
  local groupToReturn={}
  if(conditionParams.unitset~=nil)then
     -- gives something like action_1, condition_3, groupe_2, team_0*
     if (conditionParams.unitset.type=="unit") then
      groupToReturn={conditionParams.unitset.value}
      EchoDebug(json.encode({conditionParams,groupToReturn}),2)
     else
       local index=conditionParams.unitset.type..'_'..tostring(conditionParams.unitset.value)
       if(groupToCheck[index]==nil)then
         EchoDebug("warning. This index gave nothing : "..index)
       end
       groupToReturn=groupToCheck[index]
     end
  end
  return groupToReturn
end

-------------------------------------
-- Create unit according informations stored in a table
-- Also add unit in group tables (team, type) 
-------------------------------------
local function createUnit(unitTable)
  local posit=unitTable.position
  local externalId=unitTable.id
  local springId=Spring.CreateUnit(unitTable.type, posit.x, posit.y,posit.z, "n", unitTable.team)
  local reduction=(unitTable.hp/100) 
  registerUnit(springId,externalId,reduction,unitTable.autoHeal)
  --Spring.Echo("try to create unit with these informations")
  Spring.SetUnitRotation(springId,0,-1*unitTable.orientation,0)
  local teamIndex="team_"..tostring(unitTable.team)
  addUnitToGroups(externalId,{teamIndex}) 
end

-------------------------------------
-- Indicate if the action is groupable, which means that
-- it can be applied to a group of units
-- add information in the action to facilitate manipulations of this action
-- return a boolean indicating if it's groupable
-------------------------------------
local function isAGroupableTypeOfAction(a)
 local groupable=(a.params.unitset~=nil)
  return a,groupable
end

-------------------------------------
-- Apply a groupable action on a single unit
-------------------------------------
local function ApplyGroupableAction_onSpUnit(unit,act)
  if(Spring.ValidUnitID(unit))then -- check if the unit is still on board
    --Spring.Echo("valid")
    if(act.type=="transfer") then
      --Spring.Echo("try to apply transfert")
      Spring.TransferUnit(unit,act.params.team)
      addUnitToGroups(ctx.armyExternal[unit],{"team_"..tostring(act.params.team)}) 
    elseif(act.type=="kill")then
      Spring.DestroyUnit(unit)
    elseif(act.type=="hp")then
      local health,maxhealth=Spring.GetUnitHealth(unit)
      Spring.SetUnitHealth(unit,maxhealth*tonumber(act.params.percentage)/100)
    elseif(act.type=="teleport")then
      local posFound=extractPosition(act.params.position)
      Spring.SetUnitPosition(unit,posFound.x,posFound.z)
      Spring.GiveOrderToUnit(unit,CMD.STOP, {unit}, {}) -- avoid the unit getting back at its original position 
    elseif(act.type=="addToGroup")then
      addUnitToGroups(ctx.armyExternal[unit],{"group_"..act.params.group},false) 
    elseif(act.type=="removeFromGroup")then
      removeUnitFromGroups(ctx.armyExternal[unit],{"group_"..act.params.group},false) 
    elseif(act.type=="order")then
      Spring.GiveOrderToUnit(unit, act.params.command, act.params.parameters, {})
    elseif(act.type=="orderPosition")then
      local posFound=extractPosition(act.params.position)
      EchoDebug("orderPosition (posFound,unit,command) : "..json.encode({posFound,unit,act.params.command}),5)
      Spring.GiveOrderToUnit(unit, act.params.command,{posFound.x,Spring.GetGroundHeight(posFound.x, posFound.z),posFound.z}, {})
    elseif(act.type=="orderTarget")then
      local u=act.params.target
      local spUnit=ctx.armySpring[u]
      --Spring.GiveOrderToUnit(unit, act.params.command,{spUnit}, {})
      --Spring.GiveOrderToUnit(unit, CMD.FIRE_STATE, {0}, {})
      Spring.GiveOrderToUnit(unit,act.params.command, {spUnit}, {})   
   elseif (act.type=="messageUnit")or(act.type=="bubbleUnit") then
      if Spring.ValidUnitID(unit) then
        EchoDebug("try to send : DisplayMessageAboveUnit on "..tostring(unit))
        SendToUnsynced("DisplayMessageAboveUnit", json.encode({message=getAMessage(act.params.message),unit=unit,time=act.params.time/ctx.speedFactor,bubble=(act.type=="bubbleUnit")}))
        --[[
        local x,y,z=Spring.GetUnitePosition(springUnitId)
        Spring.MarkerAddPoint(x,y,z, getAMessage(act.params.message))
        local deletePositionAction={id=99,type="erasemarker",params={x=x,y=y,z=z},name="deleteMessageAfterTimeOut"} --to erase message after timeout
        AddActionInStack(deletePositionAction, secondesToFrames(act.params.time))--]]
      end
    end

    --Spring.GiveOrderToUnit(unit, CMD.ATTACK, {attacked}, {}) 
  end
end

-------------------------------------
-- Create an unit at a certain position
-- As side effects, the unit is added to various groups
-- One special group is also used in order to identify all the units
-- created by an action 
-------------------------------------
local function createUnitAtPosition(act,position)
  local y=Spring.GetGroundHeight(position.x,position.z)
  local springId= Spring.CreateUnit(act.params.unitType, position.x,y,position.z, "n",act.params.team)
  local externalId=act.name.."_"..tostring(ctx.globalIndexOfCreatedUnits)
  -- in order to keep to track of all created units
  ctx.globalIndexOfCreatedUnits=ctx.globalIndexOfCreatedUnits+1 
  local gpIndex="action_"..act.id
  ctx.groupOfUnits[gpIndex]={} -- Implementation choice : only the last unit action-created is stored in the action-group, hence the deletion.
  local teamIndex="team_"..tostring(act.params.team)
  registerUnit(springId,externalId)
  addUnitToGroups(externalId,{gpIndex,teamIndex}) 

    --<set Heal and underAttack>
end

-------------------------------------
-- Apply a groupable action, generally not related to an unit
-------------------------------------
local function ApplyNonGroupableAction(act)
  if(act.type=="cameraAuto") then
    if(act.params.toggle=="enabled")then
      _G.cameraAuto = {
        enable = true,
        specialPositions = {} --TODO: minimap and special position g�ree dans les zones
      }
      SendToUnsynced("enableCameraAuto")
      _G.cameraAuto = nil
    else
      _G.cameraAuto = {
        enable = false,
        specialPositions = {} 
      }
      SendToUnsynced("disableCameraAuto")
      _G.cameraAuto = nil  
    end

  elseif(act.type=="mouse") then
    if(act.params.toggle=="enabled")then
      SendToUnsynced("mouseEnabled", true)
    else
      SendToUnsynced("mouseDisabled", true) 
    end
    
  elseif(act.type=="centerCamera") then
    local posFound=extractPosition(act.params.position)
    SendToUnsynced("centerCamera", json.encode(posFound))
   
  -- MESSAGES
  
  elseif(act.type=="messageGlobal") then
    Script.LuaRules.showMessage(getAMessage(act.params.message), false, 500)

  elseif(act.type=="messagePosition") then
    --Spring.Echo("try to send : DisplayMessagePosition")
  --Script.LuaUI.DisplayMessageAtPosition(p.message, p.x, Spring.GetGroundHeight( p.x, p.z), p.z, p.time) 
    local posFound=extractPosition(act.params.position)   
    local x=posFound.x
    local y=Spring.GetGroundHeight(posFound.x,posFound.z)
    local z=posFound.z
    SendToUnsynced("displayMessageOnPosition", json.encode({message=getAMessage(act.params.message),x=x,y=y,z=z,time=act.params.time/ctx.speedFactor}))
    
    
   --[[ Spring.MarkerAddPoint(x,y,z, getAMessage(act.params.message))
    local deletePositionAction={id=99,type="erasemarker",params={x=x,y=y,z=z}} --to erase message after timeout
    AddActionInStack(deletePositionAction, secondesToFrames(act.params.time))
    --]]
     
  elseif(act.type=="erasemarker") then 
    Spring.MarkerErasePosition(act.params.x,act.params.y,act.params.z)
  
   -- WIN/LOSE
   
  elseif((act.type=="win")and(ctx.mission.teams[tostring(act.params.team)]["control"]=="player"))
      or((act.type=="lose")and(ctx.mission.teams[tostring(act.params.team)]["control"]=="computer"))then
    ctx.outputstate=act.params.outputState
    ctx.success=1
  -- Note : this is binary, it needs to be improved if multiplayer is enabled
  elseif((act.type=="lose")and(ctx.mission.teams[tostring(act.params.team)]["control"]=="player"))
      or((act.type=="win")and(ctx.mission.teams[tostring(act.params.team)]["control"]=="computer"))then
    ctx.outputstate=act.params.outputState
    ctx.success=-1
   
   -- VARIABLES
    
  elseif(act.type=="changeVariable")then
    ctx.variables[act.params.variable]=computeReference(act.params.number)   
  elseif(act.type=="setBooleanVariable")then
    ctx.variables[act.params.variable]=(act.params.boolean=="true")
  elseif(act.type=="createUnits") then
    for var=1,act.params.number do
      local position=getARandomPositionInZone(act.params.zone)
      createUnitAtPosition(act,position)
    end 
  elseif(act.type=="changeVariableRandom") then
    local v=math.random(act.params.min,act.params.max)
    --Spring.Echo("drawn variable")
    --Spring.Echo(v)
    ctx.variables[act.params.variable]=v   
  elseif(act.type=="script") then
    load_code(act.params.script)
 
  elseif(act.type=="enableWidget")or(act.type=="enableWidget") then
    local widgetName=act.params.widget
    local activation=(act.type=="enableWidget")
    SendToUnsynced("changeWidgetState", json.encode({widgetName=widgetName,activation=activation}))
  
  elseif (act.type == "intersection") or (act.type == "union") then
    local g1=unitSetParamsToUnitsExternal(act.params.unitset1)
    local g2=unitSetParamsToUnitsExternal(act.params.unitset2)
    local g3
    EchoDebug("act.params intersec/union -> "..json.encode(act.params),3 )
    if(act.type == "intersection")then
      g3=intersection(g1,g2)
    elseif(act.type == "union")then
      g3=union(g1,g2) -- at this point, duplicates will occur, but addUnitsToGroups for duplicates
    end
    EchoDebug("g3 -> "..json.encode(g3),3 )
    EchoDebug("before -> "..json.encode(ctx.groupOfUnits) ,3 )
    addUnitsToGroups(g3,{"group_"..tostring(act.params.group)},false)
    EchoDebug("after -> "..json.encode(ctx.groupOfUnits) ,3 )
  else
    EchoDebug("this action is not recognized : "..act.type,8)  
  end
end

-------------------------------------
-- The more general function to apply an action
-- according to its type (groupable or not) will be applied within another function
-- Handle group of units
-------------------------------------
function ApplyAction (a)
  
  EchoDebug("we try to apply action :"..tostring(a.name),7)
  EchoDebug(json.encode(a),7)
  local a, groupable=isAGroupableTypeOfAction(a)
  --if(groupable)then
  if(groupable) then
    --extract units
    if(a.params.unit~=nil)then
      local u=ctx.armySpring[a.params.unit]
      ApplyGroupableAction_onSpUnit(u,a)
    else   
      --local tl={[1]={"currentTeam","team"},[2]={"team","team"},[3]={"unitType","type"},[4]={"group","group"}}
      local listOfUnits=extractListOfUnitsImpliedByCondition(a.params)
      --Spring.Echo("we try to apply the groupable action to this group")
      EchoDebug("Units selected : "..json.encode(listOfUnits),7)
      if(a.type=="transfer")then
        --Spring.Echo("about to transfer")
        --Spring.Echo(json.encode(listOfUnits))
      end
      
      if(listOfUnits~=nil)then
        for i, externalUnitId in ipairs(listOfUnits) do
          local unit=ctx.armySpring[externalUnitId]
          ApplyGroupableAction_onSpUnit(unit,a)
          --
        end
      else
        --Spring.Echo("no units available for this action")
      end
    end
  else
    ApplyNonGroupableAction(a)
  end   
end

-------------------------------------
-- Printing the stack of actions planned in time
-- For debugging purpose
-------------------------------------
local function printMyStack()
  for i,el in pairs(ctx.actionStack) do
    --Spring.Echo("action "..el.actId.." is planned with delay : "..el.delay)
  end
end 

-------------------------------------
-- Check if an action is already in the stack of actions
-------------------------------------
local function alreadyInStack(actId)
  for index,el in pairs(ctx.actionStack) do
    if(el.actId==actId)then
      return true
    end
  end
  return false
end 

-------------------------------------
-- actions refer to unitsets which are subject to change over time 
-- conditions, actions, and groups 
-------------------------------------
function replaceDynamicUnitSet(action)
  local action2=deepcopy(action)
  if(action.params.unitset~=nil)and(action.params.type~="action")then
    -- we exclude action from this early extraction because the group do not exist when event is executed
    action2.params["units_extracted"]=extractListOfUnitsImpliedByCondition(action.params)
  end
  return action2
end

-------------------------------------
-- Add an action to the stack, in a sorted manner
-- The action is insert according its delay
-- At the beginning of table if the quickest action to be applied
-- At the end if the action with the biggest delay
-------------------------------------
function AddActionInStack(action, delayFrame)
  local element={}
  element["delay"]=delayFrame
  element["action"]=replaceDynamicUnitSet(action)
  --Spring.Echo(actId.." is added with delay : "..delay)
  for index,el in pairs(ctx.actionStack) do
    local del=el.delay
    local act=el.actId
    if(del>delayFrame) then
      table.insert(ctx.actionStack,index,element)
      return
    end
  end
  table.insert(ctx.actionStack,element)
end 

-------------------------------------
-- Update the stack by considering the time elapsed (in frames)
-- Actions get closer to be applied when time passes
-------------------------------------
local function updateStack(timeLapse)
  local updatedStack={}
  for index,el in pairs(ctx.actionStack) do
    el.delay=el.delay-timeLapse -- updating the delay
    table.insert(updatedStack,el)
  end
  return updatedStack
end 

-------------------------------------
-- All the actions with a negative delay will be applied
-- and removed from the stack
-------------------------------------
local function applyCurrentActions()
  for index,el in pairs(ctx.actionStack) do
    if(el.delay<0)then
      ApplyAction(el.action, nil)
      table.remove(ctx.actionStack,index)
    end
  end
end 

-------------------------------------
-- Units heal by themselves, which can be problematic
-- We let an option to override this principle
-- This function allows to cancel auto heal
-- for the units concerned by this option
-------------------------------------
local function watchHeal(frameNumber)
--attackedUnits
  -- for attacked TODO: for loop here and stuff
  EchoDebug("attacking-->"..json.encode(ctx.attackingUnits),1)
  EchoDebug("attacked-->"..json.encode(ctx.attackedUnits),1)
  for attacked,tableInfo in pairs(ctx.attackedUnits) do
    local idAttacked=ctx.armyExternal[attacked]
    if(idAttacked~=nil)and (ctx.armyInformations[idAttacked]~=nil)then
      --Spring.Echo(json.encode(tableInfo))
      if(tableInfo.frame==-1)then
        ctx.attackedUnits[attacked].frame=frameNumber
        ctx.armyInformations[idAttacked].isUnderAttack=true
        --Spring.Echo("under attack")
      elseif(frameNumber-tonumber(tableInfo.frame)<secondesToFrames(ctx.timeUntilPeace))then
        ctx.armyInformations[idAttacked].isUnderAttack=true
        --Spring.Echo("still under attack")
      else
       -- --Spring.Echo("no more under attack")
        ctx.armyInformations[idAttacked].isUnderAttack=false
      end
    end
  end
  for attacking,tableInfo in pairs(ctx.attackingUnits) do
    local idAttacking=ctx.armyExternal[attacking]
    if(idAttacking~=nil)and (ctx.armyInformations[idAttacking]~=nil)then
      --Spring.Echo(json.encode(tableInfo))
      if(tableInfo.frame==-1 or tableInfo.frame==nil)then
        EchoDebug(json.encode(ctx.attackingUnits[attacking]),2)
        ctx.attackingUnits[attacking]["frame"]=frameNumber
        ctx.armyInformations[idAttacking].isAttacking=true
        --Spring.Echo("under attack")
      elseif(frameNumber-tonumber(tableInfo.frame)<secondesToFrames(ctx.timeUntilPeace))then
        ctx.armyInformations[idAttacking].isAttacking=true
        --Spring.Echo("still under attack")
      else
       -- --Spring.Echo("no more under attack")
        ctx.armyInformations[idAttacking].isAttacking=false
      end
    end
  end
  for idUnit,infos in pairs(ctx.armyInformations) do
    local springUnit=ctx.armySpring[idUnit]
  -- ctx.armyInformations
    if(not infos.autoHealStatus)and(Spring.ValidUnitID(springUnit)) then
      --Spring.Echo("try to fix autoheal")
      --Spring.Echo(springUnit)
      local currentHealth = Spring.GetUnitHealth(springUnit)
      if currentHealth == infos.previousHealth+infos.autoHeal or currentHealth == infos.previousHealth+infos.idleAutoHeal then
        Spring.SetUnitHealth(springUnit, infos.previousHealth)
        
      else
        --if(currentHealth<infos.previousHealth)then
          --if updated too often this is not reliable (to fix)
          --infos.isUnderAttack=true
        --end
        infos.previousHealth = currentHealth
      end
    end
    ctx.armyInformations[idUnit]=infos
  end
end

-------------------------------------
--
-- If an event must be triggered, then shall be it
-- All the actions will be put in stack unless some specific options related to repetition
-- forbide to do so, such as allowMultipleInStack
-- this function as a side effect : it can create new actions (ex : to remove a message after a certain delay)
-------------------------------------
local function processEvents(frameNumber)
  local creationOfNewEvent=false
  local newevent
  for order,idEvent  in orderedPairs(ctx.orderedEventsId) do
  -- ctx.events
    local event=ctx.events[idEvent]
    if isTriggerable(event) then
      if(event.lastExecution==nil)or((event.repetition~=nil and event.repetition~=false and frameNumber>event.lastExecution+secondesToFrames(tonumber(event.repetitionTime)))) then
        -- Handle repetition
        event.lastExecution=frameNumber
        local frameDelay=0
        EchoDebug("try to apply the event with the following actions",7)
        EchoDebug(json.encode(event.actions),7)          
        for j=1,table.getn(event.actions) do
          frameDelay=frameDelay+1
          local a=event.actions[j]
          if(a.type=="wait")then
            frameDelay=frameDelay+secondesToFrames(a.params.time) 
          elseif(a.type=="waitCondition") or(a.type=="waitTrigger")then
            creationOfNewEvent=true
            newevent=deepcopy(event)
            newevent["actions"]={}
            newevent.hasTakenPlace=false
            newevent.lastExecution=nil
            newevent.conditions={}
            newevent.id=tostring(frameNumber)
            if(a.type=="waitCondition") then
              newevent.listOfInvolvedConditions={}
              table.insert(newevent.listOfInvolvedConditions,a.params.condition)   
              newevent.conditions[a.params.condition.."_"..tostring(newevent.id)]=ctx.conditions[a.params.condition.."_"..tostring(event.id)]
            end
            if(a.type=="waitTrigger")then 
              newevent.trigger=a.params.trigger 
              --Spring.Echo("update ctx Conditions")
              for c,cond in pairs(newevent.listOfInvolvedConditions) do
                ctx.conditions[cond.."_"..tostring(newevent.id)]=deepcopy(ctx.conditions[cond.."_"..tostring(event.id)])
                newevent.conditions[cond.."_"..tostring(newevent.id)]=ctx.conditions[cond.."_"..tostring(newevent.id)]
              end
            end                     
          else
            if creationOfNewEvent==false then
              AddActionInStack(a,frameDelay)
              --Spring.Echo(a.name.." added to stack with delay"..tostring(frameDelay))
            else
              table.insert(newevent["actions"],a)
            end
          end
        end
        if creationOfNewEvent then
          local newEvId=tostring(frameNumber+100)
          ctx.events[newEvId]=newevent -- dirty trick to generate an unique id for this new event
          ctx.indexOfLastEvent=ctx.indexOfLastEvent+1
          ctx.orderedEventsId[ctx.indexOfLastEvent]=newEvId
        end
      end
    end
  end
end

-------------------------------------
-- update values which are available in unsync only
-- It justs request unsync code by sendMessage
-- Values are sent back to sync code (check RecvLuaMsg(msg, player))
-------------------------------------
local function  UpdateUnsyncValues(frameNumber)
  if(frameNumber%10~=0)then return end
  SendToUnsynced("requestUnsyncVals")
end

local function UpdateGroups()
  EchoDebug("before update-> "..json.encode(ctx.groupOfUnits),0)
  for g,group in pairs(ctx.groupOfUnits) do
    for u,unit in pairs(group) do
      if(not Spring.ValidUnitID(ctx.armySpring[unit]))then
        table.remove(group,u)
        EchoDebug("remove ! -> "..json.encode(u),0)
      end
    end
  end
  EchoDebug("after update-> "..json.encode(ctx.groupOfUnits),0)
end

-------------------------------------
-- wrapper for two main functions related to
-- the main operations on the game
-------------------------------------
local function  UpdateGameState(frameNumber)
  watchHeal(frameNumber)
  processEvents(frameNumber) 
end

-------------------------------------
-- Get the action of the unit
-- Actions are in a queue list available by GetCommandQueue
-------------------------------------
local function GetCurrentUnitAction(unit)
if(Spring.ValidUnitID(unit))then
    local q=Spring.GetCommandQueue(unit,1) -- 1 means the only the first action in the stack
    local action=""
    if(q~=nil)and(q[1]~=nil) then
      action=q[1].id
      -- get the string describing the action by CMD[q[1].id] if you want
    end
    return action
  else
    --Spring.Echo("GetCurrentUnitAction called with invalid unit it")
    return nil
  end
end


-------------------------------------
-- Determine if an unit satisfies a condition
-- Two modes are possible depending on the mode of comparison (at least, at most ...)
-- Return boolean
-------------------------------------
local function UpdateConditionOnUnit (externalUnitId,c)--for the moment only single unit
  local internalUnitId=ctx.armySpring[externalUnitId]
  if(c.type=="dead") then --untested yet
    --Spring.Echo("is it dead ?")
    --Spring.Echo(externalUnitId)
    local alive=Spring.ValidUnitID(internalUnitId)
    --Spring.Echo(alive)
    return not(alive)
  elseif(Spring.ValidUnitID(internalUnitId)) then  -- 
  -- recquire that the unit is alive (unless the condition type is death, cf at the end of the function
    if(c.type=="zone") then
      local i=isUnitInZone(internalUnitId,c.params.zone)
     --[[--Spring.Echo("we check an unit in a zone")
      --Spring.Echo(internalUnitId)
      --Spring.Echo(c.params.zone)
      if(i)then
        --Spring.Echo("IN DA ZONE :")
        --Spring.Echo(c.name)
      end
      if(i and c.name=="enterda")then
        --Spring.Echo("condition validated")
      end--]]
      return i  
    elseif(c.type=="underAttack")then --untested yet
      --Spring.Echo("is it working")
      --Spring.Echo(ctx.armyInformations[externalUnitId].isUnderAttack)
      if(not ctx.armyInformations[externalUnitId].isUnderAttack)then return false
      else
        EchoDebug(json.encode(c),2)
        local spUnit=ctx.armySpring[externalUnitId]
        local spAttacker=ctx.attackedUnits[spUnit].attackerID 
        local externalAttacker=ctx.armyExternal[spAttacker]
        local group=ctx.groupOfUnits[c.params.attacker.type.."_"..tostring(c.params.attacker.value)]
        EchoDebug("group of attackers ->"..json.encode(group),1)
        local is,i=isInGroup(externalAttacker,group,false)
        EchoDebug(is,2)
        return is
      end
    elseif(c.type=="attacking")then --untested yet
      return ctx.armyInformations[externalUnitId].isAttacking
    elseif(c.type=="order") then
      local action=GetCurrentUnitAction(internalUnitId)     
      return (action==c.params.command) 
    elseif(c.type=="hp") then 
      local tresholdRatio=c.params.hp.number/99.99
      local health,maxhealth=Spring.GetUnitHealth(internalUnitId)
      return compareValue_Verbal(tresholdRatio*maxhealth,maxhealth,health,c.params.hp.comparison)      
    elseif(c.type=="type") then
      return(c.params.type==UnitDefs[Spring.GetUnitDefID(internalUnitId)]["name"])
    end
  end
end

-------------------------------------
-- Update the truthfulness of a condition
-------------------------------------
local function UpdateConditionsTruthfulness (frameNumber)
  for idCond,c in pairs(ctx.conditions) do
    local object=c["object"]
    if(object=="unit")then
      EchoDebug("this should not occur anymore")
      --ctx.conditions[idCond]["currentlyValid"]=UpdateConditionOnUnit(c.params.unit,c)
    elseif(object=="other")then  
      -- Time related conditions [START]
      if(c.type=="elapsedTime") then
        local elapsedAsFrame=math.floor(secondesToFrames(c.params.number.number))
        ctx.conditions[idCond]["currentlyValid"]= compareValue_Verbal(elapsedAsFrame,nil,frameNumber,c.params.number.comparison)  
      elseif(c.type=="repeat") then
        local framePeriod=secondesToFrames(c.params.number)
        ctx.conditions[idCond]["currentlyValid"]=((frameNumber-ctx.startingFrame) % framePeriod==0)
      elseif(c.type=="start") then
        ctx.conditions[idCond]["currentlyValid"]=(frameNumber==ctx.startingFrame)--frame 5 is the new frame 0
      -- Time related conditions [END]
      -- Variable related conditions [START]
      elseif(c.type=="numberVariable") then 
        local v1=ctx.variables[c.params.variable]
        local v2=c.params.number
        --{"type":"numberVariable","name":"Condition1","id":1,"object":"other","currentlyValid":false,"params":{"number":"6","variable":"unitscreated","comparison":"<"}}
        ctx.conditions[idCond]["currentlyValid"]=compareValue_Numerical(v1,v2,c.params.comparison)   
      elseif(c.type=="variableVSvariable") then
        local v1=ctx.variables[c.params.variable1]
        local v2=ctx.variables[c.params.variable2]
        ctx.conditions[idCond]["currentlyValid"]=compareValue_Numerical(v1,v2,c.params.comparison)   
      elseif(c.type=="booleanVariable") then
        ctx.conditions[idCond]["currentlyValid"]=ctx.variables[c.params.variable] -- very simple indeed 
      elseif(c.type=="script") then
        ctx.conditions[idCond]["currentlyValid"]=load_code(c.params.script) 
        --Spring.Echo(string.format("script condition : %s",tostring(ctx.conditions[idCond]["currentlyValid"])))      
      end
      
    elseif(object=="group")then  
      --local tl={[1]={"team","team"},[2]={"unitType","type"},[3]={"group","group"}}
      
      local externalUnitList=extractListOfUnitsImpliedByCondition(c.params)
      --EchoDebug(json.encode(externalUnitList),6)
      local count=0
      local total=0
      if(externalUnitList~=nil)then
        total=table.getn(externalUnitList)
        --Spring.Echo(json.encode(externalUnitList))
        for u,unit in ipairs(externalUnitList) do
          if(UpdateConditionOnUnit(unit,c)) then
            addUnitToGroups(unit,{"condition_"..c.id}) 
            count=count+1
          end 
        end
      end
      
      --Spring.Echo(json.encode({idCond,c.params.number.number,total,count,c.params.number.comparison}))
      ctx.conditions[idCond]["currentlyValid"] = compareValue_Verbal(c.params.number.number,total,count,c.params.number.comparison)
    elseif(object=="kill")or(object=="killed")then  
      EchoDebug("Condkills->"..json.encode(c.params),2)
      EchoDebug("kills->"..json.encode(ctx.kills),2)
      local count=0
      local total=table.getn(extractListOfUnitsImpliedByCondition(c.params,ctx.groupOfUndeletedUnits))
      local killerGroupTofind
      local targetGroupTofind
      if(object=="kill")then   
        killerGroupTofind=c.params.unitset.type.."_"..tostring(c.params.unitset.value)
        targetGroupTofind=c.params.target.type.."_"..tostring(c.params.target.value)
      elseif (object=="killed") then
        killerGroupTofind=c.params.attacker.type.."_"..tostring(c.params.attacker.value)
        targetGroupTofind=c.params.unitset.type.."_"..tostring(c.params.unitset.value)     
      end 
      EchoDebug('killerGroupTofind,targetGroupTofind,ctx.kills -> '..json.encode({killerGroupTofind,targetGroupTofind,ctx.kills}))
      for killerUnit,killedUnit in pairs(ctx.kills) do
        local killerUnit_groups = getGroupsOfUnit(killerUnit, false, ctx.groupOfUndeletedUnits)--, ctx.groupOfUndeletedUnits
        EchoDebug('killerUnit_groups -> '..json.encode(killerUnit_groups))--
        local killedUnit_groups = getGroupsOfUnit(killedUnit, false, ctx.groupOfUndeletedUnits)--
        EchoDebug('killedUnit_groups -> '..json.encode(killedUnit_groups))
        for g,gpname_killer in pairs(killerUnit_groups) do
          if(gpname_killer == killerGroupTofind) then
            for g,gpname_killed in pairs(killedUnit_groups) do
              if(gpname_killed == targetGroupTofind) then
                count = count + 1     
                EchoDebug("finally !")   
                local unitToStore
                if(object=="killed") then
                  local unitToStore=killedUnit
                else
                  unitToStore=killerUnit
                end
                local unitToStore=killerUnit
                addUnitToGroups(unitToStore,{"condition_"..c.id})        
              end
            end
          end   
        end
      end
      EchoDebug("final count : "..tostring(count),0)    
      ctx.conditions[idCond]["currentlyValid"]= compareValue_Verbal(c.params.number.number,total,count,c.params.number.comparison)
    end
    EchoDebug("state of condition :",2)
    EchoDebug(idCond,2)
    EchoDebug(ctx.conditions[idCond]["currentlyValid"],2)
    EchoDebug("current group of units",2)
    EchoDebug(json.encode(ctx.groupOfUnits),2)
     EchoDebug("current group of undeleted units",2)
    EchoDebug(json.encode(ctx.groupOfUndeletedUnits),2)
  end 
end


-------------------------------------
--Write a compass on unit, useful to help the player with
--coordinates when dealing with relative positions  
-------------------------------------
local function writeCompassOnUnit(springUnitId)
    local x,y,z=Spring.GetUnitPosition(springUnitId)
    -- Add marks around unit
    -- left arrow
    Spring.MarkerAddLine(x-65, y, z, x-25, y, z)
    Spring.MarkerAddLine(x-65, y, z, x-55, y, z+10)
    Spring.MarkerAddLine(x-65, y, z, x-55, y, z-10)
    -- right arrow
    Spring.MarkerAddLine(x+65, y, z, x+25, y, z)
    Spring.MarkerAddLine(x+65, y, z, x+55, y, z+10)
    Spring.MarkerAddLine(x+65, y, z, x+55, y, z-10)
    -- top arrow
    Spring.MarkerAddLine(x, y, z-65, x, y, z-25)
    Spring.MarkerAddLine(x, y, z-65, x+10, y, z-55)
    Spring.MarkerAddLine(x, y, z-65, x-10, y, z-55)
    -- down arrow
    Spring.MarkerAddLine(x, y, z+65, x, y, z+25)
    Spring.MarkerAddLine(x, y, z+65, x+10, y, z+55)
    Spring.MarkerAddLine(x, y, z+65, x-10, y, z+55)
    -- write letters
    if lang == "fr" then
      writeLetter(x-60, y, z-25, "O")
    else
      writeLetter(x-60, y, z-25, "W")
    end
    writeLetter(x+60, y, z-25, "E")
    writeLetter(x-25, y, z-60, "N")
    writeLetter(x-25, y, z+60, "S")
    -- write signs
    writeSign(x-48, y, z+18, "-")
    writeSign(x+48, y, z+18, "+")
    writeSign(x+18, y, z-48, "-")
    writeSign(x+18, y, z+48, "+")
end

-------------------------------------
-- Parse the editor file
-- enable/deactivate widgets according to the settings
-------------------------------------
local function parseJson(jsonString)
  --Spring.Echo(jsonString)
  if(jsonString==nil) then
    return nil
  end
  ctx.canUpdate=true
  ctx.mission=json.decode(jsonString)
  -- desactivate widget
  --[[
    widgetHandler:EnableWidget("Traces Widget")
  -- enable Feedbacks Widget
  widgetHandler:EnableWidget("Feedbacks Widget")
  -- enable Widget Informer
  widgetHandler:EnableWidget("Widget Informer")
  --]]
  local widgetWithForcedState={
    ["Display Message"]=true,["Hide commands"]=true,["Messenger"]=true
    ,["Mission GUI"]=true,["campaign launcher"]=true,["CA Interface"]=true
    ,["Camera Auto"]=true,["Chili Framework"]=true,["Display Zones"]=true,["Traces Widget"]=true
    ,["Feedbacks Widget"]=true,["Widget Informer"]=true
  }
  
  for i=1, table.getn(ctx.mission.description.widgets) do
    local widgetName=ctx.mission.description.widgets[i].name
    if(widgetWithForcedState.widgetName==nil)then
      local activation=ctx.mission.description.widgets[i].active
      SendToUnsynced("changeWidgetState", json.encode({widgetName=widgetName,activation=activation}))
    end
  end
  
  -- Required widgets for Prog&Play   
  for name, activ in pairs(widgetWithForcedState) do
    SendToUnsynced("changeWidgetState", json.encode({widgetName=name,activation=activ}))
  end
  
  
  return true
end

local function returnEventsTriggered()
  local eventsTriggered={}
  for idEv,ev in pairs(ctx.events) do   
    if(ev.hasTakenPlace) then
      table.insert(eventsTriggered,idEv)
    end
  end
  return eventsTriggered
end

-------------------------------------
-- Initialize the mission by parsing informations from the json
-- and process some datas
-- @todo This function does too many things
-------------------------------------
local function StartAfterJson ()
  if ctx.mission==nil then return end
  local units = Spring.GetAllUnits()
  for i = 1,table.getn(units) do
    --Spring.Echo("I am Totally Deleting Stuff")
    Spring.DestroyUnit(units[i], false, true)
  end  
 
 local specialPositionTables={} 
 
 -------------------------------
 -------ZONES-------------------
 -------------------------------
 if(ctx.mission.zones~=nil)then   
  for i=1, table.getn(ctx.mission.zones) do
    local center_xz
     local cZ=ctx.mission.zones[i]
     local idZone=cZ.id
     if(cZ.type=="Disk") then
      center_xz={x=cZ.x, z=cZ.z}
      ctx.zones[idZone]={type="Disk",center_xz=center_xz,a=cZ.a,b=cZ.b}
     elseif(cZ.type=="Rectangle") then
      local demiLargeur=(cZ.x2-cZ.x1)/2
      local demiLongueur=(cZ.z2-cZ.z1)/2
      center_xz={x=cZ.x1+demiLargeur, z=cZ.z1+demiLongueur}
      ctx.zones[idZone]={type="Rectangle",center_xz=center_xz,demiLargeur=demiLargeur,demiLongueur=demiLongueur} 
     else
      --Spring.Echo(cZ.type.." not implemented yet")
      end
    if(cZ.alwaysInView)then
      table.insert(specialPositionTables,{center_xz.x,center_xz.z})
    end 
    if(cZ.marker)then
      Spring.MarkerAddPoint(center_xz.x,Spring.GetGroundHeight(center_xz.x,center_xz.z),center_xz.z, cZ.name)
    end 
    if cZ.showInGame then
       SendToUnsynced("displayZone", json.encode(cZ))    
    end
    --displayZone
  end
end
   
   -------------------------------
   -------VARIABLES---------------
   -------------------------------
  if(ctx.mission.variables~=nil)then
    for i=1,table.getn(ctx.mission.variables) do
      local missionVar=ctx.mission.variables[i]
      local initValue=missionVar.initValue
      local name=missionVar.name
      if(missionVar.type=="number") then
        initValue=initValue
      elseif(missionVar.type=="boolean") then
        initValue=(initValue=="true")
      end
      ctx.variables[name]=initValue
    end
  end  
  --Spring.Echo(json.encode(ctx.variables))
  
  
  
    -- specialPositionTables[i]={positions[id].x,positions[id].z}
    -- 
  
   -------------------------------
   -------SETTINGS----------------
   -------------------------------
  ctx.messages["briefing"]=ctx.mission.description.briefing
  --Spring.Echo(ctx.messages["briefing"])
  --  if(mission.description.mouse=="disabled") then
  --   SendToUnsynced("mouseDisabled", true)
  --  end
  
  if(ctx.mission.description.cameraAuto=="enabled") then
    _G.cameraAuto = {
      enable = true,
      specialPositions = specialPositionTables --TODO: minimap and special position g�ree dans les zones
    }
    SendToUnsynced("enableCameraAuto")
    _G.cameraAuto = nil
  end
  local isautoHealGlobal=(ctx.mission.description.autoHeal=="enabled")
  
  if(ctx.mission.description.minimap and ctx.mission.description.minimap=="disabled") then
    Spring.SendCommands("minimap min")
  end
 -------------------------------
 ----------ARMIES---------------
 -------------------------------
  local isAutoHeal
  if(ctx.mission.units~=nil)then
    for i=1,table.getn(ctx.mission.units) do
      local armyTable=ctx.mission.units[i]
      if(armyTable.autoHeal=="global") then
        isAutoHeal=isautoHealGlobal
      else
        isAutoHeal=(armyTable.autoHeal=="enabled")
      end
        armyTable["autoHeal"]=isAutoHeal
        createUnit(armyTable)
    end
  end
 
  ShowBriefing()
   

 -------------------------------
 ------GROUP OF ARMIES----------
 -------------------------------
  if(ctx.mission["groups"]~=nil) then
    for i=1, table.getn(ctx.mission.groups) do
      local groupId=ctx.mission.groups[i].id
      local groupIndex="group_"..groupId
      ctx.groupOfUnits[groupIndex]={}
      ctx.groupOfUndeletedUnits[groupIndex]={}
      addUnitsToGroups(ctx.mission.groups[i].units,{groupIndex},true)
    end
  end 
   


   ---------------------------------------------
   -------EVENTS  AND  CONDITIONS--------------
   ---------------------------------------------
  if(ctx.mission.events~=nil)then
      for i,currentEvent in ipairs(ctx.mission.events) do
       local idEvent=currentEvent.id
       ctx.orderedEventsId[i]=idEvent
       ctx.events[idEvent]={}
       ctx.events[idEvent]=ctx.mission.events[i]
       ctx.events[idEvent].hasTakenPlace=false
       ctx.events[idEvent].listOfInvolvedConditions={}
       for j=1, table.getn(currentEvent.conditions)do
         local currentCond=currentEvent.conditions[j]
         local id=currentCond.name
         table.insert(ctx.events[idEvent].listOfInvolvedConditions,id)
         ctx.conditions[id.."_"..tostring(ctx.events[idEvent].id)]=currentEvent.conditions[j]
         ctx.conditions[id.."_"..tostring(ctx.events[idEvent].id)]["currentlyValid"]=false
         local type=currentCond.type
         local cond_object="other"
         if(currentCond.type=="killed")or(currentCond.type=="kill")then
          cond_object=currentCond.type -- special case as related units are no more
         elseif(currentCond.params.unitset~=nil)then
          cond_object="group"
         end
        ctx.conditions[id.."_"..tostring(ctx.events[idEvent].id)]["object"]=cond_object
       EchoDebug(json.encode(ctx.conditions))
      end 
      ctx.indexOfLastEvent=i
    end
  end     
end


-- shorthand for parseJson + StartAfterJson.
local function Start(jsonString) 
  EchoDebug("missionFile : "..jsonString,2)
  parseJson(jsonString)
  StartAfterJson()
end

-------------------------------------
-- The main function of Mission Player
-- Update the game state of the mission 
-- Called externally by the gadget mission_runner.lua 
-- @return success (0,1 or -1) for (nothing, success, fail) and outputstate (appliq related)
-------------------------------------
local function Update (frameNumber)
  if ctx.mission==nil then return 0 end
  UpdateConditionsTruthfulness(frameNumber) 
  UpdateGameState(frameNumber)
  ctx.actionStack=updateStack(1)--update the stack with one frame (all the delays are decremented)
  applyCurrentActions() 
  if(frameNumber>32)then ctx.recordCreatedUnits=true end   -- in order to avoid to record units that are created at the start of the game
  UpdateUnsyncValues(frameNumber)
  UpdateGroups()
  if(ctx.success==1) then
    return ctx.success,ctx.outputstate
  elseif(ctx.success==-1) then
    return ctx.success,ctx.outputstate
  else
    return 0 -- means continue
  end
  -- Trigger Events
end  
  
-------------------------------------
-- Called by mission_runner at the end of the mission
-------------------------------------
local function Stop ()
  -- delete all units created
  local units = Spring.GetAllUnits() 
  for i = 1,table.getn(units) do
    Spring.DestroyUnit(units[i], false, true)
  end
end


local function isMessage(msg,target_msg)
  local lengthTarget=string.len(target_msg)
  return ((msg~=nil)and(string.len(msg)>lengthTarget)and(string.sub(msg,1,lengthTarget)==target_msg))
end

-------------------------------------
-- Information received from Unsynced Code 
-- Executed in mission_runner.lua
-------------------------------------
local function RecvLuaMsg(msg, player)
  Spring.Echo("")
  if isMessage(msg,"kill") then
    local jsonString=string.sub(msg,5,-1)
    EchoDebug("killTable-->"..jsonString,3)
    local killTable=json.decode(jsonString)
    local killer=killTable.attackerID
    local killerExternal=ctx.armyExternal[killer]
    local killedExternal=ctx.armyExternal[killTable.unitID]
    ctx.kills[killerExternal]=killedExternal
    
  elseif isMessage(msg,"damage") then
    local jsonString=string.sub(msg,7,-1)
    local damageTable=json.decode(jsonString)
    EchoDebug("damageTable-->"..json.encode(damageTable),1)
    local attackedUnit=damageTable.attackedUnit
    local attackingUnit=damageTable.attackerID
    damageTable.frame=tonumber(damageTable.frame)    
    if ctx.attackedUnits[attackedUnit]==nil then
      ctx.attackedUnits[attackedUnit]={} 
    end
    ctx.attackedUnits[attackedUnit]=damageTable
    if(attackingUnit~=nil)then
      if ctx.attackingUnits[attackingUnit]==nil then
        ctx.attackingUnits[attackingUnit]={} 
      end
      ctx.attackingUnits[attackingUnit]=damageTable
    end
    
  elseif isMessage(msg,"unitCreation") then
    if(ctx.recordCreatedUnits)then -- this avoid to store starting bases in the tables
      local jsonString=string.sub(msg,13,-1)
      local creationTable=json.decode(jsonString)
      local realId="createdUnit_"..tostring(ctx.globalIndexOfCreatedUnits)
      ctx.globalIndexOfCreatedUnits=ctx.globalIndexOfCreatedUnits+1
      local springId=creationTable.unitID 
      
      -- < Register>
      local teamIndex="team_"..tostring(creationTable.unitTeam)
      registerUnit(springId,realId)
      addUnitToGroups(realId,{teamIndex},false)
      -- </ Register> 
    end 
  elseif isMessage(msg,"returnUnsyncVals") then
    local jsonString=string.sub(msg,17,-1)
    local values=json.decode(jsonString)
    for ind,val in pairs(values)do
      ctx[ind]=val
    end
  end
end



missionScript = {}

missionScript.returnEventsTriggered=returnEventsTriggered
missionScript.parseJson=parseJson
missionScript.StartAfterJson=StartAfterJson
missionScript.Start = Start
missionScript.ShowBriefing = ShowBriefing
missionScript.Update = Update
missionScript.Stop = Stop
missionScript.ApplyAction = ApplyAction
missionScript.RecvLuaMsg = RecvLuaMsg

ctx.load_code=load_code ; ctx.intersection=intersection ; ctx.compareValue_Verbal=compareValue_Verbal ; ctx.compareValue_Numerical=compareValue_Numerical ; ctx.makeOperation=makeOperation ; ctx.deepcopy=deepcopy ; ctx.secondesToFrames=secondesToFrames ; ctx.getFactionCode=getFactionCode ; ctx.boolAsString=boolAsString ; ctx.getAMessage=getAMessage ; ctx.isXZInsideZone=isXZInsideZone ; ctx.isUnitInZone=isUnitInZone ; ctx.getARandomPositionInZone=getARandomPositionInZone ; ctx.extractPosition=extractPosition ; ctx.writeLetter=writeLetter ; ctx.writeSign=writeSign ; ctx.showMessage=showMessage ; ctx.ShowBriefing=ShowBriefing ; ctx.isTriggerable=isTriggerable ; ctx.extractListOfUnitsImpliedByCondition=extractListOfUnitsImpliedByCondition ; ctx.createUnit=createUnit ; ctx.isAGroupableTypeOfAction=isAGroupableTypeOfAction ; ctx.ApplyGroupableAction_onSpUnit=ApplyGroupableAction_onSpUnit ; ctx.createUnitAtPosition=createUnitAtPosition ; ctx.ApplyNonGroupableAction=ApplyNonGroupableAction ; ctx.ApplyAction=ApplyAction ; ctx.printMyStack=printMyStack ; ctx.alreadyInStack=alreadyInStack ; ctx.AddActionInStack=AddActionInStack ; ctx.updateStack=updateStack ; ctx.applyCurrentActions=applyCurrentActions ; ctx.watchHeal=watchHeal ; ctx.processEvents=processEvents ; ctx.GetCurrentUnitAction=GetCurrentUnitAction ; ctx.UpdateConditionOnUnit=UpdateConditionOnUnit ; ctx.UpdateConditionsTruthfulness=UpdateConditionsTruthfulness ; ctx.writeCompassOnUnit=writeCompassOnUnit ; ctx.parseJson=parseJson ; ctx.returnEventsTriggered=returnEventsTriggered ; ctx.returnTestsToPlay=returnTestsToPlay ; ctx.StartAfterJson=StartAfterJson ; ctx.Start=Start ; ctx.Update=Update ; ctx.Stop=Stop ; ctx.SendToUnsynced=SendToUnsynced
ctx.Spring=Spring 


