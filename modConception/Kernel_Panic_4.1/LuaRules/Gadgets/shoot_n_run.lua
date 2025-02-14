
function gadget:GetInfo()
	return {
		name = "Shoot'n'Run",
		desc = "Turn RTS to HnS/SnR",
		author = "zwzsg",
		date = "10th of November 2009",
		license = "Public Domain",
		layer = 120,
		enabled = true
	}
end

local megabit = UnitDefNames.megabit.id
local megabug = UnitDefNames.megabug.id
local megabugold = UnitDefNames.megabugold.id
local megapacket = UnitDefNames.megapacket.id
local megavirus = UnitDefNames.megavirus.id
local megaexploit = UnitDefNames.megaexploit.id
local megafairy = UnitDefNames.megafairy.id
local hero={megabit,megabug,megabugold,megapacket,megavirus,megaexploit,megafairy}
local isHero= {
	[megabit]=true,
	[megabug]=true,
	[megabugold]=true,
	[megavirus]=true,
	[megaexploit]=true,
	[megapacket]=true,
	[megafairy]=true,
}

local AllowOtherUnitsControl=true
if Spring.GetModOptions()["homf"]=="1" and Spring.GetModOptions()["homf_rightclick"]=="0" then
	AllowOtherUnitsControl=false
end

if (gadgetHandler:IsSyncedCode()) then
--SYNCED

	local IsIt82=nil
	local LastHeroesCheck=0
	local ptu={}-- Player to Unit
	local utp={}-- Unit to Player
	local usd={}-- Unit Self Destruct engaged so discard subsequent self-d orders as they would cancel it
	local ptf={}-- Player to frame he was last given a hero
	local RecMsg={}-- To bufferize Received Messages bewteen each call to GameFrame
	local ScoreBoard={}

	local weirdSelection={}

	function gadget:Initialize()
		IsIt82=true
		for v=70,81 do
			if string.match(Game.version,tostring(v)) then
				IsIt82=false
			end
		end
	end

	--function gadget:GameStart()
	--end


	-- Return the list of active, non spectator, players of a team
	-- If second argument is zero, then only return those with no hero, sorted by order of last respawn (oldest first)
	local function GetBetterPlayerList(team,ZeroForHeroLessPlayers)
		PlayerList={}
		for _,p in ipairs(Spring.GetPlayerList(team,true)) do
			local _,active,spectator=Spring.GetPlayerInfo(p)
			if active and not spectator then
				if ZeroForHeroLessPlayers==0 then
					if not ptu[p] then
						local inserted=false
						for i,q in pairs(PlayerList) do
							if (ptf[p] or 0)<(ptf[q] or 0) then
								table.insert(PlayerList,i,p)
								inserted=true
								break
							end
						end
						if not inserted then
							table.insert(PlayerList,p)
						end
					end
				else
					table.insert(PlayerList,p)
				end
			end
		end
		return PlayerList
	end


	local function GiveHero(u,team)
		local team=team or Spring.GetUnitTeam(u)
		local PlayerList=GetBetterPlayerList(team,0)
		if #PlayerList>=1 then
			local p=PlayerList[1]
			ptf[p]=Spring.GetGameFrame()
			ptu[p]=u
			utp[u]=p
			Spring.SendMessage("<PLAYER"..p.."> got "..UnitDefs[Spring.GetUnitDefID(u)].humanName.."!")
			Spring.SetUnitCOBValue(u,3,0)-- 3 is STANDINGFIREORDERS
			--local nmh=10*UnitDefs[ud].health
			--Spring.SetUnitMaxHealth(u,nmh)
			--Spring.SetUnitHealth(u,nmh)
			if not ScoreBoard[p] then
				ScoreBoard[p]={}
			end
		end
	end


	function gadget:GameFrame(frame)

		-- Age half the hackers
		if frame==3 then
			if Spring.GetModOptions()["homf"] and Spring.GetModOptions()["homf"]~="0" then
				for _,t in ipairs(Spring.GetTeamList()) do
					local _,_,_,_,_,_,CustomTeamOptions=Spring.GetTeamInfo(t)
					if math.random(1,2)==2 and (not ((tonumber(Spring.GetModOptions()["removeunits"]) or 0)~=0))
						and (not ((tonumber(CustomTeamOptions["removeunits"]) or 0)~=0)) then
						for _,u in ipairs(Spring.GetTeamUnitsByDefs(t,UnitDefNames.hole.id)) do
							table.insert(weirdSelection,u)
						end
					end
				end
			end
			Spring.GiveOrderToUnitArray(weirdSelection,CMD.MOVE_STATE,{2},{})
		elseif frame==4 then
			Spring.GiveOrderToUnitArray(weirdSelection,CMD.MOVE_STATE,{0},{})
		elseif frame==5 then
			Spring.GiveOrderToUnitArray(weirdSelection,CMD.MOVE_STATE,{1},{})
		end

		if IsIt82 and frame%2~=1 then
			return
		end

		-- Make unsynced run that function once per frame
		SendToUnsynced("Shoot_n_Run_Unsynced_GameFrame",frame)
		-- Share the table telling which unit are controllled
		_G.Shoot_n_Run={utp=utp,ptu=ptu,ScoreBoard=ScoreBoard}

		-- Parse the messages from unsynced
		for _,msg in pairs(RecMsg) do
			local u=tonumber(string.match(msg,"Unit=(%d+),"))
			local dx=tonumber(string.match(msg,"MoveX=(%-?%d+),"))
			local dz=tonumber(string.match(msg,"MoveZ=(%-?%d+),"))
			local tx=tonumber(string.match(msg,"TargetX=(%-?%d+%.?%d+),"))
			local tz=tonumber(string.match(msg,"TargetZ=(%-?%d+%.?%d+),"))
			local tu=tonumber(string.match(msg,"TargetU=(%d+),"))
			local fa=string.match(msg,"FireA")
			local fb=string.match(msg,"FireB")
			local fc=string.match(msg,"FireC")
			local sd=string.match(msg,"SelfD")
			--local speed=math.sqrt((dx or 0)^2+(dz or 0)^2)
			dx=dx or 0
			dz=dz or 0
			if u and Spring.ValidUnitID(u) then
				if fa then
					if tu then
						Spring.SetUnitTarget(u,tu)
					elseif tx and tz then
						local ty=Spring.GetGroundHeight(tx,tz)
						Spring.SetUnitTarget(u,tx,ty,tz)
					end
				else
					Spring.GiveOrderToUnit(u,CMD.STOP,{},{})
				end
				if sd and not usd[u] then
					Spring.GiveOrderToUnit(u,CMD.SELFD,{},{})
					usd[u]=frame
				end
				-- Does nothing:
				--Spring.SetUnitVelocity(u,65536*dx/speed,0,65536*dz/speed)
				-- Too hard to control:
				--Spring.AddUnitImpulse(u,dx/speed,0,dz/speed)
				local x,_,z=Spring.GetUnitPosition(u)
				x=x+64*dx
				z=z+64*dz
				local y=Spring.GetGroundHeight(x,z)
				Spring.SetUnitMoveGoal(u,x,y,z)
			end
		end
		RecMsg={}

		if frame>LastHeroesCheck+139 then
			LastHeroesCheck=frame
			-- Removing heroes control from players that went inactive or spec
			for u,p in pairs(utp) do
				_,active,spectator,team=Spring.GetPlayerInfo(p)
				if not active then
					Spring.SendMessage("Player["..p.."] lost connection: removing player["..p.."]'s control over "..UnitDefs[Spring.GetUnitDefID(u)].humanName)
					ptf[p]=nil
					ptu[p]=nil
					utp[u]=nil
				elseif spectator then
					Spring.SendMessage("<PLAYER"..p.."> is now spectating: removing <PLAYER"..p..">'s control over "..UnitDefs[Spring.GetUnitDefID(u)].humanName)
					ptf[p]=nil
					ptu[p]=nil
					utp[u]=nil
				elseif team~=Spring.GetUnitTeam(u) then
					Spring.SendMessage("<PLAYER"..p.."> switched to team["..team.."]: removing <PLAYER"..p..">'s control over team["..Spring.GetUnitTeam(u).."]".." "..UnitDefs[Spring.GetUnitDefID(u)].humanName)
					ptf[p]=nil
					ptu[p]=nil
					utp[u]=nil
				end
			end
			-- Give heroless players control over playerless heroes
			for _,team in ipairs(Spring.GetTeamList()) do
				for _,u in ipairs(Spring.GetTeamUnitsByDefs(team,hero)) do
					if not utp[u] and not Spring.GetUnitIsDead(u) then
						GiveHero(u,team)
					end
				end
			end
		end

	end


	function gadget:UnitCreated(u,ud,team)
		if isHero[ud] then
			--GiveHero(u,team)
			LastHeroesCheck=-8888
		end
	end


	function gadget:UnitDestroyed(u,ud,team,atk,atkd,atkteam)
		if utp[u] then
			ScoreBoard[utp[u]].deaths=(ScoreBoard[utp[u]].deaths or 0)+1
			ScoreBoard[utp[u]].kills=0
			Spring.SendMessage("<PLAYER"..utp[u].."> lost "..UnitDefs[ud].humanName.."!")
			ptu[utp[u]]=nil
			utp[u]=nil
		end
		if utp[atk] and not Spring.AreTeamsAllied(atkteam,team) then
			ScoreBoard[utp[atk]].kills=(ScoreBoard[utp[atk]].kills or 0)+1
			ScoreBoard[utp[atk]].totalkills=(ScoreBoard[utp[atk]].totalkills or 0)+1
		end
	end


	function gadget:AllowUnitTransfer(u,ud,oldteam,newteam,capture)
		if isHero[ud] then
			return false
		else
			return true
		end
	end


	function gadget:AllowUnitCreation(ud,b,team,x,y,z)
		if isHero[ud] and Spring.GetModOptions()["homf"] and Spring.GetModOptions()["homf"]~="0" then
			if #GetBetterPlayerList(team)-#Spring.GetTeamUnitsByDefs(team,hero)>0 then
				return true
			else
				return false
			end
		end
		return true
	end


	if not AllowOtherUnitsControl then
		function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, synced)
			if (not synced) and #GetBetterPlayerList(team)>0 then
				return false
			end
			return true
		end
	end


	function gadget:RecvLuaMsg(msg,player)
		if string.sub(msg,1,12)=="Shoot'n'Run:" then
			local u=tonumber(string.match(msg,"Unit=(%d+),"))
			RecMsg[u]=msg
		end
	end

else
--UNSYNCED

	--local up_arrow,down_arrow,right_arrow,left_arrow,enter,space,dee = 273,274,275,276,13,32,100

	local function GetTheOne()
		if SYNCED.Shoot_n_Run and SYNCED.Shoot_n_Run.ptu then
			local u=SYNCED.Shoot_n_Run.ptu[Spring.GetLocalPlayerID()]
			if u and Spring.ValidUnitID(u) then
				return u
			end
		end
		return nil
	end

	function gadget:Update()-- Is called more than once per frame
		local u=GetTheOne()
		if u then
			Spring.SelectUnitArray({},false)
			local x,_,z=Spring.GetUnitPosition(u)
			local _,v,paused=Spring.GetGameSpeed()
			v = paused and 0 or v
			local vx,_,vz=Spring.GetUnitVelocity(u)
			local r=UnitDefs[Spring.GetUnitDefID(u)].maxWeaponRange
			Spring.SetCameraState({name=ta,mode=1,px=x+9*v*vx,py=0,pz=z+9*v*vz,flipped=-1,dy=-0.9,zscale=0.5,height=2*r,dx=0,dz=-0.45},1)
		else
			if Spring.GetModOptions()["homf"] and Spring.GetModOptions()["homf"]~="0" and not Spring.GetSpectatingState() then
				Spring.SelectUnitArray({},false)
				local x,y,z=Spring.GetTeamStartPosition(Spring.GetLocalTeamID())
				if x<0 or z<0 then
					x,z=Game.mapSizeX/2,Game.mapSizeZ/2
					y=Spring.GetGroundHeight(x,z)
				end
				Spring.SetCameraState({name=ta,mode=1,px=x,py=0,pz=z,flipped=-1,dy=-0.9,zscale=0.5,height=1200,dx=0,dz=-0.45},5)
			end
		end
	end

	local function Unsynced_GameFrame(caller,frame)
		local u=GetTheOne()
		if u then

			local MoveX=0
			local MoveZ=0
			local TargetX=nil
			local TargetZ=nil
			local TargetU=nil
			local FireA=false
			local FireB=false
			local FireC=false
			local SelfD=false

			-- Get mouse input
			local mx,my,LeftButton,MiddleButton,RightButton = Spring.GetMouseState()
			local _,pos = Spring.TraceScreenRay(mx,my,true,false)
			local kind,unit = Spring.TraceScreenRay(mx,my,false,false)
			if type(pos)=="table" and pos[1] and pos[3] then
				TargetX=pos[1]
				TargetZ=pos[3]
			end
			if kind=="unit" then
				TargetU=unit
			else
				TargetU=nil
			end

			-- Get keyboard input
			for _,key in ipairs(Spring.GetActionHotKeys("hero_west")) do
				if Spring.GetKeyState(Spring.GetKeyCode(key)) then
					MoveX=MoveX-1
				end
			end
			for _,key in ipairs(Spring.GetActionHotKeys("hero_east")) do
				if Spring.GetKeyState(Spring.GetKeyCode(key)) then
					MoveX=MoveX+1
				end
			end
			for _,key in ipairs(Spring.GetActionHotKeys("hero_north")) do
				if Spring.GetKeyState(Spring.GetKeyCode(key)) then
					MoveZ=MoveZ-1
				end
			end
			for _,key in ipairs(Spring.GetActionHotKeys("hero_south")) do
				if Spring.GetKeyState(Spring.GetKeyCode(key)) then
					MoveZ=MoveZ+1
				end
			end
			if Spring.GetKeyState(Spring.GetKeyCode('d')) then
				local alt,ctrl,meta,shift=Spring.GetModKeyState()
				if ctrl then
					SelfD=true
				end
			end

			-- Write message to synced
			local msg="Shoot'n'Run:"
			if u then
				msg=msg.."Unit="..u
			end
			if MoveX then
				msg=msg..",MoveX="..MoveX
			end
			if MoveZ then
				msg=msg..",MoveZ="..MoveZ
			end
			if TargetX and TargetZ then
				msg=msg..",TargetX="..TargetX..",TargetZ="..TargetZ
			end
			if TargetU then
				msg=msg..",TargetU="..TargetU
			end
			if LeftButton then
				msg=msg..",FireA"
			end
			if RightButton then
				msg=msg..",FireB"
			end
			if SelfD then
				msg=msg..",SelfD"
			end
			msg=msg..",eom"
			Spring.SendLuaRulesMsg(msg)
		end
	end

	--function gadget:MouseMove(x,y,dx,dy,button)
	--end

	--function gadget:MousePress(x,y,button)
	--	if GetTheOne() then
	--		if button==1 then
	--			return true
	--		end
	--	end
	--end

	--function gadget:MouseRelease(x,y,button)
	--end

	-- Must use Spring.GetKeyState instead
	function gadget:KeyPress(pressed_key)
		if SYNCED.Shoot_n_Run and SYNCED.Shoot_n_Run.ptu and SYNCED.Shoot_n_Run.ptu[Spring.GetLocalPlayerID()] then
			for _,hero_action in ipairs({"hero_south","hero_north","hero_west","hero_east"}) do
				for _,hero_action_key in ipairs(Spring.GetActionHotKeys(hero_action)) do
					if pressed_key==Spring.GetKeyCode(hero_action_key) then
						return true
					end
				end
			end
		end
		return false
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("Shoot_n_Run_Unsynced_GameFrame",Unsynced_GameFrame)
	end

	function gadget:DrawWorld()
		if SYNCED.Shoot_n_Run and SYNCED.Shoot_n_Run.ptu then
			for _,p in ipairs(Spring.GetPlayerList()) do
				local u=SYNCED.Shoot_n_Run.ptu[p]
				if u and Spring.ValidUnitID(u) then
					local x,y,z=Spring.GetUnitPosition(u)
					if p~=Spring.GetLocalPlayerID() then
						-- Other Player Contolled Unit
						local f=1+(Spring.GetGameSeconds()/2)%1.5
						f=f^f^f
						gl.PushMatrix()
						gl.Translate(-f*x,-f*y,-f*z)
						gl.Scale(f,f,f)
						gl.Translate(x/f,y/f,z/f)
						gl.Blending(GL.ONE_MINUS_SRC_COLOR,GL.ONE)
						gl.Unit(u)
						gl.Blending(GL.SRC_ALPHA,GL.ONE_MINUS_SRC_ALPHA)
						gl.PopMatrix()
					else
						-- My Player Controlled Unit
						local r=UnitDefs[Spring.GetUnitDefID(u)].maxWeaponRange
						gl.Blending(GL.SRC_ALPHA,GL.ONE_MINUS_SRC_ALPHA)
						gl.Color(1,0.5,0.5,0.1)
						gl.BeginEnd(GL.TRIANGLE_FAN,
							function()
								for a=0,2*math.pi,math.pi/18 do
									local px=x+r*math.cos(a)
									local pz=z+r*math.sin(a)
									local py=Spring.GetGroundHeight(px,pz)
									gl.Vertex(px,py,pz)
								end
							end
							)
						gl.Color(1,1,1,1)
					end
				end
			end
		end
	end


	local ScoreBoard={}

	function gadget:DrawScreen()
		local vsx,vsy=Spring.GetViewGeometry()
		ScoreBoard.Show=false
		local TextWidthFixHack = 1
		if tonumber(string.sub(Game.version,1,4))<=0.785 and string.sub(Game.version,1,5)~="0.78+" then
			TextWidthFixHack = (vsx/vsy)*(4/3)
		end
		if SYNCED.Shoot_n_Run and SYNCED.Shoot_n_Run.ScoreBoard and not Spring.IsGUIHidden() then
			-- Draw the Score Board
			ScoreBoard.FontSize = ScoreBoard.FontSize or vsy*0.02
			ScoreBoard.xSize = ScoreBoard.xSize or 0
			ScoreBoard.ySize = ScoreBoard.ySize or 0
			ScoreBoard.xPos = math.min(vsx-ScoreBoard.xSize-ScoreBoard.FontSize,math.max(ScoreBoard.FontSize,ScoreBoard.xPos or vsx))
			ScoreBoard.yPos = math.min(vsy,math.max(ScoreBoard.ySize,ScoreBoard.yPos or vsy-60))
			local line=0
			local MaxScoreTxtxSize=0
			for _,p in pairs(Spring.GetPlayerList()) do
				local score=SYNCED.Shoot_n_Run.ScoreBoard[p]
				if score then
					ScoreBoard.Show=true
					name,_,_,team=Spring.GetPlayerInfo(p)
					local teamcolor={Spring.GetTeamColor(team)}
					gl.Color(teamcolor[1],teamcolor[2],teamcolor[3],1)
					local ScoreTxt=((ScoreBoard.ySize>1.5*ScoreBoard.FontSize) and name.."  " or "").."Kills: "..(score.kills or 0).."/"..(score.totalkills or 0).."   Deaths: "..(score.deaths or 0)
					gl.Text(ScoreTxt,ScoreBoard.xPos,ScoreBoard.yPos-line*ScoreBoard.FontSize,ScoreBoard.FontSize,"tn")
					line=line+1
					MaxScoreTxtxSize=math.max(MaxScoreTxtxSize,gl.GetTextWidth(ScoreTxt))
				end
			end
			ScoreBoard.xSize = TextWidthFixHack*MaxScoreTxtxSize*ScoreBoard.FontSize
			ScoreBoard.ySize = line*ScoreBoard.FontSize
			if line>0 then
				--gl.Color(0.5,0.5,0.5,0.5)
				--gl.LineWidth(1)
				--gl.Shape(GL.LINE_LOOP,{
				--	{v={ScoreBoard.xPos,ScoreBoard.yPos}},{v={ScoreBoard.xPos+ScoreBoard.xSize,ScoreBoard.yPos}},
				--	{v={ScoreBoard.xPos+ScoreBoard.xSize,ScoreBoard.yPos-ScoreBoard.ySize}},{v={ScoreBoard.xPos,ScoreBoard.yPos-ScoreBoard.ySize}},})
				gl.Color(1,1,1,1)
			end
		end
		if SYNCED.Shoot_n_Run and SYNCED.Shoot_n_Run.ptu then
			-- Draw the heroes name
			for _,p in ipairs(Spring.GetPlayerList()) do
				local u=SYNCED.Shoot_n_Run.ptu[p]
				if u and Spring.ValidUnitID(u) and p~=Spring.GetLocalPlayerID() then
					local FontSize=12
					local ux,uy,uz=Spring.GetUnitPosition(u)
					local sx,sy,sz=Spring.WorldToScreenCoords(ux,uy,uz+1.3*Spring.GetUnitRadius(u))
					local name,_,_,team=Spring.GetPlayerInfo(p)
					local teamcolor={Spring.GetTeamColor(team)}
					local xsize=gl.GetTextWidth(name)*TextWidthFixHack*FontSize/2
					if sx<xsize or sy<FontSize or sx>vsx-xsize or sy>vsy  or sz>1 then
						sx,sy,sz=sx-vsx/2,sy-vsy/2,sz<1 and 1 or -1
						sx,sy=	math.max(xsize,math.min(vsx-xsize,vsx/2+(vsy/2)/math.abs(sy)*sx*sz)),
								math.max(FontSize,math.min(vsy,vsy/2+(vsx/2)/math.abs(sx)*sy*sz))
					end
					gl.Color(teamcolor[1],teamcolor[2],teamcolor[3],1)
					gl.Text(name,sx,sy,FontSize,"ac")
					gl.Color(1,1,1,1)
				end
			end
		end
	end

	function gadget:MouseMove(x,y,dx,dy,button)
		if ScoreBoard.Show and ScoreBoard.Moving then
			ScoreBoard.xPos=ScoreBoard.xPos+dx
			ScoreBoard.yPos=ScoreBoard.yPos+dy
			return true
		elseif GetTheOne() then
			return true
		end
	end

	function gadget:MousePress(x,y,button)
		if button==1 then
			if ScoreBoard.Show and x>ScoreBoard.xPos and y<ScoreBoard.yPos and x<ScoreBoard.xPos+ScoreBoard.xSize and y>ScoreBoard.yPos-ScoreBoard.ySize then
				ScoreBoard.Moving=true
				return true
			elseif GetTheOne() then
				return true
			end
		end
		return false
	end
	 
	function gadget:MouseRelease(x,y,button)
		if ScoreBoard.Moving then
			ScoreBoard.Moving=nil
			return true
		else
			return false
		end
	end

	function gadget:MouseWheel(up,value)
		if ScoreBoard.Show then
			local x,y = Spring.GetMouseState()
			if x>ScoreBoard.xPos and y<ScoreBoard.yPos and x<ScoreBoard.xPos+ScoreBoard.xSize and y>ScoreBoard.yPos-ScoreBoard.ySize then
				if up then
					ScoreBoard.FontSize = math.max(ScoreBoard.FontSize - 1,2)
				else
					ScoreBoard.FontSize = ScoreBoard.FontSize + 1
				end
				return true
			end
		end
		return false
	end

	function gadget:IsAbove(x,y)
		if ScoreBoard.Show and x>ScoreBoard.xPos and y<ScoreBoard.yPos and x<ScoreBoard.xPos+ScoreBoard.xSize and y>ScoreBoard.yPos-ScoreBoard.ySize then
			return true
		else
			return false
		end
	end

end
