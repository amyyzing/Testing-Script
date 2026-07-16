local GuiLogic = require("../gui-logic")

local patternDrawer, flickerDrawer = {}, {}
local drawers = GuiLogic.DrawerList(patternDrawer, flickerDrawer)

assert(#drawers == 2, "drawer list must contain exactly two entries")
assert(drawers[1] == patternDrawer, "pattern drawer must remain first")
assert(drawers[2] == flickerDrawer, "flicker drawer must remain second")
assert(type(drawers[2]) == "table", "assert message must not leak into the drawer list")

print("gui-logic.spec: drawer list contains no assert multi-return residue")
