function widget:GetInfo()
	return {
		name = "Spring Direct Launch 2 for SPRED",
		desc = "Show some SPRED menu when Spring.exe is run directly.",
		author = "mocahteam",
		version = "0.1",
		date = "June 24, 2016",
		license = "Public Domain",
		layer = 250,
		enabled = true,
		handler = true
	}
end

VFS.Include("LuaUI/Widgets/libs/RestartScript.lua")
VFS.Include("LuaUI/Widgets/editor/LauncherStrings.lua")
VFS.Include("LuaUI/Widgets/editor/Misc.lua")

local serde = VFS.Include("LuaUI/Widgets/libs/xml-serde.lua") -- XML serializer/deserializer
local json = VFS.Include("LuaUI/Widgets/libs/LuaJSON/dkjson.lua") -- Json serializer/deserializer
local Chili, Screen0 -- Chili
local IsActive = false -- True if this widget has to be shown
local HideView = false -- True if there is need for a black background
local vsx, vsy -- Window size
local UI = {} -- Contains each UI element
local MapList = {} -- List of the maps as read in the maps/ directory
local LevelList = {} -- List of the levels as read in the SPRED/missions/ directory
local LevelListNames = {} -- Names of the aforementioned levels
local ScenarioList = {} -- List of the scenarios as read in the SPRED/scenarios/ directory
local ScenarioListNames = {} -- Names of the aforementioned scenarios
local OutputStates = {} -- List of the output states of the levels
local Links = {} -- Links betwenn output and input states
local scenarioInEdition = false -- true if editing scenario frame is shown
local ScenarioName = "" -- Name of the current scenario
local ScenarioDesc = "" -- Description of the current scenario
local selectedInput -- Currently selected input state
local selectedOutputMission -- Currently selected output mission
local selectedOutputState -- Currently selected output state
local IncludeAllMissions = false
local MainGame = Spring.GetModOptions().maingame or getMasterGame()
local gameFolder = "games"
if Game.version == "0.82.5.1" then gameFolder = "mods" end

-- CTRL+Z/Y
local LoadLock = true -- Lock to prevent saving when loading
local SaveStates = {} -- Save states
local LoadIndex = 1 -- Current load index
local NeedToBeSaved = false -- Know when the scenario has to be changed or not

local editorRunning = false
WG.Language = Spring.GetConfigString("Language", "en") -- Get language from springrc / springsettings.cfg file. Possibly overrided in widget:Initialize.

function InitializeChili() -- Initialize Chili variables
	if not WG.Chili then
		widgetHandler:RemoveWidget()
		return
	end
	Chili = WG.Chili
	Screen0 = Chili.Screen0
end

function InitializeEditor() -- Enable editor widgets
	if not editorRunning then
		widgetHandler:EnableWidget("Editor Loading Screen")
	end
	widgetHandler:EnableWidget("Chili Framework")
	widgetHandler:EnableWidget("SPRED Hide commands")
	widgetHandler:EnableWidget("Editor Widget List")
	widgetHandler:EnableWidget("Editor User Interface")
	widgetHandler:EnableWidget("PP Restart Manager")
end

function InitializeLauncher() -- Initialize UI elements for the launcher
	if not editorRunning then
		widgetHandler:EnableWidget("Editor Loading Screen")
	end
	InitializeMainMenu()
	InitializeMapButtons()
	InitializeLevelButtons()
	InitializeScenarioFrame()
end

function InitializeMainMenu() -- Initialize the main window and buttons of the main menu
	UI.MainWindow = Chili.Window:New{
		parent = Screen0,
		x = "0%",
		y = "0%",
		width  = "100%",
		height = "100%",
		draggable = false,
		resizable = false
	}
	UI.Logo = Chili.Image:New{
		parent = UI.MainWindow,
		x = '0%',
		y = '80%',
		width = '20%',
		height = '20%',
		keepAspect = true,
		file = "bitmaps/launcher/su.png"
	}
	UI.Title = Chili.Image:New{
		parent = UI.MainWindow,
		x = '0%',
		y = '2%',
		width = '100%',
		height = '20%',
		keepAspect = true,
		file = "bitmaps/launcher/spred_logo.png"
	}
	UI.Subtitle = Chili.Label:New{
		parent = UI.MainWindow,
		x = '0%',
		y = '22%',
		width = '100%',
		height = '3%',
		caption = string.gsub(LAUNCHER_SUBTITLE, "/MAINGAME/", MainGame),
		valign = "linecenter",
		align = "center",
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 40,
			autoAdjust = true,
			maxSize = 40,
			color = { 0.2, 0.4, 0.8, 1 },
			shadow = false
		}
	}
	UI.NewMissionButton = Chili.Button:New{
		parent = UI.MainWindow,
		x = "30%",
		y = "30%",
		width = "40%",
		height = "10%",
		caption = LAUNCHER_NEW_MISSION,
		OnClick = { NewMissionFrame },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			color = { 0.2, 1, 0.8, 1 },
			shadow = false
		}
	}
	UI.EditMissionButton = Chili.Button:New{
		parent = UI.MainWindow,
		x = "30%",
		y = "40%",
		width = "40%",
		height = "10%",
		caption = LAUNCHER_EDIT_MISSION,
		OnClick = { EditMissionFrame },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			color = { 0.2, 1, 0.8, 1 },
			shadow = false
		}
	}
	UI.EditScenarioButton = Chili.Button:New{
		parent = UI.MainWindow,
		x = "30%",
		y = "50%",
		width = "40%",
		height = "10%",
		caption = LAUNCHER_SCENARIO,
		OnClick = { EditScenarioFrame },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			color = { 0.2, 1, 0.8, 1 },
			shadow = false
		}
	}
	UI.ExportGameButton = Chili.Button:New{
		parent = UI.MainWindow,
		x = "30%",
		y = "60%",
		width = "40%",
		height = "10%",
		caption = LAUNCHER_SCENARIO_EXPORT_GAME,
		OnClick = { ExportGameFrame },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			color = { 0.2, 1, 0.8, 1 },
			shadow = false
		}
	}
	UI.LanguageComboBox = Chili.ComboBox:New{
		parent = UI.MainWindow,
		x = "85%",
		y = "0%",
		width = "15%",
		height = "7%",
		items = { "English", "Fran�ais" },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 20,
			autoAdjust = true,
			maxSize = 20,
			color = { 0.2, 1, 0.8, 1 },
			shadow = false
		}
	}
	UI.LanguageComboBox.OnSelect = { -- Change language to the newly selected language
		function()
			if UI.LanguageComboBox.selected == 1 then
				ChangeLanguage("en")
			elseif UI.LanguageComboBox.selected == 2 then
				ChangeLanguage("fr")
			end
		end
	}
	UI.BackToEditor = Chili.Button:New{
		parent = UI.MainWindow,
		x = "80%",
		y = "8%",
		width = "20%",
		height = "7%",
		caption = LAUNCHER_BACK_TO_EDITOR,
		OnClick = { SwitchOff },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			color = { 0.2, 1, 0.8, 1 },
			shadow = false
		},
		backgroundColor = { 0, 0.2, 0.6, 1 },
		focusColor= { 0, 0.6, 1, 1 },
	}
	UI.BackButton = Chili.Button:New{
		parent = UI.MainWindow,
		x = "1%",
		y = "0%",
		width = "10%",
		height = "10%",
		caption = "",
		backgroundColor = { 0, 0.2, 0.6, 1 },
		focusColor = { 0, 0.6, 1, 1 },
		OnClick = { function ()
				if NeedToBeSaved then
					FrameWarning(LAUNCHER_SCENARIO_WARNING, nil, true, false, function() ResetScenario() MainMenuFrame() NeedToBeSaved = false end)
				else
					ResetScenario()
					MainMenuFrame()
					NeedToBeSaved = false
				end
			end
	 	}
	}
	Chili.Image:New{ -- Image for the back button
		parent = UI.BackButton,
		x = "10%",
		y = "10%",
		width = "80%",
		height = "80%",
		keepAspect = false,
		file = "bitmaps/launcher/arrow.png"
	}
	UI.QuitButton = Chili.Button:New{
		parent = UI.MainWindow,
		x = "90%",
		y = "90%",
		width = "10%",
		height = "10%",
		caption = LAUNCHER_QUIT,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			color = { 0.8, 0.6, 0.2, 1 },
			shadow = false
		},
		backgroundColor = { 0.8, 0, 0.2, 1 },
		focusColor= { 0.8, 0.6, 0.2, 1 },
		OnClick = { function ()
				if NeedToBeSaved then
					FrameWarning(LAUNCHER_SCENARIO_WARNING, nil, true, false, Quit)
				else
					Quit()
				end
			end
	 	}
	}
end

function InitializeMapList() -- Initialization of maps
	MapList = VFS.GetMaps()
end

function InitializeLevelList() -- Initialization of levels
	local toBeRemoved = {} -- Remove levels not corresponding to the chosen game
	LevelListNames = VFS.DirList("SPRED/missions/", "*.editor", VFS.RAW)
	for i, level in ipairs(LevelListNames) do
		level = string.gsub(level, "SPRED\\missions\\", "")
		level = string.gsub(level, ".editor", "")
		LevelListNames[i] = level -- This table contains the raw name of the levels
		LevelList[i] = json.decode(VFS.LoadFile("SPRED/missions/"..level..".editor",  VFS.RAW)) -- This table contains the whole description of the levels
		if LevelList[i].description.mainGame ~= MainGame then
			table.insert(toBeRemoved, level)
		end
	end
	for i, level in ipairs(toBeRemoved) do
		local removedIndex = nil
		for ii, l in ipairs(LevelListNames) do
			if level == l then
				removedIndex = ii
			end
		end
		if removedIndex then
			table.remove(LevelListNames, removedIndex)
			table.remove(LevelList, removedIndex)
		end
	end
end

function UpdateScenarioList() -- update scenarios
	local toBeRemoved = {} -- Remove scenarios not corresponding to the chosen game
	ScenarioListNames = VFS.DirList("SPRED/scenarios/", "*.xml", VFS.RAW)
	for i, scenario in ipairs(ScenarioListNames) do
		ScenarioList[i] = serde.deserialize(VFS.LoadFile(scenario)) -- This table contains the whole description of the scenarios
		scenario = string.gsub(scenario, "SPRED\\scenarios\\", "")
		scenario = string.gsub(scenario, ".xml", "")
		ScenarioListNames[i] = scenario -- This table contains the raw name of the scenarios
		if not string.find(ScenarioList[i].kids[1].kids[2].text, MainGame) then
			table.insert(toBeRemoved, scenario)
		end
	end
	for i, scenario in ipairs(toBeRemoved) do
		local removedIndex = nil
		for ii, s in ipairs(ScenarioListNames) do
			if scenario == s then
				removedIndex = ii
			end
		end
		if removedIndex then
			table.remove(ScenarioListNames, removedIndex)
			table.remove(ScenarioList, removedIndex)
		end
	end
end

function InitializeOutputStates() -- Initialization of the list that contains every output states
	Links["start"] = {}
	for i, level in ipairs(LevelList) do
		OutputStates[LevelListNames[i]] = {}
		Links[LevelListNames[i]] = {}
		for ii, e in ipairs(level.events) do
			for iii, a in ipairs(e.actions) do
				if a.type == "win" or a.type == "lose" or a.type == "gameover" then -- Read the output states within the win, lose and gameover actions of events
					-- Avoid outputstates duplication
					if not findInTable(OutputStates[LevelListNames[i]], a.params.outputState) then
						table.insert(OutputStates[LevelListNames[i]], a.params.outputState)
					end
				end
			end
		end
	end
end

function InitializeMapButtons() -- Create a button for each map to select it
	InitializeMapList()
	UI.NewLevel = {}
	UI.NewLevel.Title = Chili.Label:New{
		parent = UI.MainWindow,
		x = "20%",
		y = "10%",
		width = "60%",
		height = "5%",
		align = "center",
		valign = "linecenter",
		caption = LAUNCHER_NEW_TITLE,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 50,
			autoAdjust = true,
			maxSize = 50,
			color = { 0, 0.8, 1, 1 },
			shadow = false
		}
	}
	UI.NewLevel.MapScrollPanel = Chili.ScrollPanel:New{
		parent = UI.MainWindow,
		x = "20%",
		y = "20%",
		width = "60%",
		height = "60%",
	}
	if #MapList == 0 then
		UI.NewLevel.NoMapMessage = Chili.TextBox:New{
			parent = UI.NewLevel.MapScrollPanel,
			x = "5%",
			y = "5%",
			width = "90%",
			height = "90%",
			text = LAUNCHER_NEW_NO_MAP_FOUND,
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 20,
				autoAdjust = true,
				maxSize = 20,
				color = { 1, 0, 0, 1 },
				shadow = false
			}
		}
	else
		UI.NewLevel.MapButtons = {}
		for i, map in ipairs(MapList) do
			local mapButton = Chili.Button:New{
				parent = UI.NewLevel.MapScrollPanel,
				x = "0%",
				y = ((i-1)*15).."%",
				width = "100%",
				height = "15%",
				caption = map,
				OnClick = { function() NewMission(map) end },
				font = {
					font = "LuaUI/Fonts/Asimov.otf",
					size = 30,
					autoAdjust = true,
					maxSize = 30,
					color = { 0.2, 0.4, 0.8, 1 },
					shadow = false
				}
			}
			table.insert(UI.NewLevel.MapButtons, mapButton)
		end
	end
end

function InitializeLevelButtons() -- Create a button for each level to edit it
	InitializeLevelList()
	UI.LoadLevel = {}
	UI.LoadLevel.Title = Chili.Label:New{
		parent = UI.MainWindow,
		x = "20%",
		y = "10%",
		width = "60%",
		height = "5%",
		align = "center",
		valign = "linecenter",
		caption = LAUNCHER_EDIT_TITLE,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 50,
			autoAdjust = true,
			maxSize = 50,
			color = { 0, 0.8, 1, 1 },
			shadow = false
		}
	}
	UI.LoadLevel.LevelScrollPanel = Chili.ScrollPanel:New{
		parent = UI.MainWindow,
		x = "20%",
		y = "20%",
		width = "60%",
		height = "60%",
	}
	if #LevelListNames == 0 then
		UI.LoadLevel.NoLevelMessage = Chili.TextBox:New{
			parent = UI.LoadLevel.LevelScrollPanel,
			x = "5%",
			y = "5%",
			width = "90%",
			height = "90%",
			text = string.gsub(LAUNCHER_EDIT_NO_LEVEL_FOUND, "/MAINGAME/", MainGame),
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 20,
				autoAdjust = true,
				maxSize = 20,
				color = { 1, 0, 0, 1 },
				shadow = false
			}
		}
	else
		UI.LoadLevel.LevelButtons = {}
		for i, level in ipairs(LevelListNames) do
			local levelButton = Chili.Button:New{
				parent = UI.LoadLevel.LevelScrollPanel,
				x = "0%",
				y = ((i-1)*15).."%",
				width = "100%",
				height = "15%",
				caption = LevelList[i].description.name,
				OnClick = { function() EditMission(level) end },
				font = {
					font = "LuaUI/Fonts/Asimov.otf",
					size = 30,
					autoAdjust = true,
					maxSize = 30,
					color = { 0.2, 0.4, 0.8, 1 },
					shadow = false
				}
			}
			table.insert(UI.LoadLevel.LevelButtons, levelButton)
		end
	end
end

function InitializeScenarioFrame() -- Create a window for each level, and in each window, create a button for each output state and one for the input state
	InitializeLevelList()
	InitializeOutputStates()
	UpdateScenarioList()
	UI.Scenario = {}
	UI.Scenario.Title = Chili.Label:New{
		parent = UI.MainWindow,
		x = "20%",
		y = "10%",
		width = "60%",
		height = "5%",
		align = "center",
		valign = "linecenter",
		caption = LAUNCHER_SCENARIO_TITLE,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 50,
			autoAdjust = true,
			maxSize = 50,
			color = { 0, 0.8, 1, 1 },
			shadow = false
		}
	}
	UI.Scenario.Reset = Chili.Button:New{
		parent = UI.MainWindow,
		x = '91%',
		y = '12%',
		width = '9%',
		height = '8%',
		caption = LAUNCHER_SCENARIO_RESET,
		OnClick = { ResetScenario },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 20,
			autoAdjust = true,
			maxSize = 20,
			color = { 0, 0.8, 1, 1 },
			shadow = false
		},
		backgroundColor = { 1, 0.8, 0.4, 1 }
	}
	UI.Scenario.Open = Chili.Button:New{
		parent = UI.MainWindow,
		x = "1%",
		y = "90%",
		width = "20%",
		height = "10%",
		caption = LAUNCHER_SCENARIO_OPEN,
		backgroundColor = { 0.2, 1, 0.8, 1 },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 25,
			autoAdjust = true,
			maxSize = 25,
			shadow = false,
		},
		OnClick = { function ()
				if NeedToBeSaved then
					FrameWarning(LAUNCHER_SCENARIO_WARNING, nil, true, false, function() NeedToBeSaved = false OpenScenarioFrame() end)
				else
					OpenScenarioFrame()
				end
			end
	 	}
	}
	UI.Scenario.Save = Chili.Button:New{
		parent = UI.MainWindow,
		x = "21%",
		y = "90%",
		width = "20%",
		height = "10%",
		caption = LAUNCHER_SCENARIO_SAVE,
		backgroundColor = { 0, 0.8, 1, 1 },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 25,
			autoAdjust = true,
			maxSize = 25,
			shadow = false,
		},
		OnClick = { SaveScenarioFrame }
	}
	UI.Scenario.ScenarioScrollPanel = Chili.ScrollPanel:New{
		parent = UI.MainWindow,
		x = "1%",
		y = "20%",
		width = "99%",
		height = "69%"
	}
	UI.Scenario.Output = {}
	UI.Scenario.Input = {}
	UI.Scenario.Levels = {}
	UI.Scenario.Levels["start"] = Chili.Window:New{ -- Specific start window
		parent = UI.Scenario.ScenarioScrollPanel,
		x = 10,
		y = 10,
		width = 150,
		height = 75,
		draggable = true,
		resizable = false
	}
	UI.Scenario.Output["start"] = {}
	UI.Scenario.Output["start"][1] = Chili.Button:New{
		parent = UI.Scenario.Levels["start"],
		x = "0%",
		y = "0%",
		width = "100%",
		height = "100%",
		caption = LAUNCHER_SCENARIO_BEGIN,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 16,
			autoAdjust = true,
			maxSize = 16,
			shadow = false,
		},
		OnClick = { function()
			if selectedOutputMission == "start" and selectedOutputState == 1 then -- Delete links when double-click
				if Links[selectedOutputMission][selectedOutputState] then
					UI.Scenario.Output[selectedOutputMission][selectedOutputState].state.chosen = false
					UI.Scenario.Output[selectedOutputMission][selectedOutputState]:InvalidateSelf()
					Links[selectedOutputMission][selectedOutputState] = nil
					local someLinks = {}
					for k, link in pairs(Links) do
						for kk, output in pairs(link) do
							someLinks[output] = true
						end
					end
					for k, b in pairs(UI.Scenario.Input) do
						if not someLinks[k] then
							b.state.chosen = false
							b:InvalidateSelf()
						end
					end
				end
				selectedOutputState = nil
				selectedOutputMission = nil
				SaveState()
			else
				selectedOutputMission = "start"
				selectedOutputState = 1
			end
		end }
	}
	UI.Scenario.Levels["end"] = Chili.Window:New{ -- Specific end window
		parent = UI.Scenario.ScenarioScrollPanel,
		x = 170,
		y = 10,
		width = 150,
		height = 75,
		draggable = true,
		resizable = false
	}
	UI.Scenario.Input["end"] = Chili.Button:New{
		parent = UI.Scenario.Levels["end"],
		x = "0%",
		y = "0%",
		width = "100%",
		height = "100%",
		caption = LAUNCHER_SCENARIO_END,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 16,
			autoAdjust = true,
			maxSize = 16,
			shadow = false,
		},
		OnClick = { function()
				if selectedOutputMission and selectedOutputState then
					selectedInput = "end"
				end
			end
		},
		chosenColor = { math.random(), math.random(), math.random(), 1 } -- Initialize the chosen color for links
	}
	local column = -1
	local defaultWidth = 300
	local nbColumns = math.max(math.floor(UI.Scenario.ScenarioScrollPanel.width / (defaultWidth+10)), 1)
	local nbLines = math.ceil(#LevelList / nbColumns)
	local maxY = 0
	for i, level in ipairs(LevelList) do
		-- Search for output states
		local outputStates = OutputStates[LevelListNames[i]]
		if nbColumns == 1 or i%nbColumns == 1 then
			column = 0
		else
			column = column + 1
		end
		local nextY = 95
		if i > nbColumns then
			nextY = UI.Scenario.Levels[LevelListNames[i-nbColumns]].y + UI.Scenario.Levels[LevelListNames[i-nbColumns]].height + 10
		end
		UI.Scenario.Levels[LevelListNames[i]] = Chili.Window:New{
			parent = UI.Scenario.ScenarioScrollPanel,
			x = 10 + column * (defaultWidth+10),
			y = nextY,
			width = defaultWidth,
			height = math.max(150, (#outputStates + 2) * 30),
			draggable = true,
			resizable = false
		}
		maxY  = math.max(maxY, UI.Scenario.Levels[LevelListNames[i]].y+UI.Scenario.Levels[LevelListNames[i]].height)
		Chili.Label:New{
			parent = UI.Scenario.Levels[LevelListNames[i]],
			x = "0%",
			y = 0,
			width = "100%",
			height = 30,
			caption = level.description.name,
			align = "center",
			valign = "linecenter",
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 18,
				autoAdjust = true,
				maxSize = 18,
				color = { 0, 0.8, 0.8, 1 },
				shadow = false
			}
		}
		UI.Scenario.Input[LevelListNames[i]] = Chili.Button:New{
			parent = UI.Scenario.Levels[LevelListNames[i]],
			x = 0,
			y = 30,
			width = 50,
			height = 30,
			caption = "in",
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 16,
				autoAdjust = true,
				maxSize = 16,
				shadow = false,
			},
			OnClick = { function()
				if selectedInput == LevelListNames[i] then -- Delete links when double-click
					for k, link in pairs(Links) do
						for kk, linked in pairs(link) do
							if linked == selectedInput then
								UI.Scenario.Output[k][kk].state.chosen = false
								UI.Scenario.Output[k][kk]:InvalidateSelf()
								Links[k][kk] = nil
							end
						end
					end
					UI.Scenario.Input[selectedInput].state.chosen = false
					UI.Scenario.Input[selectedInput]:InvalidateSelf()
					selectedInput = nil
					SaveState()
				elseif selectedOutputMission and selectedOutputState then
					selectedInput = LevelListNames[i]
				end
			end },
			chosenColor = { math.random(), math.random(), math.random(), 1 } -- Initialize the chosen color for links
		}
		UI.Scenario.Output[LevelListNames[i]] = {}
		for ii, out in ipairs(outputStates) do
			local but = Chili.Button:New{
				parent = UI.Scenario.Levels[LevelListNames[i]],
				x = 155,
				y = ii * 30,
				width = 120,
				height = 30,
				caption = out,
				font = {
					font = "LuaUI/Fonts/Asimov.otf",
					size = 16,
					autoAdjust = true,
					maxSize = 16,
					shadow = false,
				}
			}
			but.OnClick = { function()
				if selectedOutputMission == LevelListNames[i] and selectedOutputState == out then -- Delete links when double-click
					if Links[selectedOutputMission][selectedOutputState] then
						UI.Scenario.Output[selectedOutputMission][selectedOutputState].state.chosen = false
						UI.Scenario.Output[selectedOutputMission][selectedOutputState]:InvalidateSelf()
						Links[selectedOutputMission][selectedOutputState] = nil
						local someLinks = {}
						for k, link in pairs(Links) do
							for kk, output in pairs(link) do
								someLinks[output] = true
							end
						end
						for k, b in pairs(UI.Scenario.Input) do
							if not someLinks[k] then
								b.state.chosen = false
								b:InvalidateSelf()
							end
						end
					end
					selectedOutputState = nil
					selectedOutputMission = nil
					SaveState()
				else
					selectedOutputMission = LevelListNames[i]
					selectedOutputState = out
				end
			end }
			UI.Scenario.Output[LevelListNames[i]][out] = but
		end
	end
	local drawLinks = function(obj) -- Function to draw links between buttons
		gl.Color(1, 1, 1, 1)
		gl.LineWidth(3)
		gl.BeginEnd(
			GL.LINES,
			function()
				if selectedOutputMission and selectedOutputState then -- Draw a link between the center of the selected output and the mouse cursor
					local x, y
					x = UI.Scenario.Output[selectedOutputMission][selectedOutputState].x + UI.Scenario.Output[selectedOutputMission][selectedOutputState].tiles[1]/2 + UI.Scenario.Levels[selectedOutputMission].x + UI.Scenario.Output[selectedOutputMission][selectedOutputState].width/2
					y = UI.Scenario.Output[selectedOutputMission][selectedOutputState].y + UI.Scenario.Output[selectedOutputMission][selectedOutputState].tiles[2]/2 + UI.Scenario.Levels[selectedOutputMission].y + UI.Scenario.Output[selectedOutputMission][selectedOutputState].height/2
					local mouseX, mouseY = Spring.GetMouseState()
					mouseX = mouseX - obj.x - UI.Scenario.ScenarioScrollPanel.x - UI.Scenario.ScenarioScrollPanel.tiles[1] - 7 + UI.Scenario.ScenarioScrollPanel.scrollPosX
					mouseY = vsy - mouseY - obj.y - UI.Scenario.ScenarioScrollPanel.y - UI.Scenario.ScenarioScrollPanel.tiles[2] - 7 + UI.Scenario.ScenarioScrollPanel.scrollPosY
					gl.Vertex(x, y)
					gl.Vertex(mouseX, mouseY)
				end
				for k, link in pairs(Links) do -- Draw a link between each linked pair input/output
					for kk, out in pairs(link) do
						gl.Color(unpack(UI.Scenario.Output[k][kk].chosenColor)) -- Color is the color of the button
						local x1, y1, x2, y2
						x1 = UI.Scenario.Output[k][kk].x + UI.Scenario.Output[k][kk].tiles[1]/2 + UI.Scenario.Levels[k].x + UI.Scenario.Output[k][kk].width/2 -- Compute the coordinates of the center of the button. Tiles represents an offset to make children buttons look better.
						y1 = UI.Scenario.Output[k][kk].y + UI.Scenario.Output[k][kk].tiles[2]/2 + UI.Scenario.Levels[k].y + UI.Scenario.Output[k][kk].height/2
						x2 = UI.Scenario.Input[out].x + UI.Scenario.Input[out].tiles[1]/2 + UI.Scenario.Levels[out].x + UI.Scenario.Input[out].width/2
						y2 = UI.Scenario.Input[out].y + UI.Scenario.Input[out].tiles[2]/2 + UI.Scenario.Levels[out].y + UI.Scenario.Input[out].height/2
						gl.Vertex(x1, y1)
						gl.Vertex(x2, y2)
					end
				end
			end
		)
	end
	UI.Scenario.Links = Chili.Control:New{
		parent = UI.Scenario.ScenarioScrollPanel,
		x = 0,
		y = 0,
		width = 10 + nbColumns * (defaultWidth+10),
		height = maxY,
		DrawControl = drawLinks,
		drawcontrolv2 = true
	}
end

function UpdateCaption(element, text) -- Update the caption of an UI element
	if element then
		element:SetCaption(text)
	end
end

function UpdateText(element, text) -- Update the text of an UI element
	if element then
		element:SetText(text)
	end
end

function ClearUI() -- Remove UI elements from the screen
	ClearTemporaryUI()
	UI.MainWindow:RemoveChild(UI.Title)
	UI.MainWindow:RemoveChild(UI.Subtitle)
	UI.MainWindow:RemoveChild(UI.Logo)
	UI.MainWindow:RemoveChild(UI.BackToEditor)
	UI.MainWindow:RemoveChild(UI.NewMissionButton)
	UI.MainWindow:RemoveChild(UI.EditMissionButton)
	UI.MainWindow:RemoveChild(UI.EditScenarioButton)
	UI.MainWindow:RemoveChild(UI.ExportGameButton)
	UI.MainWindow:RemoveChild(UI.BackButton)

	UI.MainWindow:RemoveChild(UI.NewLevel.Title)
	UI.MainWindow:RemoveChild(UI.NewLevel.MapScrollPanel)

	UI.MainWindow:RemoveChild(UI.LoadLevel.Title)
	UI.MainWindow:RemoveChild(UI.LoadLevel.LevelScrollPanel)

	UI.MainWindow:RemoveChild(UI.Scenario.Title)
	UI.MainWindow:RemoveChild(UI.Scenario.ScenarioScrollPanel)
	UI.MainWindow:RemoveChild(UI.Scenario.Save)
	UI.MainWindow:RemoveChild(UI.Scenario.Open)
	UI.MainWindow:RemoveChild(UI.Scenario.Reset)
	scenarioInEdition = false
end

function ClearTemporaryUI() -- Remove pop-ups
	if UI.Scenario.OpenScenarioPopUp then
		UI.Scenario.OpenScenarioPopUp:Dispose()
	end
	if UI.Scenario.SaveScenarioPopUp then
		UI.Scenario.SaveScenarioPopUp:Dispose()
	end
	if UI.Scenario.WarningPopUp then
		UI.Scenario.WarningPopUp:Dispose()
	end
	if UI.Scenario.ExportGamePopUp then
		UI.Scenario.ExportGamePopUp:Dispose()
	end
end

function MainMenuFrame() -- Shows the main menu
	-- reset history
	SaveStates = {}
	LoadIndex = 1
	-- Display main menu
	ClearUI()
	UI.MainWindow:AddChild(UI.Title)
	UI.MainWindow:AddChild(UI.Subtitle)
	UI.MainWindow:AddChild(UI.Logo)
	if editorRunning then
		UI.MainWindow:AddChild(UI.BackToEditor)
	end
	UI.MainWindow:AddChild(UI.NewMissionButton)
	UI.MainWindow:AddChild(UI.EditMissionButton)
	UI.MainWindow:AddChild(UI.EditScenarioButton)
	UI.MainWindow:AddChild(UI.ExportGameButton)
end

function NewMissionFrame() -- Shows the new mission menu
	ClearUI()
	UI.MainWindow:AddChild(UI.BackButton)
	UI.MainWindow:AddChild(UI.NewLevel.Title)
	UI.MainWindow:AddChild(UI.NewLevel.MapScrollPanel)
end

function EditMissionFrame() -- Shows the edit mission menu
	ClearUI()
	InitializeLevelButtons()
	UI.MainWindow:AddChild(UI.BackButton)
end

function EditScenarioFrame() -- Shows the edit scenario menu
	ClearUI()
	scenarioInEdition = true
	InitializeScenarioFrame()
	UI.MainWindow:AddChild(UI.BackButton)
	-- force all output and input states to redraw (resolves bug on Begin and End
	-- that are already display in chosen state even if they aren't in this state)
	for k, but in pairs(UI.Scenario.Input) do
		but:InvalidateSelf()
	end
	for k, out in pairs(UI.Scenario.Output) do
		for kk, but in pairs(out) do
			but:InvalidateSelf()
		end
	end
	NeedToBeSaved = false
end

function SaveScenarioFrame() -- Shows the save scenario pop-up
	ClearTemporaryUI()
	local window = Chili.Window:New{
		parent = UI.MainWindow,
		x = '20%',
		y = '40%',
		width = '60%',
		height = '30%',
		draggable = false,
		resizable = false,
		color = {1, 1, 1, 1}
	}
	local closeButton = Chili.Image:New{
		parent = window,
		x = '95%',
		y = '0%',
		width = '5%',
		height = '10%',
		minWidth = 0,
		minHeight = 0,
		keepAspect = true,
		file = "bitmaps/editor/close.png",
		color = { 1, 0, 0, 1 },
		OnClick = { function() window:Dispose() end }
	}
	closeButton.OnMouseOver = { function() closeButton.color = { 1, 0.5, 0, 1 } end }
	closeButton.OnMouseOut = { function() closeButton.color = { 1, 0, 0, 1 } end }
	Chili.Label:New{
		parent = window,
		x = '5%',
		y = '10%',
		width = '15%',
		height = '21%',
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 20,
			autoAdjust = true,
			maxSize = 20,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		},
		valign = "linecenter",
		caption = LAUNCHER_SCENARIO_NAME
	}
	local nameBox = Chili.EditBox:New{
		parent = window,
		x = '25%',
		y = '10%',
		width = '60%',
		height = '21%',
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 20,
			autoAdjust = true,
			maxSize = 20,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		},
		text = ScenarioName,
		hint = LAUNCHER_SCENARIO_NAME_DEFAULT,
		hintFont = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 16,
			autoAdjust = true,
			maxSize = 16,
			color = {0.6, 0.6, 0.6, 1},
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		},
	}
	Chili.Label:New{
		parent = window,
		x = '5%',
		y = '36%',
		width = '15%',
		height = '21%',
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 20,
			autoAdjust = true,
			maxSize = 20,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		},
		valign = "linecenter",
		caption = LAUNCHER_SCENARIO_DESCRIPTION
	}
	local descBox = Chili.EditBox:New{
		parent = window,
		x = '25%',
		y = '36%',
		width = '60%',
		height = '21%',
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 16,
			autoAdjust = true,
			maxSize = 16,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		},
		text = ScenarioDesc,
		hint = LAUNCHER_SCENARIO_DESCRIPTION_DEFAULT,
		hintFont = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 16,
			autoAdjust = true,
			maxSize = 16,
			color = {0.6, 0.6, 0.6, 1},
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		},
	}
	nameBox.OnKeyPress = {
		function (self, key)
			if key == Spring.GetKeyCode("enter") or key == Spring.GetKeyCode("numpad_enter") then
				Screen0:FocusControl(descBox)
			end
		end
	}
	local exportBut = Chili.Button:New{
		parent = window,
		x = "30%",
		y = "65%",
		width = "40%",
		height = "33%",
		caption = LAUNCHER_SCENARIO_SAVE,
		backgroundColor = { 0, 0.8, 1, 1 },
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 25,
			autoAdjust = true,
			maxSize = 25,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		}
	}
	descBox.OnKeyPress = {
		function (self, key)
			if key == Spring.GetKeyCode("enter") or key == Spring.GetKeyCode("numpad_enter") then
				Screen0:FocusControl(exportBut)
			end
		end
	}
	local function saveClicked ()
		local name, desc
		if nameBox.text ~= "" then
			name = nameBox.text
		else
			name = LAUNCHER_SCENARIO_NAME_DEFAULT
		end
		if descBox.text ~= "" then
			desc = descBox.text
		else
			desc = LAUNCHER_SCENARIO_DESCRIPTION_DEFAULT
		end
		window:Dispose()
		SaveScenario(name, desc)
	end
	exportBut.OnClick = { saveClicked }
	exportBut.OnKeyPress = {
		function (self, key)
			if key == Spring.GetKeyCode("enter") or key == Spring.GetKeyCode("numpad_enter") then
				Screen0:FocusControl(nil)
				saveClicked ()
			end
		end
	}
	Chili.Image:New{
		parent = window,
		x = '0%',
		y = '0%',
		width = '100%',
		height = '100%',
		keepAspect = false,
		file = "bitmaps/editor/blank.png",
		color = { 0, 0, 0, 1 }
	}
	UI.Scenario.SaveScenarioPopUp = window
	Screen0:FocusControl(nameBox)
end

--- Shows a warning message
-- @tparam msg1 first line of the message to display as warning
-- @tparam msg2 optionnal second line of the message to display as warning
-- @bool yesnoButton if true display "yes" and "no" buttons
-- @bool okButton if true display "ok" button
-- @tparam yesCallback function listener yes button clicked
function FrameWarning(msg1, msg2, yesnoButton, okButton, yesCallback)
	ClearTemporaryUI()
	local window = Chili.Window:New{
		parent = UI.MainWindow,
		x = '20%',
		y = (not msg2 or msg2 == "") and '45%' or '40%', -- 45% if msg2 is not defined or empty and 40% otherwise
		width = '60%',
		height = (not msg2 or msg2 == "") and '20%' or '30%', -- 20% if msg2 is not defined or empty and 30% otherwise
		draggable = false,
		resizable = false
	}
	Chili.Label:New{
		parent = window,
		x = '2%',
		y = '0%',
		width = '96%',
		height = (not msg2 or msg2 == "") and '50%' or '33%',
		align = "center",
		valign = "linecenter",
		caption = msg1,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 25,
			autoAdjust = true,
			maxSize = 25,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		}
	}
	if msg2 and msg2~="" then
		Chili.Label:New{
		parent = window,
		x = '2%',
		y = '33%',
		width = '96%',
		height = '33%',
		align = "center",
		valign = "linecenter",
		caption = msg2,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 25,
			autoAdjust = true,
			maxSize = 25,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		}
	}
	end
	if (yesnoButton) then
		Chili.Button:New{
			parent = window,
			x = '0%',
			y = (not msg2 or msg2 == "") and '55%' or '66%',
			width = '33%',
			height = (not msg2 or msg2 == "") and '40%' or '33%',
			caption = LAUNCHER_YES,
			OnClick = { yesCallback },
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 25,
				autoAdjust = true,
				maxSize = 25,
				-- avoid transparent artifact on windows superposition
				outlineWidth = 0,
				outlineWeight = 0,
				outline = true,
				shadow = false
			}
		}
		Chili.Button:New{
			parent = window,
			x = '66%',
			y = (not msg2 or msg2 == "") and '55%' or '66%',
			width = '33%',
			height = (not msg2 or msg2 == "") and '40%' or '33%',
			caption = LAUNCHER_NO,
			OnClick = { ClearTemporaryUI },
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 25,
				autoAdjust = true,
				maxSize = 25,
				-- avoid transparent artifact on windows superposition
				outlineWidth = 0,
				outlineWeight = 0,
				outline = true,
				shadow = false
			}
		}
	end
	if okButton then
		Chili.Button:New{
			parent = window,
			x = '33%',
			y = (not msg2 or msg2 == "") and '55%' or '66%',
			width = '33%',
			height = (not msg2 or msg2 == "") and '40%' or '33%',
			caption = LAUNCHER_OK,
			OnClick = { ClearTemporaryUI },
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 25,
				autoAdjust = true,
				maxSize = 25,
				-- avoid transparent artifact on windows superposition
				outlineWidth = 0,
				outlineWeight = 0,
				outline = true,
				shadow = false
			}
		}
	end
	Chili.Image:New{
		parent = window,
		x = '0%',
		y = '0%',
		width = '100%',
		height = '100%',
		keepAspect = false,
		file = "bitmaps/editor/blank.png",
		color = { 0, 0, 0, 1 }
	}
	UI.Scenario.WarningPopUp = window
end

function OpenScenarioFrame() -- Shows the import scenario pop-up
	ClearTemporaryUI()
	local window = Chili.Window:New{
		parent = UI.MainWindow,
		x = '30%',
		y = '30%',
		width = '40%',
		height = '40%',
		draggable = false,
		resizable = false
	}
	Chili.Label:New{
		parent = window,
		x = '2%',
		y = '0%',
		width = '90%',
		height = '19%',
		caption = LAUNCHER_SCENARIO_SELECT,
		valign = "linecenter",
		align = "center",
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			-- avoid transparent artifact on windows superposition
			outlineWidth = 0,
			outlineWeight = 0,
			outline = true,
			shadow = false
		}
	}
	local scrollPanel = Chili.ScrollPanel:New{
		parent = window,
		x = '0%',
		y = '20%',
		width = '100%',
		height = '80%',
	}
	local closeButton = Chili.Image:New{
		parent = window,
		x = '95%',
		y = '0%',
		width = '5%',
		height = '5%',
		minWidth = 0,
		minHeight = 0,
		keepAspect = true,
		file = "bitmaps/editor/close.png",
		color = { 1, 0, 0, 1 },
		OnClick = { function() window:Dispose() end }
	}
	closeButton.OnMouseOver = { function() closeButton.color = { 1, 0.5, 0, 1 } end }
	closeButton.OnMouseOut = { function() closeButton.color = { 1, 0, 0, 1 } end }
	UpdateScenarioList()
	if #ScenarioList == 0 then
		Chili.TextBox:New{
			parent = scrollPanel,
			x = "5%",
			y = "5%",
			width = "90%",
			height = "90%",
			text = string.gsub(LAUNCHER_SCENARIO_OPEN_SCENARIO_NOT_FOUND, "/MAINGAME/", MainGame),
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 20,
				autoAdjust = true,
				maxSize = 20,
				color = { 1, 0, 0, 1 },
				shadow = false
			}
		}
	else
		for i, name in ipairs(ScenarioListNames) do
			Chili.Button:New{
				parent = scrollPanel,
				x = '0%',
				y = ((i-1) * 25).."%",
				width = '100%',
				height = "25%",
				caption = name,
				OnClick = { function()
						ResetScenario()
						OpenScenario(ScenarioList[i])
						window:Dispose()
				 	end
				},
				font = {
					font = "LuaUI/Fonts/Asimov.otf",
					size = 30,
					autoAdjust = true,
					maxSize = 30,
					shadow = false,
				}
			}
		end
	end
	Chili.Image:New{
		parent = window,
		x = '0%',
		y = '0%',
		width = '100%',
		height = '100%',
		keepAspect = false,
		file = "bitmaps/editor/blank.png",
		color = { 0, 0, 0, 1 }
	}
	UI.Scenario.OpenScenarioPopUp = window
end

function ExportGameFrame()
	ClearTemporaryUI()
	local window = Chili.Window:New{
		parent = UI.MainWindow,
		x = '20%',
		y = '20%',
		width = '60%',
		height = '60%',
		draggable = false,
		resizable = false
	}
	Chili.Label:New{
		parent = window,
		x = "0%",
		y = "0%",
		width = "80%",
		height = "10%",
		caption = LAUNCHER_SCENARIO_EXPORT_GAME_TITLE,
		align = "center",
		valing = "center",
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 30,
			autoAdjust = true,
			maxSize = 30,
			shadow = false
		}
	}
	local scrollPanel = Chili.ScrollPanel:New{
		parent = window,
		x = '0%',
		y = '10%',
		width = '100%',
		height = '80%',
	}
	local closeButton = Chili.Image:New{
		parent = window,
		x = '95%',
		y = '0%',
		width = '5%',
		height = '5%',
		minWidth = 0,
		minHeight = 0,
		keepAspect = true,
		file = "bitmaps/editor/close.png",
		color = { 1, 0, 0, 1 },
		OnClick = { function() window:Dispose() end }
	}
	closeButton.OnMouseOver = { function() closeButton.color = { 1, 0.5, 0, 1 } end }
	closeButton.OnMouseOut = { function() closeButton.color = { 1, 0, 0, 1 } end }
	local includeMissions = Chili.Checkbox:New{
		parent = window,
		x = "0%",
		y = "90%",
		width = "50%",
		height = "10%",
		maxboxsize = 20,
		boxalign = "left",
		checked = false,
		caption = "  "..LAUNCHER_SCENARIO_EXPORT_GAME_INCLUDE_ALL,
		font = {
			font = "LuaUI/Fonts/Asimov.otf",
			size = 20,
			autoAdjust = true,
			maxSize = 20,
			shadow = false,
		}
	}
	UpdateScenarioList()
	if #ScenarioList == 0 then
		Chili.TextBox:New{
			parent = scrollPanel,
			x = "5%",
			y = "5%",
			width = "90%",
			height = "90%",
			text = string.gsub(LAUNCHER_SCENARIO_OPEN_SCENARIO_NOT_FOUND, "/MAINGAME/", MainGame),
			font = {
				font = "LuaUI/Fonts/Asimov.otf",
				size = 20,
				autoAdjust = true,
				maxSize = 20,
				color = { 1, 0, 0, 1 },
				shadow = false
			}
		}
	else
		for i, name in ipairs(ScenarioListNames) do
			Chili.Button:New{
				parent = scrollPanel,
				x = '0%',
				y = ((i-1) * 15).."%",
				width = '100%',
				height = "15%",
				caption = name,
				OnClick = { function()
					IncludeAllMissions = includeMissions.checked
					if (OpenScenario(ScenarioList[i])) then
						BeginExportGame()
					end
					window:Dispose()
				end },
				font = {
					font = "LuaUI/Fonts/Asimov.otf",
					size = 20,
					autoAdjust = true,
					maxSize = 20,
					shadow = false,
				}
			}
		end
	end
	Chili.Image:New{
		parent = window,
		x = '0%',
		y = '0%',
		width = '100%',
		height = '100%',
		keepAspect = false,
		file = "bitmaps/editor/blank.png",
		color = { 0, 0, 0, 1 }
	}
	UI.Scenario.ExportGamePopUp = window
end

function ChangeLanguage(lang) -- Load strings corresponding to lang and update captions/texts
	-- close pop-up
	ClearTemporaryUI()

	WG.Language = lang
	-- store this default language in config file
	Spring.SetConfigString("Language", lang)
	
	GetLauncherStrings(lang)

	UpdateCaption(UI.Subtitle, string.gsub(LAUNCHER_SUBTITLE, "/MAINGAME/", MainGame))
	UpdateCaption(UI.BackToEditor, LAUNCHER_BACK_TO_EDITOR)
	UpdateCaption(UI.NewMissionButton, LAUNCHER_NEW_MISSION)
	UpdateCaption(UI.EditMissionButton, LAUNCHER_EDIT_MISSION)
	UpdateCaption(UI.EditScenarioButton, LAUNCHER_SCENARIO)
	UpdateCaption(UI.ExportGameButton, LAUNCHER_SCENARIO_EXPORT_GAME)
	UpdateCaption(UI.QuitButton, LAUNCHER_QUIT)

	UpdateText(UI.NewLevel.NoMapMessage, LAUNCHER_NEW_NO_MAP_FOUND)
	UpdateCaption(UI.NewLevel.Title, LAUNCHER_NEW_TITLE)

	UpdateText(UI.LoadLevel.NoLevelMessage, string.gsub(LAUNCHER_EDIT_NO_LEVEL_FOUND, "/MAINGAME/", MainGame))
	UpdateCaption(UI.LoadLevel.Title, LAUNCHER_EDIT_TITLE)

	UpdateCaption(UI.Scenario.Title, LAUNCHER_SCENARIO_TITLE)
	UpdateCaption(UI.Scenario.Output["start"][1], LAUNCHER_SCENARIO_BEGIN)
	UpdateCaption(UI.Scenario.Input["end"], LAUNCHER_SCENARIO_END)
	UpdateCaption(UI.Scenario.Save, LAUNCHER_SCENARIO_SAVE)
	UpdateCaption(UI.Scenario.Open, LAUNCHER_SCENARIO_OPEN)
	UpdateCaption(UI.Scenario.Reset, LAUNCHER_SCENARIO_RESET)
end

function NewMission(map) -- Start editor with empty mission on the selected map
	local operations = {
		["MODOPTIONS"] = {
			["language"] = WG.Language,
			["scenario"] = "noScenario",
			["maingame"] = MainGame
		},
		["GAME"] = {
			["Mapname"] = map,
			["Gametype"] = Game.modName
		}
	}
	DoTheRestart("LevelEditor.txt", operations)
end

function EditMission(level) -- Start editor with selected mission
	if VFS.FileExists("SPRED/missions/"..level..".editor",  VFS.RAW) then
		local levelFile = VFS.LoadFile("SPRED/missions/"..level..".editor",  VFS.RAW)
		levelFile = json.decode(levelFile)
		local operations = {
			["MODOPTIONS"] = {
				["language"] = WG.Language,
				["scenario"] = "noScenario",
				["toBeLoaded"] = level,
				["maingame"] = MainGame
			},
			["GAME"] = {
				["Mapname"] = levelFile.description.map,
				["Gametype"] = Game.modName
			}
		}
		DoTheRestart("LevelEditor.txt", operations)
	end
end

function ComputeInputStates() -- Associative table between input states and output states/missions
	local inputStates = {}
	for i = 1, #LevelList, 1 do
		inputStates[LevelListNames[i]] = {}
	end
	inputStates["end"] = {}
	for k, link in pairs(Links) do
		for kk, linku in pairs(link) do
			table.insert(inputStates[linku], { k, kk })
		end
	end
	return inputStates
end

function SaveScenario(name, desc) -- Creates a table using the xml-serde formalism and export it as a xml file
	ScenarioName = name
	ScenarioDesc = desc
	NeedToBeSaved = false
	local inputStates = ComputeInputStates()
	-- Base
	local xmlScenario = {
		["name"] = "games",
		["attr"] = {
			["xsi:noNamespaceSchemaLocation"] = "http://seriousgames.lip6.fr/appliq/MoPPLiq_XML_v0.3.xsd",
			["xmlns:xsi"] = "http://www.w3.org/2001/XMLSchema-instance"
		},
		["kids"] = {
			{
				["name"] = "game",
				["attr"] = {
					["id_game"] = "76",
					["status"] = "prepa",
					["publication_date"] = os.date("%Y-%m-%dT%H:%M:%S+01:00"),
					["activity_prefix"] = "true"
				},
				["kids"] = {
					{
						["name"] = "title",
						["text"] = "SPRED"
					},
					{
						["name"] = "description",
						["text"] = "Game made with SPRED for "..MainGame
					},
					{
						["name"] = "activities",
						["kids"] = {}
					},
					{
						["name"] = "link_sets",
						["kids"] = {
							{
								["name"] = "link_set",
								["attr"] = {
									["id_link_set"] = "302",
									["default"] = "oui",
									["publication_date"] = os.date("%Y-%m-%dT%H:%M:%S+01:00"),
									["status"] = "prepa"
								},
								["kids"] = {
									{
										["name"] = "title",
										["text"] = name
									},
									{
										["name"] = "description",
										["text"] = desc
									},
									{
										["name"] = "links",
										["kids"] = {}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	-- Only consider levels with links
	local purifiedLevelList = {}
	for k, link in pairs(Links) do
		for kk, input in pairs(link) do
			if not findInTable(purifiedLevelList, input) and findInTable(LevelListNames, input) then
				table.insert(purifiedLevelList, input)
			end
		end
	end

	-- Activities
	for i, level in ipairs(LevelList) do
		if findInTable(purifiedLevelList, LevelListNames[i]) then
			local activity = {
				["name"] = "activity",
				["attr"] = {
					["id_activity"] = tostring(LevelListNames[i])
				},
				["kids"] = {
					{
						["name"] = "name",
						["text"] = level.description.name
					},
					{
						["name"] = "input_states",
						["kids"] = {}
					},
					{
						["name"] = "output_states",
						["kids"] = {}
					}
				}
			}
			-- input
			local count = 1
			for ii, inp in ipairs(inputStates[LevelListNames[i]]) do
				local inputState = {
					["name"] = "input_state",
					["attr"] = {
						["id_input"] = LevelListNames[i].."||"..count
					}
				}
				table.insert(activity.kids[2].kids, inputState)
				count = count + 1
			end
			-- output
			for ii, out in ipairs(OutputStates[LevelListNames[i]]) do
				local outputState = {
					["name"] = "output_state",
					["attr"] = {
						["id_output"] = LevelListNames[i].."||"..out
					}
				}
				table.insert(activity.kids[3].kids, outputState)
			end
			table.insert(xmlScenario.kids[1].kids[3].kids, activity)
		end
	end
	-- Links
	for k, link in pairs(Links) do
		if k == "start" and link[1] then
			local id = link[1]
			for ii, linku in ipairs(inputStates[link[1]]) do
				if k == linku[1] and linku[2] == 1 then
					id = id.."||"..ii
					break
				end
			end
			local l = {
				["name"] = "output_input_link",
				["attr"] = {
					["id_output"] = "start",
					["id_input"] = id
				}
			}
			table.insert(xmlScenario.kids[1].kids[4].kids[1].kids[3].kids, l)
		else
			for kk, link2 in pairs(link) do
				if link2 == "end" then
					local l = {
						["name"] = "output_input_link",
						["attr"] = {
							["id_output"] = k.."||"..kk,
							["id_input"] = "end"
						}
					}
					table.insert(xmlScenario.kids[1].kids[4].kids[1].kids[3].kids, l)
				else
					for iii, linku in ipairs(inputStates[link2]) do
						if k == linku[1] and kk == linku[2] then
							local l = {
								["name"] = "output_input_link",
								["attr"] = {
									["id_output"] = k.."||"..kk,
									["id_input"] = link2.."||"..iii
								}
							}
							table.insert(xmlScenario.kids[1].kids[4].kids[1].kids[3].kids, l)
						end
					end
				end
			end
		end
	end
	local xmlString = string.gsub(serde.serialize(xmlScenario), "%>%<", ">\n<") -- Serialize as xml string and insert \n for a more readable file
	xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"..xmlString -- Add the first line
	local saveName = generateSaveName(name)
	local file = io.open("SPRED/scenarios/"..saveName..".xml", "w")
	file:write(xmlString)
	file:close()
end

function SaveState() -- Save the current state of the scenario
	if LoadLock then
		savedLinks = deepcopy(Links)
		for i = 1, LoadIndex-1, 1 do -- Erase states
			table.remove(SaveStates, 1)
		end
		LoadIndex = 1
		table.insert(SaveStates, 1, savedLinks)
		NeedToBeSaved = true
	end
end

function LoadState(direction) -- Load a previous state of the scenario
	LoadLock = false
	if (LoadIndex < #SaveStates and direction > 0) or (LoadIndex > 1 and direction < 0) then
		LoadIndex = LoadIndex + direction
		ResetLinks()
		local links = SaveStates[LoadIndex]
		for k, link in pairs(links) do
			for kk, input in pairs(link) do
				selectedInput = input
				selectedOutputMission = k
				selectedOutputState = kk
				MakeLink()
			end
		end
		NeedToBeSaved = true
	end
	LoadLock = true
end

function OpenScenario(xmlTable) -- Load a scenario from a xml file
	loadingSuccess = true
	ResetLinks()
	LoadLock = false
	NeedToBeSaved = false
	links = xmlTable.kids[1].kids[4].kids[1].kids[3].kids
	if links ~= nil then
		for i, link in ipairs(links) do
			local input = splitString2(link.attr.id_input, "||")[1]
			local outputMission, output = unpack(splitString2(link.attr.id_output, "||"))
			if outputMission == "start" then
				selectedOutputMission = "start"
				selectedOutputState = 1
				selectedInput = input
			else
				selectedOutputMission = outputMission
				selectedOutputState = output
				selectedInput = input
			end
			MakeLink()
		end
		ScenarioName = xmlTable.kids[1].kids[4].kids[1].kids[1].text
		ScenarioDesc = xmlTable.kids[1].kids[4].kids[1].kids[2].text
	else
		FrameWarning(LAUNCHER_SCENARIO_EMPTY, nil, false, true)
		loadingSuccess = false
	end
	LoadLock = true
	return loadingSuccess
end

function ResetLinks()
	NeedToBeSaved = false
	for k, link in pairs(Links) do
		Links[k] = {}
	end
	for k, but in pairs(UI.Scenario.Input) do
		but.state.chosen = false
		but:InvalidateSelf()
	end
	for k, out in pairs(UI.Scenario.Output) do
		for kk, but in pairs(out) do
			but.state.chosen = false
			but:InvalidateSelf()
		end
	end
end

function ResetScenario()
	ResetLinks()
	ScenarioName = ""
	ScenarioDesc = ""
	SaveState()
end

function BeginExportGame()
	-- check editor existence in order to extract game model
	local editorName = string.gsub(Game.modName, " "..Game.modVersion, "") -- remove version to Game.modName
	if not VFS.FileExists(gameFolder.."/"..editorName..".sdz") then
		local message = string.gsub(LAUNCHER_SCENARIO_EXPORT_GAME_FAIL_ARCHIVE_NOT_FOUND, "/GAMEFILENAME/", "<Spring>/"..gameFolder.."/"..editorName..".sdz")
		FrameWarning (message, nil, false, true)
		return
	end

	-- Choose levels
	local levelList = {}
	if IncludeAllMissions then
		for i, level in ipairs(LevelListNames) do
			table.insert(levelList, level)
		end
	else
		for k, link in pairs(Links) do
			for kk, input in pairs(link) do
				if not findInTable(levelList, input) and findInTable(LevelListNames, input) then
					table.insert(levelList, input)
				end
			end
		end
	end

	-- Choose traces
	local tracesList = {}
	for i, level in ipairs(LevelList) do
		if findInTable(levelList, level.description.saveName) and level.description.traces then
			for ii, trace in ipairs(level.description.traces) do
				table.insert(tracesList, level.description.saveName..","..trace)
			end
		end
	end

	local name = generateSaveName(ScenarioName)
	local scenarioName = ScenarioName
	if VFS.BuildPPGame then
		-- Check if game exists
		if VFS.FileExists(gameFolder.."/"..name..".sdz") then
			local msg = string.gsub(LAUNCHER_SCENARIO_EXPORT_GAME_EXISTS, "/MAINGAME/", gameFolder.."/"..name..".sdz")
			FrameWarning(msg, LAUNCHER_SCENARIO_EXPORT_GAME_CONFIRM, true, false,
				function ()
					VFS.BuildPPGame(editorName, scenarioName, ScenarioDesc, generateSaveName(ScenarioName), name, MainGame, levelList, tracesList, "1")
					FrameWarning(LAUNCHER_SCENARIO_EXPORT_GAME_SUCCESS, "<Spring>/"..gameFolder.."/"..name..".sdz", false, true)
				end
			)
		else
			VFS.BuildPPGame(editorName, scenarioName, ScenarioDesc, generateSaveName(ScenarioName), name, MainGame, levelList, tracesList, "1")
			FrameWarning(LAUNCHER_SCENARIO_EXPORT_GAME_SUCCESS, "<Spring>/"..gameFolder.."/"..name..".sdz", false, true)
		end
	else
		FrameWarning(LAUNCHER_SCENARIO_EXPORT_GAME_WRONG_VERSION, nil, false, true)
		Spring.Echo ("WARNING!!! VFS.BuildPPGame == nil => wrong Spring version")
	end
end

function MakeLink() -- If both input and output are selected, proceed linking
	if selectedInput and selectedOutputMission then

		if (findInTable(LevelListNames, selectedInput) and findInTable(LevelListNames, selectedOutputMission))
			or (selectedOutputMission == "start" and findInTable(LevelListNames, selectedInput))
			or (selectedInput == "end" and findInTable(LevelListNames, selectedOutputMission))
		then
			local isValidOutput = false
			if selectedOutputMission == "start" then
				isValidOutput = true
			else
				isValidOutput = findInTable(OutputStates[selectedOutputMission], selectedOutputState)
			end
			if isValidOutput then
				Links[selectedOutputMission][selectedOutputState] = selectedInput

				UI.Scenario.Output[selectedOutputMission][selectedOutputState].chosenColor = UI.Scenario.Input[selectedInput].chosenColor
				UI.Scenario.Output[selectedOutputMission][selectedOutputState].state.chosen = true
				UI.Scenario.Output[selectedOutputMission][selectedOutputState]:InvalidateSelf()
				UI.Scenario.Input[selectedInput].state.chosen = true
				UI.Scenario.Input[selectedInput]:InvalidateSelf()

				local someLinks = {}
				for k, link in pairs(Links) do
					for kk, output in pairs(link) do
						someLinks[output] = true
					end
				end
				for k, b in pairs(UI.Scenario.Input) do
					if not someLinks[k] then
						b.state.chosen = false
						b:InvalidateSelf()
					end
				end

				SaveState()
			end
		end

		selectedOutputState = nil
		selectedOutputMission = nil
		selectedInput = nil
	end

	if UI.Scenario then
		UI.Scenario.Links:InvalidateSelf()
	end
end

function Quit() -- Close spring
	Spring.SendCommands("quit")
	Spring.SendCommands("quitforce")
end

function RemoveOtherWidgets() -- Disable other widgets
  local RemovedWidgetList = {}
  local RemovedWidgetListName = {}
  for name,kw in pairs(widgetHandler.knownWidgets) do
    if kw.active and name ~= "Spring Direct Launch 2 for SPRED" and name ~= "Chili Framework" then
      table.insert(RemovedWidgetListName,name)
    end
  end
  for _,w in pairs(widgetHandler.widgets) do
    for _,name in pairs(RemovedWidgetListName) do
      if w.GetInfo().name == name then
        table.insert(RemovedWidgetList,w)
      end
    end
  end
  for _,w in pairs(RemovedWidgetList) do
    Spring.Echo("Removing",w.GetInfo().name)
    widgetHandler:RemoveWidget(w)
  end
end

function EitherDrawScreen() -- Shows a black background if required
	if not vsx or not vsy or not HideView then
		return
	end

	local bgText = "bitmaps/editor/blank.png"
	gl.Blending(false)
	gl.Color(0, 0, 0, 0)
	gl.Texture(bgText)
	gl.TexRect(vsx, vsy, 0, 0, 0, 0, 1, 1)
	gl.Texture(false)
	gl.Blending(true)
end

function SwitchOn() -- Activate this widget
	Spring.SendCommands({"NoSound 1"})
	Spring.SendCommands("forcestart")
	Spring.SendCommands("fps 0")
	HideView = true
	if not editorRunning then
		RemoveOtherWidgets()
	end
	InitializeLauncher()
	MainMenuFrame()
	if WG.Language == "en" then
		UI.LanguageComboBox:Select(1)
	elseif WG.Language == "fr" then
		UI.LanguageComboBox:Select(2)
	end
	SaveState()
	NeedToBeSaved = false
end

function backToMainMenu() -- called in editor_user_interface.lua
	editorRunning = true
	SwitchOn()
end
WG.BackToMainMenu = backToMainMenu

function SwitchOff() -- Desactivate this widget
	HideView = false
	if UI.MainWindow then
		UI.MainWindow:Dispose()
	end
	if not editorRunning then
		RemoveOtherWidgets()
		InitializeEditor()
	else
		WG.BackToEditor() -- Defined in editor_user_interface.lua
	end
end

function widget:DrawScreenEffects(dse_vsx, dse_vsy)
	vsx, vsy = dse_vsx, dse_vsy
	if Spring.IsGUIHidden() then
		EitherDrawScreen()
	end
end

function widget:DrawScreen()
	if not Spring.IsGUIHidden() then
		EitherDrawScreen()
	end
end

function CreateMissingDirectories()
	if not VFS.FileExists("SPRED") then
		Spring.CreateDir("SPRED")
	end
	if not VFS.FileExists("SPRED/missions") then
		Spring.CreateDir("SPRED/missions")
	end
	if not VFS.FileExists("SPRED/scenarios") then
		Spring.CreateDir("SPRED/scenarios")
	end
end

function widget:Initialize()
	widgetHandler:EnableWidget("Chili Framework")
	CreateMissingDirectories()
	InitializeChili()
	
	-- override Language with ModOption if exists
	if Spring.GetModOptions().language then
		WG.Language = Spring.GetModOptions().language
	end
	
	if not Spring.GetModOptions().hidemenu then
		SwitchOn()
	else
		SwitchOff()
	end
end

function widget:Update(delta)
	if HideView then
		MakeLink()
	end
	if scenarioInEdition then
		-- update link area
		local maxX = 0
		local maxY = 0
		for i, level in ipairs(LevelList) do
			maxX  = math.max(maxX, UI.Scenario.Levels[LevelListNames[i]].x+UI.Scenario.Levels[LevelListNames[i]].width)
			maxY  = math.max(maxY, UI.Scenario.Levels[LevelListNames[i]].y+UI.Scenario.Levels[LevelListNames[i]].height)
		end
		UI.Scenario.Links.width = maxX
		UI.Scenario.Links.height = maxY
	end
end

function widget:MousePress(mx, my, button)
	if HideView and button == 3 then
		selectedInput = nil
		selectedOutputMission = nil
		selectedOutputState = nil
	end
end

function widget:KeyPress(key, mods)
	if HideView then
		if key == Spring.GetKeyCode("esc") then
			MainMenuFrame()
			return true
		end
		if key == Spring.GetKeyCode("z") and mods.ctrl then
			LoadState(1)
			return true
		end
		if key == Spring.GetKeyCode("y") and mods.ctrl then
			LoadState(-1)
			return true
		end
		if key == Spring.GetKeyCode("enter") or key == Spring.GetKeyCode("numpad_enter") then
			return true
		end
	end
end
