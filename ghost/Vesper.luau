local NAME = "Vesper"

local function createObserver()
	local destroyed = false
	return {
		OnEvent = function() return false end,
		Reset = function() end,
		Snapshot = function() return {Destroyed = destroyed, EvidenceOnly = true} end,
		Destroy = function() destroyed = true end,
	}
end

return {
	Name = NAME,
	Evidence = {"GhostWriting", "Handprints", "Wither"},
	BehaviorStatus = "EvidenceOnly",
	ObservationEvents = {},
	Perks = { ["Pretty Sure"] = {}, Maybe = {}, Idk = {"No qualified unique behavior is specified yet."} },
	CreateObserver = createObserver,
}
