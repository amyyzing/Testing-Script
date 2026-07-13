-- Ordered lifecycle and event dispatcher for per-ghost observers.
-- Ghost definitions own their policies; this module only coordinates them.

return function(dependencies)
	dependencies = dependencies or {}

	local definitions = assert(
		dependencies.Definitions,
		"ghost/runtime.luau requires Definitions"
	)
	local api = assert(dependencies.Api, "ghost/runtime.luau requires Api")
	local onAction = assert(
		dependencies.OnAction,
		"ghost/runtime.luau requires OnAction"
	)
	local onError = dependencies.OnError

	assert(type(definitions) == "table", "Definitions must be a table")
	assert(type(api) == "table", "Api must be a table")
	assert(type(onAction) == "function", "OnAction must be a function")
	assert(onError == nil or type(onError) == "function", "OnError must be a function")

	local observers = {}
	local observersByName = {}
	local definitionNames = {}
	local destroyed = false
	local mode = dependencies.Mode
	local previousEmit = rawget(api, "Emit")
	local runtimeEmit

	local function tracebackError(message)
		return debug.traceback(tostring(message), 2)
	end

	local function reportError(message, context)
		if not onError then
			error(message, 0)
		end

		local ok, callbackError = xpcall(function()
			onError(message, context)
		end, tracebackError)
		if not ok then
			error(callbackError, 0)
		end
	end

	local function emitAction(action)
		if action == nil then
			return nil
		end
		return onAction(action)
	end

	runtimeEmit = function(selfOrAction, action)
		if action == nil and selfOrAction ~= api then
			action = selfOrAction
		end
		return emitAction(action)
	end
	api.Emit = runtimeEmit

	local function routeResult(result)
		if result == nil then
			return
		end

		if type(result) == "table"
			and (rawget(result, 1) ~= nil or next(result) == nil) then
			for _, action in ipairs(result) do
				emitAction(action)
			end
			return
		end

		emitAction(result)
	end

	local function invoke(entry, hook, event, routeActions)
		local handler = entry.Observer[hook]
		if type(handler) ~= "function" then
			return nil, false
		end

		local result
		local ok, handlerError = xpcall(function()
			result = handler(entry.Observer, event)
			if routeActions ~= false then
				routeResult(result)
			end
		end, tracebackError)
		if not ok then
			reportError(handlerError, {
				Definition = entry.Definition,
				Ghost = entry.Name,
				Hook = hook,
				Observer = entry.Observer,
			})
			return nil, true
		end

		return result, true
	end

	for index, definition in ipairs(definitions) do
		assert(type(definition) == "table", "Definitions entries must be tables")
		local name = definition.Name
		assert(
			type(name) == "string" and name ~= "",
			"Definitions entries require a non-empty Name"
		)
		assert(not definitionNames[name], "duplicate ghost definition: " .. name)
		definitionNames[name] = true

		local createObserver = definition.CreateObserver
		if createObserver ~= nil then
			assert(
				type(createObserver) == "function",
				"CreateObserver must be a function for " .. name
			)

			local observer
			local ok, createError = xpcall(function()
				observer = createObserver(api)
			end, tracebackError)
			if not ok then
				reportError(createError, {
					Definition = definition,
					Ghost = name,
					Hook = "CreateObserver",
					Index = index,
				})
			elseif observer ~= nil and type(observer) ~= "table" then
				reportError("CreateObserver must return a table for " .. name, {
					Definition = definition,
					Ghost = name,
					Hook = "CreateObserver",
					Index = index,
				})
			elseif observer ~= nil then
				local entry = {
					Definition = definition,
					Name = name,
					Observer = observer,
				}
				table.insert(observers, entry)
				observersByName[name] = observer
			end
		end
	end

	local Runtime = {}
	Runtime.__index = Runtime

	function Runtime:Reset(options)
		if destroyed then
			return false
		end
		for _, entry in ipairs(observers) do
			invoke(entry, "Reset", options, true)
		end
		return true
	end

	function Runtime:Dispatch(hook, event)
		if destroyed then
			return false
		end
		assert(type(hook) == "string" and hook ~= "", "Dispatch requires a hook name")
		for _, entry in ipairs(observers) do
			invoke(entry, hook, event, true)
		end
		return true
	end

	function Runtime:Tick(event)
		return self:Dispatch("Tick", event)
	end

	function Runtime:GetObserver(name)
		return observersByName[name]
	end

	function Runtime:SetMode(nextMode)
		if destroyed then
			return false
		end
		mode = nextMode
		for _, entry in ipairs(observers) do
			invoke(entry, "SetMode", nextMode, true)
		end
		return true
	end

	local function copySnapshot(value, seen)
		if type(value) ~= "table" then
			return value
		end
		seen = seen or {}
		if seen[value] then
			return seen[value]
		end
		local copy = {}
		seen[value] = copy
		for key, nestedValue in pairs(value) do
			copy[copySnapshot(key, seen)] = copySnapshot(nestedValue, seen)
		end
		return copy
	end

	function Runtime:Snapshot()
		local snapshot = {
			Mode = mode,
			Observers = {},
		}
		for _, entry in ipairs(observers) do
			local state, implemented = invoke(entry, "Snapshot", nil, false)
			if implemented and state ~= nil then
				snapshot.Observers[entry.Name] = copySnapshot(state)
			end
		end
		return snapshot
	end

	function Runtime:Destroy()
		if destroyed then
			return false
		end
		destroyed = true
		for _, entry in ipairs(observers) do
			invoke(entry, "Destroy", nil, true)
		end
		if rawget(api, "Emit") == runtimeEmit then
			api.Emit = previousEmit
		end
		table.clear(observers)
		table.clear(observersByName)
		return true
	end

	return setmetatable({}, Runtime)
end
