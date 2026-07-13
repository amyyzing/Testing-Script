local SOURCE = "https://demonology.fandom.com/wiki/The_Wisp"

return {
	Name = "Wisp",
	DisplayName = "The Wisp",
	Aliases = {"The Wisp", "Will-o-the-Wisp", "Will o the Wisp"},
	Evidence = {"GhostOrb", "LaserProjector", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 35,
	TTL = 120,
	ObservationKeys = {"HolyOilGhostWall", "OffFavouriteRoomHunt"},
	CreateObserver = function(api)
		local observer = {}
		local mismatchKey
		local mismatchSince
		local mismatchSamples = 0
		local negativeRecordedThisHunt = false

		local function resetMismatch()
			mismatchKey = nil
			mismatchSince = nil
			mismatchSamples = 0
		end

		function observer:Reset()
			resetMismatch()
			negativeRecordedThisHunt = false
		end

		function observer:OnHuntStarted()
			resetMismatch()
			negativeRecordedThisHunt = false
		end

		function observer:OnHuntEnded()
			resetMismatch()
		end

		function observer:OnRoomPresence(event)
			event = type(event) == "table" and event or {}
			if event.Hunting ~= true or negativeRecordedThisHunt then
				resetMismatch()
				return
			end
			local favourite = tostring(event.FavouriteRoom or "")
			local current = tostring(event.CurrentRoom or "")
			if favourite == "" or current == ""
				or string.lower(favourite) == string.lower(current)
				or event.CurrentRoomContainsGhost ~= true
				or event.FavouriteRoomContainsGhost == true then
				resetMismatch()
				return
			end
			local key = string.lower(favourite) .. "\0" .. string.lower(current)
			local now = tonumber(event.Time) or os.clock()
			if mismatchKey ~= key then
				mismatchKey = key
				mismatchSince = now
				mismatchSamples = 1
				return
			end
			mismatchSamples = mismatchSamples + 1
			if mismatchSamples >= 4 and now - (mismatchSince or now) >= 0.3 then
				negativeRecordedThisHunt = true
				resetMismatch()
				self:OnOffFavouriteHunt({
					Confirmed = true,
					CurrentRoom = current,
					FavouriteRoom = favourite,
					Source = event.Source,
				})
			end
		end

		function observer:OnHolyOilObservation(event)
			event = type(event) == "table" and event or {}
			if event.Hunting ~= true then
				return
			end
			local eligibleCount = tonumber(event.EligibleWallCount)
			local nonCollidableCount = tonumber(event.NonCollidableWallCount)
			if eligibleCount == nil and type(event.WallCanCollide) == "boolean" then
				eligibleCount = 1
				nonCollidableCount = event.WallCanCollide and 0 or 1
			end
			if (nonCollidableCount or 0) > 0 then
				self:OnHolyOilWall({
					Outcome = "PassThrough",
					Source = event.Source,
				})
			elseif (eligibleCount or 0) > 0 then
				self:OnHolyOilWall({
					Outcome = "Blocked",
					Source = event.Source,
				})
			end
		end

		function observer:OnHolyOilWall(event)
			event = event or {}
			if event.Outcome == "PassThrough" then
				api:ClearRuleOut("Wisp")
				api:Detect(
					"Wisp",
					event.Reason
						or "while the ghost was hunting and HolyOil was Burning, that model's GhostWall.CanCollide was false",
					99
				)
			elseif event.Outcome == "Blocked" then
				api:ClearDetection("Wisp")
				api:RuleOut(
					"Wisp",
					event.Reason
						or "while the ghost was hunting and HolyOil was Burning, every eligible GhostWall remained collidable",
					99
				)
			else
				return
			end
			api:Refresh()
		end

		function observer:OnOffFavouriteHunt(event)
			event = event or {}
			if event.Confirmed ~= true then
				return
			end
			local detection = api:GetDetection("Wisp")
			local confidence = if type(detection) == "table"
				then tonumber(detection.Confidence) or 0
				else tonumber(detection) or 0
			if confidence >= 99 then
				return
			end

			local reason = event.Reason
			if not reason and event.CurrentRoom and event.FavouriteRoom then
				reason = "during a hunt, the ghost was verified in "
					.. tostring(event.CurrentRoom)
					.. " instead of favourite room "
					.. tostring(event.FavouriteRoom)
			end
			api:ClearDetection("Wisp")
			api:RuleOut(
				"Wisp",
				reason
					or "during a hunt, the ghost was verified outside its favourite room",
				95
			)
			api:Refresh()
		end

		function observer:Snapshot()
			return {
				MismatchKey = mismatchKey,
				MismatchSince = mismatchSince,
				MismatchSamples = mismatchSamples,
				NegativeRecordedThisHunt = negativeRecordedThisHunt,
			}
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "It crosses ignited Holy Oil and visibly catches fire; a mimicking Skinwalker does not ignite.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "It lights an unlit candle or walks through a line of fire, both of which Skinwalker may mimic.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "Hunts only seemed to start in the favorite room; that room can change on higher difficulty.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
	},
}
