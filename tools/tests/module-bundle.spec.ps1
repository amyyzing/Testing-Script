param([string] $Luau = "luau")

$ErrorActionPreference = "Stop"
$bundlePath = Join-Path $PSScriptRoot "../../dist/modules.luau"
$bundle = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $bundlePath).Path)
$setup = @'
local Color3 = {
	fromRGB = function(red, green, blue)
		return {R = red / 255, G = green / 255, B = blue / 255}
	end,
}
local bundle = (function()
'@
$checks = @'
end)()
assert(bundle.__compiled == true, "bundle should contain initialized modules")
assert(type(bundle["logic/movement.luau"]) == "function", "movement module missing")
assert(type(bundle["ghost/verdict.luau"]) == "function", "verdict module missing")
assert(bundle.__nil ~= nil, "nil module sentinel missing")
assert(type(bundle["ghost/ghosts/Banshee.luau"]) == "table", "Banshee processor missing")
assert(type(bundle["ghost/ghosts/Dybbuk.luau"]) == "table", "Dybbuk processor missing")
assert(type(bundle["ghost/dormant-trackers/music-box-stun.luau"]) == "function", "Music Box tracker missing")
assert(bundle["ghost/ghosts/Nightmare.luau"] == bundle.__nil, "nil module was not bundled")
print("module-bundle.spec: compiled bundle passed")
'@

$testPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "demonology-bundle-$([guid]::NewGuid()).luau")
try {
	# Module-scoped globals in standalone Luau do not flow through require.
	[System.IO.File]::WriteAllText($testPath, $setup + "`n" + $bundle + "`n" + $checks)
	& $Luau $testPath
	if ($LASTEXITCODE -ne 0) { throw "Bundle test failed with exit code $LASTEXITCODE" }
} finally {
	Remove-Item -LiteralPath $testPath -ErrorAction SilentlyContinue
}
