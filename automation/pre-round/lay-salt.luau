return function(dependencies: any)
	local placeTool: any = assert(dependencies.PlaceTool, "lay-salt requires PlaceTool")
	return function(generation, session)
		return placeTool("Salt Canister", generation, session)
	end
end
