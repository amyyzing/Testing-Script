if not game:IsLoaded() then game.Loaded:Wait() end

local BASE_URL = "https://raw.githubusercontent.com/amyyzing/Testing-Script/refs/heads/main/"
local VERSION = tostring(os.time())
local environment = (getgenv and getgenv()) or _G
local Services = {
	Players = game:GetService("Players"),
	UserInputService = game:GetService("UserInputService"),
	TweenService = game:GetService("TweenService"),
	RunService = game:GetService("RunService"),
	Lighting = game:GetService("Lighting"),
	CoreGui = game:GetService("CoreGui"),
	Workspace = game:GetService("Workspace"),
}
local player = Services.Players.LocalPlayer

local function loadModule(path)
	local source = game:HttpGet(BASE_URL .. path .. "?v=" .. VERSION)
	assert(type(source) == "string" and source ~= "", "Empty module: " .. path)
	local compiler = loadstring or load
	assert(type(compiler) == "function", "This executor does not provide loadstring")
	local chunk, compileError = compiler(source, "@" .. path)
	assert(chunk, ("Compilation failed for %s: %s"):format(path, tostring(compileError)))
	local ok, result = xpcall(chunk, debug.traceback)
	assert(ok, ("Initialization failed for %s:\n%s"):format(path, tostring(result)))
	return result
end

local previous = environment.DemonologySession
if previous and type(previous.Destroy) == "function" then pcall(previous.Destroy, previous) end

local LoadScreen = loadModule("gui/load-screen.luau")
local loading = LoadScreen.new({Services = Services, Player = player, Title = "Demonology Assistant"})
loading:SetStage("Loading interface", 1, 10)

local Aesthetic = loadModule("gui/aesthetic.luau")
loading:SetStage("Loading window controls", 2, 10)
local GuiLogic = loadModule("gui/gui-logic.luau")
loading:SetStage("Loading traffic", 3, 10)
local createTraffic = loadModule("ghost/traffic.luau")
loading:SetStage("Loading verdict", 4, 10)
local createVerdict = loadModule("ghost/verdict.luau")
loading:SetStage("Loading Aswang", 5, 10)
local Aswang = loadModule("ghost/ghosts/Aswang.luau")
loading:SetStage("Loading trackers", 6, 10)
local createHuntingState = loadModule("ghost/active-trackers/hunting-state.luau")
local createKillCount = loadModule("ghost/active-trackers/kill-count.luau")
local createSaltHit = loadModule("ghost/active-trackers/salt-hit.luau")
local createSpeedTracker = loadModule("ghost/active-trackers/speed-tracker.luau")
local createSaltState = loadModule("ghost/discardable-trackers/salt-state-after-hit.luau")
local createEscapeHunt = loadModule("logic/escape-hunt.luau")
local createBright = loadModule("logic/bright.luau")
local createGhostESP = loadModule("logic/ghost-esp.luau")
local createTeleportBaseCamp = loadModule("logic/teleport-base-camp.luau")

loading:SetStage("Building interface", 7, 10)
local view = Aesthetic.Create({
	Services = Services,
	Player = player,
	Environment = environment,
})
local session
local presenter = GuiLogic.new({
	Services = Services,
	Player = player,
	View = view,
	OnClose = function()
		if session then session:Destroy() end
	end,
})

session = {
	Destroyed = false,
	Connections = {},
	Trackers = {},
	View = view,
	Presenter = presenter,
	Loading = loading,
}
environment.DemonologySession = session

local function remember(value)
	table.insert(session.Trackers, value)
	return value
end

local teleportToBaseCamp = createTeleportBaseCamp({Player = player, Workspace = Services.Workspace})
session.TeleportToBaseCamp = teleportToBaseCamp
session.Bright = remember(createBright({
	Lighting = Services.Lighting,
	Button = view.Buttons.Bright,
	EnabledColor = view.Colors.Accent,
}))

local function disconnectWaiting()
	for _, connection in ipairs(session.Connections) do connection:Disconnect() end
	table.clear(session.Connections)
end

function session:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	disconnectWaiting()
	for index = #self.Trackers, 1, -1 do
		local tracker = self.Trackers[index]
		if tracker and type(tracker.Destroy) == "function" then pcall(tracker.Destroy, tracker) end
	end
	self.Presenter:Destroy()
	if self.View.Gui then self.View.Gui:Destroy() end
	if self.Loading and not self.Loading.Destroyed then self.Loading:Destroy() end
	if environment.UntitledGuiInstance == self.View.Gui then environment.UntitledGuiInstance = nil end
	if environment.DemonologySession == self then environment.DemonologySession = nil end
end

local coreStarted, saltStarted = false, false
local descendantConnection
local function startTrackers()
	if session.Destroyed then return end
	local ghost = Services.Workspace:FindFirstChild("Ghost")
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	if not coreStarted and (not ghost or not humanoid) then
		view.Status.Text = not ghost and "Waiting for Workspace.Ghost"
			or "Waiting for Ghost Humanoid"
		return
	end

	if not coreStarted then
		coreStarted = true
		if descendantConnection then descendantConnection:Disconnect() end
		local Traffic = createTraffic()
		local Verdict = createVerdict({Traffic = Traffic})
		session.Traffic, session.Verdict, session.Ghost = Traffic, Verdict, ghost
		remember(Aswang.new({Traffic = Traffic}))
		session.EscapeHunt = remember(createEscapeHunt({
			Player = player,
			Ghost = ghost,
			TeleportToSafety = teleportToBaseCamp,
			Button = view.Buttons.HuntEscape,
			EnabledColor = view.Colors.Accent,
		}))
		session.GhostESP = remember(createGhostESP({
			Ghost = ghost,
			RunService = Services.RunService,
			Workspace = Services.Workspace,
			GuiParent = view.Gui.Parent,
			Button = view.Buttons.GhostESP,
			EnabledColor = view.Colors.Accent,
			Red = view.Colors.Danger,
		}))
		remember(createSpeedTracker({Traffic = Traffic, Ghost = ghost}))
		remember(createKillCount({Traffic = Traffic, Players = Services.Players}))
		remember(createHuntingState({Traffic = Traffic, Ghost = ghost}))
	end

	local saltPiles = Services.Workspace:FindFirstChild("SaltPiles")
	if not saltStarted and saltPiles then
		saltStarted = true
		remember(createSaltState({Traffic = session.Traffic, SaltFolder = saltPiles}))
		remember(createSaltHit({Traffic = session.Traffic, Ghost = session.Ghost, SaltFolder = saltPiles}))
		disconnectWaiting()
	end
	view.Status.Text = saltStarted and "Aswang tracker running"
		or "Aswang kill tracker running; waiting for salt"
end

loading:SetStage("Starting Aswang tracker", 8, 10)
table.insert(session.Connections, Services.Workspace.ChildAdded:Connect(startTrackers))
descendantConnection = Services.Workspace.DescendantAdded:Connect(startTrackers)
table.insert(session.Connections, descendantConnection)
startTrackers()
presenter:Bind()

loading:SetStage(coreStarted and "Ready" or "Waiting for round", 10, 10)
task.delay(0.2, function()
	if not loading.Destroyed then loading:Destroy() end
end)

return session
