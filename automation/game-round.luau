return function(dependencies: any)
	local createPreRound: any = assert(
		dependencies.CreatePreRound,
		"round-automation requires CreatePreRound"
	)
	local createRound: any = assert(
		dependencies.CreateRound,
		"round-automation requires CreateRound"
	)
	local createPostRound: any = assert(
		dependencies.CreatePostRound,
		"round-automation requires CreatePostRound"
	)
	local pre = createPreRound(dependencies)
	local post = createPostRound({
		Dependencies = dependencies,
		Pre = pre,
	})
	return createRound({
		Dependencies = dependencies,
		Pre = pre,
		Post = post,
	})
end
