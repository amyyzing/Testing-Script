param([string] $Luau = "luau")
$ErrorActionPreference = "Stop"
$loader = Get-Content (Join-Path $PSScriptRoot "../../loader.luau") -Raw
$parts = $loader -split 'local function initialize\(\)', 2
$footer = ($parts[1] -split 'end -- initialize', 2)[1]
$setup = @'
local environment, calls, armed = {}, 0, 0
local game = {IsLoaded = function() return true end}
local function getgenv() return environment end
local task = {wait = function() coroutine.yield() end}
local initializer = function()
 calls += 1
 coroutine.yield()
 return {Destroyed = false, MCPResume = {Arm = function() armed += 1 end}}
end
local function runLoader()
'@
$checks = @'
end
local first = coroutine.create(runLoader)
local duplicate = coroutine.create(runLoader)
assert(coroutine.resume(first) and calls == 1)
assert(coroutine.resume(duplicate) and calls == 1, "concurrent loader must wait for its owner")
local ok, session = coroutine.resume(first)
assert(ok and session.Ready)
local joined, same = coroutine.resume(duplicate)
assert(joined and same == session and calls == 1, "both callers must receive the same ready session")
assert(runLoader() == session and calls == 1 and armed == 1, "re-execution must reuse the current session")
initializer = function() calls += 1 return {Destroyed = false} end
environment.DemonologyForceReload = true
assert(runLoader() ~= session and calls == 2, "explicit refresh must remain possible")
initializer = function() error("fixture initialization failed") end
environment.DemonologyForceReload = true
assert(not pcall(runLoader) and environment.DemonologyStartup.Loading == false,
 "failed initialization must release the startup lock")
initializer = function() calls += 1 return {Destroyed = false} end
assert(runLoader().Ready and calls == 3, "failed initialization must remain retryable")
print("loader-startup.spec: concurrent startup, reuse, explicit refresh and failed retry passed")
'@
$source = $setup + "`n" + $parts[0] + "`nlocal function initialize() return initializer() end -- initialize`n" + $footer + "`n" + $checks
$file = Join-Path $env:TEMP "demonology-startup-$([guid]::NewGuid()).luau"
try {
 [IO.File]::WriteAllText($file, $source)
 & $Luau $file
 if ($LASTEXITCODE -ne 0) { throw "Loader startup regression failed" }
} finally { Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue }
