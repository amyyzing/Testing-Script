return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "favourite-hunt-room requires Traffic")
	local Ghost = assert(dependencies.Ghost, "favourite-hunt-room requires Ghost")
	local readCurrentRoom = dependencies.ReadCurrentRoom
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Hunting = Ghost:GetAttribute("Hunting") == true,
	}

	local function token(value)
		if value and value.Name then value = value.Name end
		return string.lower(tostring(value or ""):gsub("[^%w]", ""))
	end

	local function currentRoom()
		if readCurrentRoom then return readCurrentRoom(true) end
		return Ghost:GetAttribute("CurrentRoom")
	end

	local function favouriteRoom()
		return Ghost:GetAttribute("FavoriteRoom")
			or Ghost:GetAttribute("FavouriteRoom")
	end

	Tracker.Disconnect = Traffic:Receive("FavouriteHuntRoom", function(signal, payload)
		if signal ~= "HuntingState" or type(payload) ~= "table" then return end
		local hunting = payload.Hunting == true
		if hunting == Tracker.Hunting then return end
		Tracker.Hunting = hunting
		if not hunting then return end
		local room, favourite = currentRoom(), favouriteRoom()
		local roomToken, favouriteToken = token(room), token(favourite)
		if roomToken == "" or favouriteToken == "" then return end
		Traffic("FavouriteHuntRoom", {
			InFavourite = roomToken == favouriteToken,
			Room = room,
			FavouriteRoom = favourite,
			Time = payload.Time,
		}):SendTo("Wisp")
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
	end

	return Tracker
end
