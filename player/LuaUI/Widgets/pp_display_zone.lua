function widget:GetInfo()
  return {
    name      = "PP Display Zones",
    desc      = "Display zone at a specific position",
    author    = "mocahteam",
    date      = "Apr 29, 2016",
    license   = "GPL v2 or later",
    layer     = 300,
    enabled   = true --  loaded by default?
  }
end

VFS.Include("LuaUI/Widgets/libs/MiscCommon.lua")
local lang = Spring.GetModOptions()["language"] -- get the language

local Zones = {}

function AddZoneToDisplayList(zone)
	-- check if this zone is not already in display list
	local found = false
	for i, z in ipairs(Zones) do
		if z.id == zone.id then
			found = true
			break
		end
	end
	if not found then
        zone.inGameText = extractLang(zone.inGameText, lang)
		zone.inGameText = string.gsub(zone.inGameText, "\\n", "\n")
		table.insert(Zones, zone)
	end
end

function RemoveZoneFromDisplayList(zone)
	for i, z in ipairs(Zones) do
		if z.id == zone.id then
			table.remove(Zones, i)
			break
		end
	end
end

function DrawText(text, _x, _z)
	local s = 20
	local x, y = Spring.WorldToScreenCoords(_x, Spring.GetGroundHeight(_x, _z), _z)
	gl.Text(text, x, y, s, "vcs")
end

function DrawGroundFilledEllipsis(centerX, centerZ, a, b, red, green, blue)
	local divs = 100
	gl.Color(red, green, blue, 0.5)
	gl.BeginEnd(GL.TRIANGLE_STRIP, function()
		for angle = 0, 2*math.pi+2*math.pi/divs, 2*math.pi/divs do
			local x, z = centerX + a * math.cos(angle), centerZ + b * math.sin(angle)
			gl.Vertex(x, Spring.GetGroundHeight(x, z), z)
			gl.Vertex(centerX, Spring.GetGroundHeight(centerX, centerZ), centerZ)
		end
	end)
	gl.Color(1, 1, 1, 1)
end

function DrawGroundRectangle(x1, x2, z1, z2, r, g, b)
	gl.Color(r, g, b, 0.5)
	gl.DrawGroundQuad(x1, z1, x2, z2)
	gl.Color(1, 1, 1, 1)
end

function widget:DrawWorld()
	for i, z in ipairs(Zones) do
		if z.type == "Rectangle" then
			DrawGroundRectangle(z.x1, z.x2, z.z1, z.z2, z.red, z.green, z.blue)
		elseif z.type == "Disk" then
			DrawGroundFilledEllipsis(z.x, z.z, z.a, z.b, z.red, z.green, z.blue)
		end
	end
end

function widget:DrawScreen()
	for i, z in ipairs(Zones) do
		if z.type == "Rectangle" then
			DrawText(z.inGameText, (z.x1+z.x2)/2, (z.z1+z.z2)/2)
		elseif z.type == "Disk" then
			DrawText(z.inGameText, z.x, z.z)
		end
	end
end

function widget:Initialize()
	widgetHandler:RegisterGlobal("AddZoneToDisplayList", AddZoneToDisplayList)
	widgetHandler:RegisterGlobal("RemoveZoneFromDisplayList", RemoveZoneFromDisplayList)
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal("AddZoneToDisplayList")
	widgetHandler:DeregisterGlobal("RemoveZoneFromDisplayList")
end