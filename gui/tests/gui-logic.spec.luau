local GuiLogic = require("../gui-logic")

local patternDrawer, speedDrawer = {}, {}
local drawers = GuiLogic.DrawerList(patternDrawer, speedDrawer)

assert(#drawers == 2, "drawer list must contain exactly two entries")
assert(drawers[1] == patternDrawer, "pattern drawer must remain first")
assert(drawers[2] == speedDrawer, "speed drawer must remain second")
assert(type(drawers[2]) == "table", "assert message must not leak into the drawer list")

print("gui-logic.spec: drawer list contains no assert multi-return residue")
