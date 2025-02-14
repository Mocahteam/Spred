function widget:GetInfo()
  return {
    name      = "PP Meta Traces Manager",
    desc      = "Used to deal with traces",
    author    = "meresse, muratet, mocahteam",
    date      = "Feb 25, 2016",
    license   = "GPL v2 or later",
    layer     = 211,
    enabled   = true --  loaded by default?
  }
end

local missionName = Spring.GetModOptions()["missionname"]
local tracesDirname = "traces"
local ppTraces = nil -- File handler to store traces

function TraceAction(msg)
	if ppTraces ~= nil then
		local actor = WG.StudentId -- defined in ask_studentID Widget
		if actor == nil then
			actor = "Anonymous"
		end
		ppTraces:write("TIME_STAMP\t"..os.date().."\tUSER_ID\t"..actor.."\tTRACE_CONTENT\t"..msg.."\n")
		ppTraces:flush()
	end
end

function MissionEnded(victoryState)
	TraceAction("end_mission\t"..victoryState.."\t"..missionName)
end

function widget:RecvLuaMsg(msg, player)
  if player == Spring.GetMyPlayerID() then
	if((msg~=nil)and(string.len(msg)>16)and(string.sub(msg,1,16)=="CompressedTraces")) then -- received from game engine (ProgAndPlay.cpp)
		local content=string.sub(msg,18,-1) -- we start at 18 due to an underscore used as a separator
		content = string.gsub(content, "\n", " ") -- remove \n
		content = string.gsub(content, "\t", " ") -- remove \t
		content = string.gsub(content, "%s+", " ") -- remove multiple spaces
		TraceAction("compressed_trace\t"..content)
	end
  end
end

function widget:Initialize()
	widgetHandler:RegisterGlobal("MissionEnded", MissionEnded)
	widgetHandler:RegisterGlobal("TraceAction", TraceAction)
	
	if missionName ~= nil then
		if not VFS.FileExists(tracesDirname) then
			Spring.CreateDir(tracesDirname)
		end
		ppTraces = io.open(tracesDirname..'\\'.."meta.log", "a+")
	end
end

function widget:GameStart()
	TraceAction("start_mission\t"..missionName.."\twithTeam\t"..Spring.GetMyTeamID())
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal("MissionEnded", MissionEnded)
	widgetHandler:DeregisterGlobal("TraceAction", TraceAction)
	
	if ppTraces ~= nil then
		ppTraces:close()
	end
end
