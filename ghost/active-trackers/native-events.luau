return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "native-events requires Traffic")
	local World = dependencies.Workspace or workspace
	local clock = dependencies.Clock or os.clock
	local tracker = {Connections = {}, Bound = {}, Glass = {}, Running = true}
	local function connect(signal, callback)
		table.insert(tracker.Connections, signal:Connect(callback))
	end
	local function bind(object, added)
		local name = string.lower(object.Name)
		local eligible = object:GetAttribute("ItemName") ~= nil
			or (object.HasTag and (object:HasTag("Candle") or object:HasTag("Lantern")))
			or object:GetAttribute("SpiritCandle") == true
			or object:GetAttribute("LeviathanGlitch") ~= nil
			or (object.Parent and object.Parent.Name == "Items")
			or name:find("candle", 1, true) or name:find("lantern", 1, true)
		local glass = object:IsA("Model") and object.Name == "BrokenGlass"
			and object.Parent and object.Parent.Name == "BrokenGlass"
		if not eligible and not glass then return end
		if tracker.Bound[object] then
			tracker.Bound[object]()
			return
		end
		local previousGlitch, candleSeen
		local function update()
			if not tracker.Running or not object:IsDescendantOf(World) then return end
			local glitch = object:GetAttribute("LeviathanGlitch")
			if type(glitch) == "number" and glitch > 0 and glitch ~= previousGlitch then
				Traffic("NativeGlitch", {Item = object, Token = glitch}):SendTo("Leviathan")
			end
			previousGlitch = glitch
			if not candleSeen and object:GetAttribute("SpiritCandle") == true then
				candleSeen = true
				Traffic("SpiritCandle", {Item = object}):SendTo("Spirit", "Doppelganger")
			end
		end
		tracker.Bound[object] = update
		if eligible and (object:IsA("Model") or object:IsA("BasePart")) then
			connect(object:GetAttributeChangedSignal("LeviathanGlitch"), update)
			connect(object:GetAttributeChangedSignal("SpiritCandle"), update)
			update()
		end
		if added and glass then
			local now = clock()
			local recent = {}
			for _, time in ipairs(tracker.Glass) do
				if now - time <= 5 then table.insert(recent, time) end
			end
			table.insert(recent, now)
			tracker.Glass = recent
			if #recent >= 2 then Traffic("GlassBurst", {Count = #recent}):SendTo("Banshee") end
		end
	end
	for _, object in ipairs(World:GetDescendants()) do bind(object, false) end
	connect(World.DescendantAdded, function(object) bind(object, true) end)
	function tracker:Destroy()
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
		table.clear(self.Bound)
	end
	return tracker
end
