return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "evidence-state requires Traffic")
	local Player = assert(dependencies.Player, "evidence-state requires Player")
	local RunService = dependencies.RunService
	local Workspace = dependencies.Workspace
	local ReplicatedStorage = dependencies.ReplicatedStorage
	local Catalog = dependencies.EvidenceCatalog
	local Verdict = dependencies.Verdict
	local defer = dependencies.Defer or task and task.defer or function(callback) callback() end
	local tracker = {
		Connections = {},
		ContainerConnections = {},
		RowConnections = {},
		Pending = {},
		Journal = {},
		Automatic = {},
		Published = {},
		Displays = {},
		Details = {},
		Metrics = {},
		SubtitleBound = {},
		HighestEMF = 1,
		ScanCount = 0,
		LastEvidenceChangedAt = os.clock(),
		Destroyed = false,
	}
	local NIL = {}

	local function connect(signal, callback, list)
		if not signal then return nil end
		local connection = signal:Connect(callback)
		table.insert(list or tracker.Connections, connection)
		return connection
	end

	local function normalize(evidence)
		return Catalog and Catalog.NormalizeEvidence(evidence) or evidence
	end

	local function effectiveState(evidence)
		if tracker.Automatic[evidence] then return true end
		return tracker.Journal[evidence]
	end

	local function publishEvidence(evidence)
		evidence = normalize(evidence)
		if not evidence then return end
		local state = effectiveState(evidence)
		local stored = state == nil and NIL or state
		if tracker.Published[evidence] == stored then return end
		tracker.Published[evidence] = stored
		tracker.LastEvidenceChangedAt = os.clock()
		Traffic("EvidenceState", {
			Evidence = evidence,
			State = state,
			Source = tracker.Automatic[evidence] and "Automatic" or "Journal",
		}):SendTo("Verdict", "EvidenceLog")
	end

	local function publishMetric(key, text, state)
		local signature = tostring(text) .. "|" .. tostring(state)
		if tracker.Metrics[key] == signature then return end
		tracker.Metrics[key] = signature
		Traffic("EvidenceMetric", {Key = key, Text = text, State = state})
			:SendTo("EvidenceLog")
	end

	local function publishDetail(evidence, text)
		if tracker.Details[evidence] == text then return end
		tracker.Details[evidence] = text
		Traffic("EvidenceDetail", {Evidence = evidence, Text = text})
			:SendTo("EvidenceLog")
	end

	local function setAutomatic(evidence)
		evidence = normalize(evidence)
		if not evidence or tracker.Automatic[evidence] then return false end
		tracker.Automatic[evidence] = true
		publishEvidence(evidence)
		return true
	end

	local function evidenceContainer()
		local node = Player:FindFirstChildOfClass("PlayerGui")
		for _, name in ipairs({
			"Journal", "Holder", "Pages", "Page4", "Left", "Page", "EvidenceTypes",
		}) do
			node = node and node:FindFirstChild(name)
		end
		return node
	end

	local function controls(row)
		local container = row and row:FindFirstChild("Container") or row
		return container and container:FindFirstChild("Highlight"),
			container and container:FindFirstChild("CrossOut")
	end

	local function publishRow(row)
		if tracker.Destroyed or not row or not row.Parent
			or not tracker.RowConnections[row] then return end
		local highlight, crossOut = controls(row)
		local state
		if highlight and highlight.Visible then
			state = true
		elseif crossOut and crossOut.Visible then
			state = false
		end
		local evidence = normalize(row.Name)
		if not evidence then return end
		tracker.Journal[evidence] = state
		publishEvidence(evidence)
	end

	local function queuePublish(row)
		if tracker.Destroyed or tracker.Pending[row] then return end
		tracker.Pending[row] = true
		defer(function()
			tracker.Pending[row] = nil
			if not tracker.Destroyed then publishRow(row) end
		end)
	end

	local function bindRow(row)
		if tracker.Destroyed then return end
		local highlight, crossOut = controls(row)
		if not highlight and not crossOut then return end
		local connections = {}
		tracker.RowConnections[row] = connections
		if highlight then
			connect(highlight:GetPropertyChangedSignal("Visible"), function()
				queuePublish(row)
			end, connections)
		end
		if crossOut then
			connect(crossOut:GetPropertyChangedSignal("Visible"), function()
				queuePublish(row)
			end, connections)
		end
		queuePublish(row)
	end

	local function bindContainer(container)
		if tracker.Destroyed or tracker.Container == container then return end
		for _, connection in ipairs(tracker.ContainerConnections) do connection:Disconnect() end
		table.clear(tracker.ContainerConnections)
		for _, connections in pairs(tracker.RowConnections) do
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end
		table.clear(tracker.RowConnections)
		tracker.Container = container
		for _, row in ipairs(container:GetChildren()) do bindRow(row) end
		connect(container.ChildAdded, bindRow, tracker.ContainerConnections)
		connect(container.ChildRemoved, function(row)
			local connections = tracker.RowConnections[row]
			for _, connection in ipairs(connections or {}) do connection:Disconnect() end
			tracker.RowConnections[row] = nil
		end, tracker.ContainerConnections)
	end

	local function spiritBookHasWriting(model)
		if not model or not model:IsA("Model") then return false end
		local itemName = string.lower(tostring(model:GetAttribute("ItemName") or ""))
		local identified = itemName == "spirit book" or string.lower(model.Name) == "spirit book"
		local canvas = model:FindFirstChild("Canvas", true)
		local surface = canvas and canvas:FindFirstChild("SurfaceGui")
		local frame = surface and surface:FindFirstChild("Frame")
		local image = frame and frame:FindFirstChild("ImageLabel")
		if image and image:IsA("ImageLabel") and image.Image ~= "" then return true end
		if not identified then return false end
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("Decal") and descendant.Texture ~= "" then return true end
			if descendant:IsA("ImageLabel") and descendant.Image ~= ""
				and descendant:FindFirstAncestor("Canvas") then return true end
		end
		return false
	end

	local function inspectWorldObject(object)
		if not object or type(object.IsA) ~= "function" then return end
		if object:IsA("BasePart") then
			if object.Name == "GhostOrb" then setAutomatic("GhostOrb") end
			if object.Name == "Handprint1" or object.Name == "Handprint2"
				or object.Name == "Footprint" or object.Name == "Footprint1" then
				local saltPiles = Workspace and Workspace:FindFirstChild("SaltPiles")
				if not saltPiles or not object:IsDescendantOf(saltPiles) then
					setAutomatic("Handprints")
				end
			end
		end
	end

	local function inspectItemModel(model)
		if not model:IsA("Model") then return end
		if not tracker.Automatic.GhostWriting and spiritBookHasWriting(model) then
			setAutomatic("GhostWriting")
		end
		if model:GetAttribute("ItemName") ~= "EMF Reader" then return end
		local readingObject = model:FindFirstChild("ReadingLevel", true)
		local level
		if readingObject and (readingObject:IsA("NumberValue") or readingObject:IsA("IntValue")) then
			level = readingObject.Value
		else
			level = model:GetAttribute("ReadingLevel")
		end
		if type(level) == "number" then
			tracker.HighestEMF = math.max(tracker.HighestEMF,
				math.clamp(math.floor(level + 0.5), 1, 5))
		end
	end

	local function scanItems()
		local checked = setmetatable({}, {__mode = "k"})
		local worldItems = Workspace and Workspace:FindFirstChild("Items")
		for _, container in ipairs({
			worldItems,
			Player:FindFirstChild("ToolsHolder"),
			Player.Character,
		}) do
			if container then
				for _, object in ipairs(container:GetDescendants()) do
					if container == worldItems and object:IsA("BasePart")
						and object.Name == "Flower_Petals" then
						local color = object.Color
						if color and color.R <= 0.03 and color.G <= 0.03 and color.B <= 0.03 then
							setAutomatic("Wither")
						end
					end
					if object:IsA("Model") and not checked[object] then
						checked[object] = true
						inspectItemModel(object)
					end
				end
			end
		end
		if tracker.HighestEMF >= 5 then setAutomatic("EMFLevel5") end
		publishDetail("EMFLevel5", "EMF-" .. tostring(tracker.HighestEMF))
	end

	local function scanTemperature()
		local map = Workspace and Workspace:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if rooms then
			for _, room in ipairs(rooms:GetChildren()) do
				local temperature = room:GetAttribute("Temperature")
				if type(temperature) == "number" then
					tracker.LowestTemperature = math.min(
						tracker.LowestTemperature or temperature, temperature)
				end
			end
		end
		if tracker.LowestTemperature then
			if tracker.LowestTemperature < 0 then setAutomatic("FreezingTemperatures") end
			publishDetail("FreezingTemperatures", "Lowest Temperature: "
				.. string.format("%.1f°C", tracker.LowestTemperature))
		end
	end

	local function publishDisplays()
		if not Catalog or not Verdict then return end
		local candidates = {}
		for index, name in ipairs(Verdict.Lists) do
			if not table.find(Verdict.RuledOut, index) and Verdict:IsCompatible(name) then
				table.insert(candidates, name)
			end
		end
		if #candidates == 0 then
			for _, name in ipairs(Verdict.Lists) do
				if Verdict:IsCompatible(name) then table.insert(candidates, name) end
			end
		end
		for _, evidence in ipairs(Catalog.EvidenceOrder) do
			local impossible = effectiveState(evidence) == nil
			for _, ghostName in ipairs(candidates) do
				if Catalog.SupportsEvidence(ghostName, evidence, {IncludeFalseEvidence = true}) then
					impossible = false
					break
				end
			end
			if tracker.Displays[evidence] ~= impossible then
				tracker.Displays[evidence] = impossible
				Traffic("EvidenceDisplay", {Evidence = evidence, Impossible = impossible})
					:SendTo("EvidenceLog")
			end
		end
	end

	local function publishRoundInfo(ghost)
		local favourite = ghost and ghost:GetAttribute("FavoriteRoom")
		publishMetric("FavouriteRoom", favourite and tostring(favourite) ~= ""
			and "Favourite Room: " .. tostring(favourite) or "Favourite Room: ...")
		local selected = Verdict and Verdict.Selected[1]
		local ghostName = selected and Verdict.Lists[selected]
		if not ghostName then
			publishMetric("Ghost", "Ghost: Unknown (Idk)")
			return
		end
		local resolved = Verdict.GetEvidenceResolvedGhost and Verdict:GetEvidenceResolvedGhost()
		local score = math.max(0, (Verdict.Confidence[selected] or 0)
			- (Verdict.NegativeConfidence[selected] or 0))
		local tier = resolved == ghostName and "Certain"
			or Catalog and select(2, Catalog.ConfidenceTier(score)) or "Idk"
		publishMetric("Ghost", "Ghost: " .. ghostName .. " (" .. tier .. ")",
			tier == "Certain" or tier == "Pretty Sure")
	end

	local function scanAutomatic()
		if not Workspace then return end
		local ghost = dependencies.Ghost or Workspace:FindFirstChild("Ghost")
		if ghost and ghost:GetAttribute("InLaser") == true then setAutomatic("LaserProjector") end
		scanItems()
		scanTemperature()
		publishDisplays()
		publishRoundInfo(ghost)
		tracker.ScanCount += 1
	end

	local function rebuildVoiceIndex()
		tracker.VoiceSubtitles = tracker.VoiceSubtitles or {}
		table.clear(tracker.VoiceSubtitles)
		local assets = ReplicatedStorage and ReplicatedStorage:FindFirstChild("Assets")
		local voices = assets and assets:FindFirstChild("SpiritBoxVoices")
		if not voices then return end
		for _, object in ipairs(voices:GetDescendants()) do
			if object:IsA("Sound") and type(object:GetAttribute("Subtitle")) == "string" then
				local text = string.lower(object:GetAttribute("Subtitle")):gsub("%s+", "")
				if text ~= "" then tracker.VoiceSubtitles[text] = true end
			end
		end
	end

	local function onSubtitle(text)
		if type(text) ~= "string" then return end
		if not tracker.VoiceSubtitles or next(tracker.VoiceSubtitles) == nil then
			rebuildVoiceIndex()
		end
		local key = string.lower(text):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "")
		if tracker.VoiceSubtitles and tracker.VoiceSubtitles[key] then
			setAutomatic("SpiritBox")
		end
	end

	local function bindSubtitle(connector)
		if not connector or tracker.SubtitleBound[connector] then return end
		local ok, connection = pcall(function()
			if type(connector) == "function" then return connector(onSubtitle) end
			return connector.Connect(onSubtitle)
		end)
		if ok and connection then
			tracker.SubtitleBound[connector] = true
			table.insert(tracker.Connections, connection)
		end
	end

	function tracker:Refresh()
		if self.Destroyed then return false end
		local container = evidenceContainer()
		if container then bindContainer(container) end
		bindSubtitle(dependencies.ShowSubtitle)
		bindSubtitle(dependencies.LocalShowSubtitle)
		scanAutomatic()
		return container ~= nil
	end

	function tracker:IsSettled(seconds)
		return self.ScanCount >= 2
			and os.clock() - self.LastEvidenceChangedAt >= (tonumber(seconds) or 2)
	end

	function tracker:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		for _, connection in ipairs(self.ContainerConnections) do connection:Disconnect() end
		for _, connections in pairs(self.RowConnections) do
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end
		table.clear(self.Connections)
		table.clear(self.ContainerConnections)
		table.clear(self.RowConnections)
	end

	if Workspace then
		for _, object in ipairs(Workspace:GetDescendants()) do inspectWorldObject(object) end
		connect(Workspace.DescendantAdded, inspectWorldObject)
	end
	tracker:Refresh()
	if RunService and RunService.Heartbeat then
		local elapsed = 0
		connect(RunService.Heartbeat, function(delta)
			elapsed += math.max(0, tonumber(delta) or 0)
			if elapsed < 1 then return end
			elapsed = 0
			tracker:Refresh()
		end)
	end
	return tracker
end
