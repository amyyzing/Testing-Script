return function(dependencies)
	local environment = dependencies.Environment or _G
	local loaderUrl = assert(dependencies.LoaderUrl, "teleport-loop requires LoaderUrl")
	local queue = dependencies.QueueOnTeleport
	if type(queue) ~= "function" then
		queue = environment.queue_on_teleport or environment.queueonteleport
	end
	if type(queue) ~= "function" then
		for _, name in ipairs({"syn", "fluxus", "krnl"}) do
			local namespace = environment[name]
			local candidate = type(namespace) == "table"
				and (namespace.queue_on_teleport or namespace.queueonteleport)
			if type(candidate) == "function" then queue = candidate break end
		end
	end
	local serial = 0
	local controller = {Enabled = environment.DemonologyLoopEnabled == true}

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		environment.DemonologyLoopEnabled = self.Enabled
		return self.Enabled
	end

	function controller:Queue(context)
		if not self.Enabled then return false, "automation loop is disabled" end
		if type(queue) ~= "function" then return false, "queue_on_teleport is unavailable" end
		context = tostring(context or "Teleport")
		if self.QueuedContext == context then return true end
		serial += 1
		local token = table.concat({tostring(os.time()), tostring(os.clock()), tostring(serial), context}, ":")
		local source = string.format([[
local environment = (getgenv and getgenv()) or _G
if environment.DemonologyLoopEnabled == false then return end
environment.DemonologyLoopEnabled = true
local token = %q
if environment.DemonologyHandoffToken == token then return end
environment.DemonologyHandoffToken = token
environment.DemonologyAutoHandoff = {Auto = true, Context = %q}
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(4)
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local source = game:HttpGet(%q .. "?v=" .. tostring(os.time()))
local chunk, compileError = compiler(source, "@DemonologyAutoLoop")
assert(chunk, compileError)
chunk()
]], token, context, loaderUrl)
		local ok, failure = pcall(queue, source)
		if not ok then return false, tostring(failure) end
		self.QueuedContext = context
		return true
	end

	return controller
end
