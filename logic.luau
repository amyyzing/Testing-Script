if not game:IsLoaded() then game.Loaded:Wait() end

local url = "https://raw.githubusercontent.com/amyyzing/Testing-Script/refs/heads/main/loader.luau?v="
	.. tostring(os.time())
local source = game:HttpGet(url)
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local chunk, compileError = compiler(source, "@loader.luau")
assert(chunk, compileError)
return chunk()
