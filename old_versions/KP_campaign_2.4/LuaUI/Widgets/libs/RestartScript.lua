local json=VFS.Include("LuaUI/Widgets/libs/LuaJSON/dkjson.lua")
local reloadAvailable=(tonumber(Game.version)~=nil and tonumber(Game.version)>=99) -- nil test is made because prior to v92 Game.Version is an ugly string (e.g 0.82)
local gameName=Game.gameShortName or Game.modShortName

local function saveTxt(txt)
  Spring.Echo(gameName)
  if(not VFS.FileExists("Savegames/"..gameName.."/"))then
    Spring.CreateDir("Savegames/"..gameName.."/")
  end
  local file=io.open("Savegames/"..gameName.."/currentSave.sav","wb")
  file:write(txt)
  file:flush()
  file:close()
end
--- 

function DoTheRestart(startscriptfilename, tableOperation)
  -- Warning : tableOperation must not include keys which are a substring of another key in the txt file
  -- for exemple, as it happened, using a key such as mode when gamemode already exists.
  -- One idea would be to fix how regex are made in the function replace section.
	local n_infologcopy="infolog.bak.txt"
	Spring.Echo("test")
	Spring.Echo(widget:GetInfo().name..": Wanting to reload \""..startscriptfilename.."\"")
	if VFS.FileExists(startscriptfilename) then
		local complete=VFS.LoadFile(startscriptfilename)
    complete=updateValues(complete, tableOperation)
		Spring.Echo("\n\n<<BEGIN DUMPING FULL \""..startscriptfilename.."\">>\n\n")
		Spring.Echo(complete)
		Spring.Echo("\n\n<<END DUMPING FULL \""..startscriptfilename.."\">>\n\n")
		local trimmed=complete
		trimmed,_=string.gsub(trimmed,"//[^\r\n]-[\r\n]+","\n")-- Remove // comments
		trimmed,_=string.gsub(trimmed,"/%*.-%*/","")-- Remove /* comments */
		Spring.Echo("\n\n<<BEGIN DUMPING TRIMMED>>\n\n")
		Spring.Echo(trimmed)
		Spring.Echo("\n\n<<END DUMPING TRIMMED>>\n\n")
		params = "-s"
		if tonumber(Spring.GetConfigInt("safemode"))==1 then
			params = "--safemode "..params
		end
		Spring.Echo(widget:GetInfo().name..": Ok, calling Spring.Restart(\""..params.."\",\"[GAME]{..}\") now!")
		Spring.Echo("Making infolog.txt copy into "..n_infologcopy)
		local file=io.open(n_infologcopy,"wb")
		file:write(VFS.LoadFile("infolog.txt"))
		file:flush()
		file:close()
		saveTxt(trimmed)
		Spring.Restart(params,trimmed)
		Spring.Echo(widget:GetInfo().name..": Just called Spring.Restart(\""..params.."\",\"[GAME]{..}\")")
		Spring.Echo(widget:GetInfo().name..": Wait, we shouldn't be here, should have restarted or crashed or quitted by now.")
	else
		Spring.Echo(widget:GetInfo().name..": that file is not valid... Restart aborted")
	end
end

function replaceSection(fullfile,sectionName,replacement)
    local regexSection="%["..sectionName.."%]%s*%{([^%}]*)%}"
    local regexBracket="%}"
    local indexSection=string.find(fullfile,regexSection)
    local indexOfNextClosingBracked=string.find(fullfile,regexBracket,indexSection)
    local firstPart=string.sub(fullfile, 1,indexSection-1)
    local lastPart=string.sub(fullfile, indexOfNextClosingBracked+1)
    local fullstring=firstPart..replacement..lastPart
    return(fullstring)
end

function updateValues(fullFile,tableOperation)
  -- works as follow : will replace the entire sections. 
  -- For each section concerned a copy is made and replacements are done within this section
  -- If the attribute is not present then it is added at the end of the section
  for section,operations in pairs(tableOperation) do
    local regexSection="%["..section.."%]%s*%{([^%}]*)%}"
    local contentSection=string.match(fullFile,regexSection) -- contain the content of the section
    local oldSection=contentSection
    for attribute,value in pairs(operations) do
      if(string.match(contentSection,attribute.."=[^;]*;")) then
        contentSection,_=string.gsub(contentSection,attribute.."=[^;]*;",attribute.."="..value..";",1)
      else
        contentSection=contentSection.."\r\n\t\t"..attribute.."="..value..";"  -- If the attribute is not present then it is added at the end of the section
      end
    end
    contentSection="["..section.."]\r\n\t{"..contentSection.."\r\n\t}"
    fullFile=replaceSection(fullFile,section,contentSection) -- will replace the old section by the newly created section
  end
    --local fullFile=string.gsub(fullFile,"%["..section.."%]%s*%{([^%}]*)%}",contentSection) -- replace the content of the action
  return fullFile 
end

local function writeAttributes(file, levelOfIndentation, tableValues)
  for k,v in pairs(tableValues) do
    file=file.."\n"..string.rep("\t", levelOfIndentation+1)..k.."="..v..";"
  end
  return file
end

local function writeAttributesAndSection(file,sectionName, levelOfIndentation, tableValues)
  file=file.."\n"..string.rep("\t", levelOfIndentation).."["..sectionName.."]"
  file=file.."\n"..string.rep("\t", levelOfIndentation).."{"
  file=writeAttributes(file, levelOfIndentation, tableValues)
  file=file.."\n"..string.rep("\t", levelOfIndentation).."}"
  return file
end

local function createFromScratch(editorTables, playerName)
  local file=""
  -- GLOBAL OPTIONS
  file=file.."[GAME]\r\n{" -- This section is special as it includes other section, can't use writeAttributesAndSection, only writeAttributes
  local mapName=editorTables.description.map or "Marble_Madness_Map" 
  local name=editorTables.description.saveName 
  local lang=editorTables.description.lang or "en" 
  local table1 = {Mapname=mapName, Gametype=Game.modName, MyPlayerName=playerName, HostIP="localhost", HostPort="8451", ishost="1",StartPosType="3"}
  file=writeAttributes(file, 0, table1)
  local table2={jsonlocation="editor" ,gamemode="3",fixedallies="0",hidemenu="1",language=lang,missionname=name,scenario="default"}
  file=writeAttributesAndSection(file,"MODOPTIONS", 1, table2)
  local indexPlayer=0
  local indexIA=0
  local nteam=0
  
  -- find max 
  local max=0
  for teamNumber,teamInformations in pairs(editorTables.teams) do
    if teamInformations.enabled and (tonumber(teamNumber)>max)then max=tonumber(teamNumber) end
  end
  
  
  for teamNumber,teamInformations in pairs(editorTables.teams) do
    local allyTeamInformation=editorTables.allyteams[teamNumber]
    -- Write first section : who controls the team (player/IA)
    if(tonumber(teamNumber)<=max)then 
      nteam=nteam+1
      if (teamInformations.control=="player" and teamInformations.enabled==true) then 
-- if a team is player controled but disabled it should not be stored as a player  
-- controled team to avoid bug "Player1 has name player which is already taken" 
        local sectionName=string.lower("PLAYER"..tostring(indexPlayer))
        local name=teamInformations.name or string.lower(sectionName)
        indexPlayer=indexPlayer+1
        local tableController={Name="Player"..tostring(indexPlayer) ,Spectator="0",Team=tostring(teamNumber)} -- "Player"..tostring(indexPlayer)
        file=writeAttributesAndSection(file,sectionName, 1, tableController)   
      else -- control==computer or disabled team. Disabled team MUST be described in the txt to avoid Spring index collapsing and mismatch with editor informations
      -- when max is attained, it's not necessary to add disabled teams anymore
        local sectionName="AI"..tostring(indexIA)
        indexIA=indexIA+1
        local name=teamInformations.name or string.lower(sectionName)
        local shortName="NullAI"
        if(teamInformations.ai~=nil and teamInformations.ai~="")then
          shortName=teamInformations.ai
        end
        
        local tableController={Name=name ,ShortName=shortName,fixedallies="0",Team=tostring(teamNumber),Host="0"} 
        file=writeAttributesAndSection(file,sectionName, 1, tableController) 
      end  
      -- Write Second section : information about the team (player/IA)
      local teamSectionName="TEAM"..tostring(teamNumber)
      local arbitraryPosition=tostring(teamNumber*200+100)
      local rGBColor=tostring(teamInformations.color.red).." "..tostring(teamInformations.color.green).." "..tostring(teamInformations.color.blue)
      --local rGBColor=tostring(teamInformations.color.red).." "..tostring(teamInformations.color.blue).." "..tostring(teamInformations.color.green)
      local tableController={TeamLeader="0" ,AllyTeam=tostring(teamNumber),RGBColor=rGBColor,Side="System",StartPosX=arbitraryPosition,StartPosZ=arbitraryPosition} 
      file=writeAttributesAndSection(file,teamSectionName, 1, tableController)
      
      -- Write Third section : information about the allyteam (1 allyteam by team)
      local allyTeamSectionName="ALLYTEAM"..tostring(teamNumber)
      local NumAllies=table.getn(allyTeamInformation)
      local tableAllyTeam={NumAllies=NumAllies}    
      for i,u in pairs(allyTeamInformation) do
        local allyKey="Ally"..tostring(i-1)
        tableAllyTeam[allyKey]=u
      end
      file=writeAttributesAndSection(file,allyTeamSectionName, 1, tableAllyTeam)  
    end   
  end
  file=file.."\n}"
  return file
end

function restartWithEditorFile(editorTables)
  local txtFileContent=createFromScratch(editorTables)
  Spring.Echo(txtFileContent)--comment the next lines to see this output
  if(reloadAvailable) then
    Spring.Reload(txtFileContent) --(this line, yes)
  else
    Spring.Restart("-s",txtFileContent)--( and this line too)
  end
end

local function open_and_decode(missionName)
   local sf=VFS.LoadFile(missionName)
   Spring.Echo("try to decode")
   Spring.Echo(missionName)
   return json.decode(sf)
end

function number_of_player_editor_file(missionName,operations,contextFile)
  local tableEditor = open_and_decode(missionName)
  local count =  0
  for teamNumber,teamInformations in pairs(tableEditor.teams) do
      if (teamInformations.control=="player" and teamInformations.enabled==true) then 
        count = count + 1
      end
   end
   return count
end

local function generateTxt_and_restart(missionName, operations, reload, playerName)
   local tableEditor=open_and_decode(missionName)
   Spring.Echo("decoded with success")
   local txtFileContent=createFromScratch(tableEditor, playerName)
   local updatedTxtFileContent=updateValues(txtFileContent, operations)
   saveTxt(updatedTxtFileContent)
   if(reload) then
      Spring.Reload(updatedTxtFileContent) --(this line, yes)
   else
      Spring.Restart("-s",updatedTxtFileContent)--( and this line too)
   end
end


function number_of_player(missionName,contextFile)
-- Warning : no retro compatibility with old txt files
-- they can still be run, but are 1 player by default (return false statements below)
   local path = ""
   if(not contextFile)then -- meaning that context is : In-game => we have access to modoptions
     if Spring.GetModOptions()["jsonlocation"]~=nil and Spring.GetModOptions()["jsonlocation"]=="editor" then
        path = "Missions/"..missionName..".editor"-- because we are in the context : Ingame
     else
        return false  
     end
   else -- meaning Not in game, we just have access to the file name
    if (string.sub(missionName, -3, -1)=="txt")then      
      return false 
    elseif (string.sub(missionName, -6, -1)=="editor")then
      path = missionName
    else
      Spring.Echo("Warning, pbm in restart script")
    end   
  end
  return number_of_player_editor_file(path)
end 
-- restart can be used for .editor files or .txt files giving some (or none) updating operation
-- a bit of copy pasta in this function, could be refractored easily
function genericRestart(missionName,operations,contextFile, playerName)
  playerName = playerName or "Player1"
   if(not contextFile)then -- meaning that context is : In-game => we have access to modoptions
     if Spring.GetModOptions()["jsonlocation"]~=nil and Spring.GetModOptions()["jsonlocation"]=="editor" then
        local path = "Missions/"..missionName..".editor"-- because we are in the context : Ingame
        generateTxt_and_restart(missionName, operations, false, playerName)
     else
        DoTheRestart("Missions/"..missionName.."txt", operations)  
     end
   else -- meaning Not in game, we just have access to the file name
    if (string.sub(missionName, -3, -1)=="txt")then      
      DoTheRestart(missionName, operations)  
    elseif (string.sub(missionName, -6, -1)=="editor")then
      generateTxt_and_restart(missionName, operations, reloadAvailable, playerName)
    else
      Spring.Echo("Warning, pbm in restart script")
    end   
  end
end   


function restartToConnect(playerName,IP)
  local table2={HostIP=IP ,Hostport="8451",ishost="0",MyPlayerName=playerName}
  local file=writeAttributesAndSection("","GAME", 0, table2)
  Spring.Restart("-s",file)--(this line, yes)
end 
      
