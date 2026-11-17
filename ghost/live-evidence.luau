return function(dependencies)
	local Catalog = assert(dependencies.Catalog, "live-evidence requires Catalog")
	local Storage = assert(dependencies.ReplicatedStorage, "live-evidence requires ReplicatedStorage")
	local load = dependencies.Require or require
	local result = {Updated = {}, Skipped = {}}
	local modules = Storage:FindFirstChild("Modules")
	local types = modules and modules:FindFirstChild("GhostTypes")
	local evidenceModule = modules and modules:FindFirstChild("EvidenceTypes")
	if not types or not evidenceModule then return result end
	local ok, definitions = pcall(load, evidenceModule)
	if not ok or type(definitions) ~= "table" then return result end
	local keys = {}
	for name, value in pairs(definitions) do
		local key = Catalog.NormalizeEvidence(name)
		if key and (type(value) == "number" or type(value) == "string") then keys[value] = key end
	end
	for _, profile in ipairs(Catalog.Profiles) do
		local module = types:FindFirstChild(profile.Name)
		local loaded, native = false, nil
		if module and module:IsA("ModuleScript") then loaded, native = pcall(load, module) end
		local evidence, set, display = {}, {}, {}
		local valid = loaded and type(native) == "table" and type(native.Evidence) == "table"
		if valid then
			for _, value in ipairs(native.Evidence) do
				local key = keys[value] or Catalog.NormalizeEvidence(value)
				if not key or set[key] then valid = false break end
				set[key] = true
				table.insert(evidence, key)
				table.insert(display, Catalog.Evidence[key].DisplayName)
			end
		end
		if valid and #evidence == 3 then
			profile.Evidence, profile.EvidenceSet = evidence, set
			profile.EvidenceDisplay, profile.DisplayEvidence = display, display
			profile.SourceStatus = "live-game"
			table.insert(result.Updated, profile.Name)
		else
			table.insert(result.Skipped, profile.Name)
		end
	end
	return result
end
