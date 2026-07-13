local StaticGhostFacts = {}
StaticGhostFacts.__index = StaticGhostFacts

local FEMALE_MODELS = {Abaddon = true, Leech = true, Rattle = true, Watcher = true}

local function replicatedValue(ghost, valueName)
	if type(ghost.GetAttribute) == "function" then
		local direct = ghost:GetAttribute(valueName)
		if direct ~= nil then return direct end
	end
	if type(ghost.GetDescendants) == "function" then
		for _, descendant in ipairs(ghost:GetDescendants()) do
			if type(descendant.GetAttribute) == "function" then
				local attribute = descendant:GetAttribute(valueName)
				if attribute ~= nil then return attribute end
			end
			if descendant.Name == valueName
				and type(descendant.IsA) == "function"
				and descendant:IsA("ValueBase") then
				return descendant.Value
			end
		end
	end
	return nil
end

local function defaultFacts(ghost)
	local facts = {
		Name = ghost.Name,
		ClassName = ghost.ClassName,
	}
	if type(ghost.GetAttributes) == "function" then
		facts.Attributes = ghost:GetAttributes()
	end
	if type(ghost.FindFirstChild) == "function" then
		local root = ghost:FindFirstChild("HumanoidRootPart")
		facts.HasHumanoidRootPart = root ~= nil
		facts.RootSoundNames = {}
		if root and type(root.GetChildren) == "function" then
			for _, child in ipairs(root:GetChildren()) do
				if child.ClassName == "Sound" or type(child.IsA) == "function" and child:IsA("Sound") then
					table.insert(facts.RootSoundNames, child.Name)
				end
			end
		end
	end
	local attributes = facts.Attributes or {}
	local lidarValue = replicatedValue(ghost, "InvisibleOnLIDAR")
	facts.LidarExists = lidarValue == true
	facts.LidarValue = lidarValue
	facts.VisualModel = attributes.VisualModel
	facts.Sex = attributes.Sex or attributes.Gender
	if facts.Sex == nil and type(facts.VisualModel) == "string" and facts.VisualModel ~= "" then
		facts.Sex = FEMALE_MODELS[facts.VisualModel] and "Female" or "Male"
	end
	return facts
end

function StaticGhostFacts.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "StaticGhostFacts",
		Category = "Discardable",
		Status = "Idle",
		ReadFacts = options.ReadFacts or defaultFacts,
		_context = nil,
		_result = nil,
		_error = nil,
	}, StaticGhostFacts)
end

StaticGhostFacts.New = StaticGhostFacts.new

function StaticGhostFacts:Start(context)
	if self.Status == "Discarded" then
		return
	end
	self._context = context or {}
	self.Status = "Running"
	local ghost = assert(self._context.GhostModel, "StaticGhostFacts requires the fixed GhostModel")
	local ok, result = pcall(self.ReadFacts, ghost, self._context)
	if not ok then
		self._error = tostring(result)
		self.Status = "Failed"
		return
	end
	self._result = result
	if type(self._context.Emit) == "function" then
		self._context.Emit({
			Type = "StaticGhostFacts",
			Source = self.Name,
			Payload = result,
		})
		local hasOtherSound = false
		for _, soundName in ipairs(type(result.RootSoundNames) == "table" and result.RootSoundNames or {}) do
			if soundName ~= "Hunting" then
				hasOtherSound = true
				break
			end
		end
		if result.HasHumanoidRootPart == true then
			self._context.Emit({
				Type = "RootSoundScan",
				Source = self.Name,
				Payload = {
					Qualified = true,
					HasOtherSound = hasOtherSound,
					SoundNames = result.RootSoundNames,
				},
			})
		end
		if type(result.LidarExists) == "boolean" then
			self._context.Emit({
				Type = "LidarState",
				Source = self.Name,
				Payload = {Qualified = true, Exists = result.LidarExists},
			})
		end
		if result.Sex == "Female" or result.Sex == "Male" then
			self._context.Emit({
				Type = "GhostModelSex",
				Source = self.Name,
				Payload = {Qualified = true, Sex = result.Sex},
			})
		end
	end
	self.Status = "Discarded"
end

function StaticGhostFacts:OnEvent() end

function StaticGhostFacts:Stop()
	if self.Status ~= "Discarded" then
		self.Status = "Stopped"
	end
end

function StaticGhostFacts:Reset()
	self._result = nil
	self._error = nil
	self.Status = "Idle"
end

function StaticGhostFacts:Destroy()
	self._context = nil
	self.Status = "Destroyed"
end

function StaticGhostFacts:Snapshot()
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		Result = self._result,
		Error = self._error,
	}
end

return StaticGhostFacts
