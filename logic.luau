if not game:IsLoaded() then game.Loaded:Wait() end

local url = "https://raw.githubusercontent.com/amyyzing/Testing-Script/refs/heads/main/loader.luau?v="
	.. tostring(os.time())
local function fetch()
	local failure
	for attempt = 1, 3 do
		local ok, result = pcall(game.HttpGet, game, url)
		if ok and type(result) == "string" and result ~= "" then return result end
		failure = result
		if attempt < 3 then task.wait(attempt) end
	end
	error("Could not download loader.luau: " .. tostring(failure), 0)
end
local source = fetch()
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local chunk, compileError = compiler(source, "@loader.luau")
assert(chunk, compileError)
return chunk()
