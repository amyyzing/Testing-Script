local createBright = require("../bright")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local originalAmbient, originalOutdoor, white = {}, {}, {}
local lighting = {
	Ambient = originalAmbient,
	OutdoorAmbient = originalOutdoor,
	Brightness = 1,
	GlobalShadows = true,
	FogEnd = 1000,
}
local controller = createBright({Lighting = lighting, White = white})

expect(controller:Toggle() == true, "first toggle should enable full bright")
expect(lighting.Ambient == white and lighting.OutdoorAmbient == white, "ambient should become white")
expect(lighting.Brightness == 3 and lighting.GlobalShadows == false and lighting.FogEnd == 100000,
	"full bright values should match the original behavior")

controller:Destroy()
expect(lighting.Ambient == originalAmbient and lighting.OutdoorAmbient == originalOutdoor,
	"destroy should restore original ambient values")
expect(lighting.Brightness == 1 and lighting.GlobalShadows == true and lighting.FogEnd == 1000,
	"destroy should restore every original lighting value")

print("bright.spec: toggle and original lighting restoration passed")
