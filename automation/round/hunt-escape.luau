return function(dependencies: any)
	local world: any = assert(dependencies.Workspace, "hunt-escape requires Workspace")
	local state: any = assert(dependencies.State, "hunt-escape requires State")
	local getGhost: any = assert(dependencies.GetGhost, "hunt-escape requires GetGhost")
	local operationActive: any = assert(dependencies.OperationActive, "hunt-escape requires OperationActive")
	local setStatus: any = assert(dependencies.SetStatus, "hunt-escape requires SetStatus")
	local teleportToBase: any = assert(dependencies.TeleportToBase, "hunt-escape requires TeleportToBase")
	local fastTeleportToBase: any = dependencies.FastTeleportToBase
	local teleportOptions: any = assert(dependencies.TeleportOptions, "hunt-escape requires TeleportOptions")
	local playerInsideBase: any = assert(dependencies.PlayerInsideBase, "hunt-escape requires PlayerInsideBase")
	local wait: any = assert(dependencies.Wait, "hunt-escape requires Wait")
	local retryMin = tonumber(dependencies.RetryMin) or 0.25
	local retryMax = tonumber(dependencies.RetryMax) or 2

	return function(generation)
		local escaped = false
		local failures = 0
		local nextAttemptAt = 0
		while operationActive(generation) do
			if world:FindFirstChild("Map") ~= state.roundMap then
				error("the round map changed", 0)
			end
			local ghost = getGhost()
			if ghost and ghost ~= state.roundGhost then
				error("the round ghost changed", 0)
			end
			if ghost and ghost:GetAttribute("Hunting") ~= true then break end
			state.questionsActive = false
			setStatus(ghost and "Hunt escape" or "Waiting for ghost")
			if not escaped and os.clock() >= nextAttemptAt then
				if type(fastTeleportToBase) == "function" then
					escaped = fastTeleportToBase() == true and playerInsideBase()
				end
				if not escaped then
					escaped = teleportToBase(teleportOptions(generation)) == true
						and playerInsideBase()
				end
				if not escaped then
					failures += 1
					nextAttemptAt = os.clock() + math.min(retryMax,
						retryMin * (2 ^ math.min(failures - 1, 3)))
				end
			end
			wait(generation, 0.15)
		end
		if escaped then wait(generation, 0.65) end
		return escaped
	end
end
