local SOURCE = "https://demonology.fandom.com/wiki/Dybbuk"

local function createObserver(api)
	local state = {
		Qualified = false,
		CompletedNoIncreaseHunt = false,
		LastReason = nil,
	}
	local observer = {}

	function observer:Reset()
		state.Qualified = false
		state.CompletedNoIncreaseHunt = false
		state.LastReason = nil
	end

	function observer:OnDullahanEvaluation(event)
		if type(event) ~= "table" then
			return
		end
		state.CompletedNoIncreaseHunt = event.CompletedNoIncreaseHunt == true
	end

	function observer:OnResidualEvidence(event)
		if type(event) ~= "table" then
			return
		end
		local evidenceQualified = event.Qualified
		if type(evidenceQualified) ~= "boolean" then
			evidenceQualified = event.Freezing == true
				and event.Wither == true
				and event.LidarVisible == true
		end
		local blockedBySpecificPattern = api:GetDetection("Dullahan") ~= nil
			or api:GetDetection("Vex") ~= nil
		state.Qualified = evidenceQualified
			and state.CompletedNoIncreaseHunt
			and not blockedBySpecificPattern
		state.LastReason = event.Reason
		if state.Qualified then
			api:Detect(
				"Dybbuk",
				event.Reason
					or "Freezing and Wither were observed, the ghost appeared on LIDAR, and a completed hunt lacked Dullahan-style speed steps",
				60,
				event.Source
			)
		else
			api:ClearDetection("Dybbuk")
		end
		api:Refresh()
	end

	function observer:Snapshot()
		return {
			Qualified = state.Qualified,
			CompletedNoIncreaseHunt = state.CompletedNoIncreaseHunt,
			LastReason = state.LastReason,
		}
	end

	return observer
end

return {
	Name = "Dybbuk",
	Evidence = {"FreezingTemperatures", "Handprints", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 60,
	TTL = 120,
	ObservationKeys = {"LidarDullahanExclusion"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "The first Music Box play visibly stuns it for about three seconds.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
				Conditions = "The Music Box is not guaranteed to spawn and is absent on Nightmare difficulty.",
			},
		},
		["Maybe"] = {
			{
				Text = "A corpse was directly observed being thrown.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "A corpse was merely found displaced; ordinary physics can move bodies.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
