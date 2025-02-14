function widget:GetInfo()
  return {
    name      = "Display Message",
    desc      = "Display message at a specific position or above a unit",
    author    = "zigaroula, martinb, mocahteam",
    date      = "Apr 29, 2016",
    license   = "GPL v2 or later",
    layer     = 0,
    enabled   = true --  loaded by default?
  }
end

local UnitMessages = {}
local PositionMessages = {}
local BubbleMessages = {}

function DisplayMessageAboveUnit(message, unit, timer)
	table.insert(UnitMessages, {message = message, unit = unit, timer = timer,infinite=(timer==0)})
end

function DisplayMessageAtPosition(message, x, y, z, timer)
	table.insert(PositionMessages, {message = message, x = x, y = y, z = z, timer = timer,infinite=(timer==0)})
end

function DisplayMessageInBubble(message, unit, timer)
	table.insert(BubbleMessages, {message = message, unit = unit, timer = timer,infinite=(timer==0)})
end

function TurnTextIntoLines(texte)
  local maxWidth=10
  local tableLines={}
  local message=""
  local wCurrentLine=0
  local f=true--first insert
  for token in string.gmatch(texte, "[^%s]+") do
    local tokSize=gl.GetTextWidth(token)
    if(((wCurrentLine+tokSize)<maxWidth) or (message=="")) then -- we continue to write on the same line
      if (f) then message=token ; f=false -- to avoid a blank space at the beginning of the message
      else message=message.." "..token end
      wCurrentLine=wCurrentLine+tokSize
    else -- threshold reached => newline
      table.insert(tableLines,message)
      message=token
      wCurrentLine=tokSize
    end
  end
  table.insert(tableLines,message) -- to include the tail of the string for which, by definition, the threshold is not reached
  return tableLines
end

-- display text at position, if the text is too wide
-- it will be cut in smaller parts by the call of TurnTextIntoLines
function DisplayTextAtScreenPosition(x, y, texte)
    local s = 30
    local tableLine=TurnTextIntoLines(texte)
    local nLines=table.getn(tableLine)
    for i, m in ipairs(tableLine) do
      local w = gl.GetTextWidth(m)*s
      gl.Text(m, x-(w/2), y+(nLines-i)*s, s, "s")
    end
end

function DisplayBubbleAtScreenPosition(x, y, text, u)
	x = x - 80
	local s = 20
	local tableLine = TurnTextIntoLines(text)
	local nLines = table.getn(tableLine)
	local height = s * nLines
	for i, m in ipairs(tableLine) do
		gl.Text(m, x+10, y+(nLines-i)*s+80, s, "s")
	end
	local top_tex = "bitmaps/game/bubble_top.png"
	local mid_tex = "bitmaps/game/bubble_mid.png"
	local bot_tex = "bitmaps/game/bubble_bot.png"
	local team = Spring.GetUnitTeam(u)
	local r, g, b, a = Spring.GetTeamColor(team)
	gl.Color(r, g, b, a)
	gl.Texture(bot_tex)
	gl.TexRect(x, y, x+300, y+80, false, false)
	gl.Texture(top_tex)
	gl.TexRect(x, y+height+80, x+300, y+height+100, false, false)
	gl.Texture(mid_tex)
	gl.TexRect(x, y+80, x+300, y+height+80, false, false)
	gl.Texture(false)
end

function widget:DrawScreen()
	for i, mes in ipairs(UnitMessages) do
		local u, m = mes.unit, mes.message
		if(not Spring.ValidUnitID(u))then return end
		local x, y, z = Spring.GetUnitPosition(u)
		x, y = Spring.WorldToScreenCoords(x, y+50, z)
		DisplayTextAtScreenPosition(x, y, m)
	end
	for i, mes in ipairs(PositionMessages) do
		local x, y, z, m = mes.x, mes.y, mes.z, mes.message
		x, y = Spring.WorldToScreenCoords(x, y, z)
		DisplayTextAtScreenPosition(x, y, m)
	end
	for i, mes in ipairs(BubbleMessages) do
		local u, m = mes.unit, mes.message
		if(not Spring.ValidUnitID(u))then return end
		local x, y, z = Spring.GetUnitPosition(u)
		x, y = Spring.WorldToScreenCoords(x, y+50, z)
		DisplayBubbleAtScreenPosition(x, y, m, u)
	end
end

function widget:Initialize()
	widgetHandler:RegisterGlobal("DisplayMessageAboveUnit", DisplayMessageAboveUnit)
	widgetHandler:RegisterGlobal("DisplayMessageAtPosition", DisplayMessageAtPosition)
	widgetHandler:RegisterGlobal("DisplayMessageInBubble", DisplayMessageInBubble)
end

function widget:Update(delta)
	local toBeRemoved = {}
	for i, m in ipairs(UnitMessages) do
	 if (not m.infinite)then
  		m.timer = m.timer - delta
  		if m.timer < 0 then
  			table.insert(toBeRemoved, i)
  		end
    end
	end
	for _, i in ipairs(toBeRemoved) do
		table.remove(UnitMessages, i)
	end
	
	toBeRemoved = {}
	for i, m in ipairs(PositionMessages) do
   if (not m.infinite)then
      m.timer = m.timer - delta
      if m.timer < 0 then
        table.insert(toBeRemoved, i)
      end
    end
	end
	for _, i in ipairs(toBeRemoved) do
		table.remove(PositionMessages, i)
	end
	
	toBeRemoved = {}
	for i, m in ipairs(BubbleMessages) do
   if (not m.infinite)then
      m.timer = m.timer - delta
      if m.timer < 0 then
        table.insert(toBeRemoved, i)
      end
    end
	end
	for _, i in ipairs(toBeRemoved) do
		table.remove(BubbleMessages, i)
	end
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal("DisplayMessageAboveUnit")
	widgetHandler:DeregisterGlobal("DisplayMessageAtPosition")
  widgetHandler:DeregisterGlobal("DisplayMessageInBubble")
end