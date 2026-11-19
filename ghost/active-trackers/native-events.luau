return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "native-events requires Traffic")
	local World = dependencies.Workspace or workspace
	local clock = dependencies.Clock or os.clock
	local tracker = {Connections = {}, Bound = {}, Running = true}
	local function connect(signal, callback)
		table.insert(tracker.Connections, signal:Connect(callback))
	end
	local function bind(object)
		local name = string.lower(object.Name)
		local eligible = object:GetAttribute("ItemName") ~= nil
			or (object.HasTag and (object:HasTag("Candle") or object:HasTag("Lantern")))
			or object:GetAttribute("SpiritCandle") == true
			or object:GetAttribute("LeviathanGlitch") ~= nil
			or (object.Parent and object.Parent.Name == "Items")
			or name:find("candle", 1, true) or name:find("lantern", 1, true)
		if not eligible then return end
		if tracker.Bound[object] then
			tracker.Bound[object]()
			return
		end
		local previousGlitch, candleSeen
		local previousPlayed = object:GetAttribute("HasBeenPlayed")
		local function update(allowTimed)
			if not tracker.Running or not object:IsDescendantOf(World) then return end
			local glitch = object:GetAttribute("LeviathanGlitch")
			if type(glitch) == "number" and glitch > 0 and glitch ~= previousGlitch then
				Traffic("NativeGlitch", {Item = object, Token = glitch}):SendTo("Leviathan")
			end
			previousGlitch = glitch
			local played = object:GetAttribute("HasBeenPlayed")
			if allowTimed == true and previousPlayed ~= true and played == true
				and object:GetAttribute("ItemName") == "Music Box" then
				Traffic("MusicBoxFirstPlay", {MusicBox = object, Time = clock()}):SendTo("MusicBoxStun")
			end
			previousPlayed = played
			if not candleSeen and object:GetAttribute("SpiritCandle") == true then
				candleSeen = true
				Traffic("SpiritCandle", {Item = object}):SendTo("Spirit", "Doppelganger")
			end
		end
		tracker.Bound[object] = update
		if eligible and (object:IsA("Model") or object:IsA("BasePart")) then
			connect(object:GetAttributeChangedSignal("LeviathanGlitch"), update)
			connect(object:GetAttributeChangedSignal("SpiritCandle"), update)
			connect(object:GetAttributeChangedSignal("HasBeenPlayed"), function() update(true) end)
			update()
		end
	end
	for _, object in ipairs(World:GetDescendants()) do bind(object) end
	connect(World.DescendantAdded, bind)
	function tracker:Destroy()
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
		table.clear(self.Bound)
	end
	return tracker
end
