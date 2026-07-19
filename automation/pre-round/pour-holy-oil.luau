return function(dependencies: any)
	local placeTool: any = assert(dependencies.PlaceTool, "pour-holy-oil requires PlaceTool")
	return function(generation, session)
		return placeTool("Holy Oil", generation, session)
	end
end
