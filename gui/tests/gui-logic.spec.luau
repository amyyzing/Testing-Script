local GuiLogic = require("../gui-logic")

local patternDrawer, evidenceDrawer = {}, {}
local drawers = GuiLogic.DrawerList(patternDrawer, evidenceDrawer)

assert(#drawers == 2, "drawer list must contain exactly two entries")
assert(drawers[1] == patternDrawer, "pattern drawer must remain first")
assert(drawers[2] == evidenceDrawer, "evidence drawer must remain second")
assert(type(drawers[2]) == "table", "assert message must not leak into the drawer list")

local opens = GuiLogic.DrawerOpensAfterGesture
assert(opens(false, false, 0, 0), "a click should open a closed drawer")
assert(not opens(true, false, 1, 1), "a click should close an open drawer")
assert(not opens(false, true, 0, 0.24), "a short drag should leave the drawer closed")
assert(opens(false, true, 0, 0.25), "the opening drag threshold should still apply")
assert(not opens(true, true, 1, 0.75), "the closing drag threshold should still apply")

print("gui-logic.spec: drawer list and click/drag behavior passed")
