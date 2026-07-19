return function(dependencies: any)
	local Services: any = assert(dependencies.Services, "maintain-item requires Services")
	local player: any = assert(dependencies.Player, "maintain-item requires Player")
	local workspace: any = assert(dependencies.Workspace, "maintain-item requires Workspace")
	local state: any = assert(dependencies.State, "maintain-item requires State")
	local droppedItems: any = assert(dependencies.DroppedItems, "maintain-item requires DroppedItems")
	local poweredItems: any = assert(dependencies.PoweredItems, "maintain-item requires PoweredItems")
	local normalizeItemName: any = assert(dependencies.NormalizeItemName, "maintain-item requires NormalizeItemName")
	local itemIsBurntCross: any = assert(dependencies.ItemIsBurntCross, "maintain-item requires ItemIsBurntCross")
	local itemIsInsideRoom: any = assert(dependencies.ItemIsInsideRoom, "maintain-item requires ItemIsInsideRoom")
	local actionIsSafe: any = assert(dependencies.ActionIsSafe, "maintain-item requires ActionIsSafe")
	local approachPositions: any = assert(dependencies.ApproachPositions, "maintain-item requires ApproachPositions")
	local teleportNearTarget: any = assert(dependencies.TeleportNearTarget, "maintain-item requires TeleportNearTarget")
	local teleportToBaseCamp: any = assert(dependencies.TeleportToBaseCamp, "maintain-item requires TeleportToBaseCamp")
	local teleportOptions: any = assert(dependencies.TeleportOptions, "maintain-item requires TeleportOptions")
	local getPosition: any = assert(dependencies.GetPosition, "maintain-item requires GetPosition")
	local beginMutation: any = assert(dependencies.BeginMutation, "maintain-item requires BeginMutation")
	local waitFor: any = assert(dependencies.Wait, "maintain-item requires Wait")
	local setStatus: any = assert(dependencies.SetStatus, "maintain-item requires SetStatus")
	local captureItems: any = assert(dependencies.CaptureItems, "maintain-item requires CaptureItems")
	local enabledObjectFor: any = assert(dependencies.EnabledObjectFor, "maintain-item requires EnabledObjectFor")
	local restoreItem: any = assert(dependencies.RestoreItem, "maintain-item requires RestoreItem")
	local outsideGrace = tonumber(dependencies.OutsideGrace) or 4
	local interval = tonumber(dependencies.Interval) or 1
	local retryBackoff = tonumber(dependencies.RetryBackoff) or 2
	local remoteDelay = tonumber(dependencies.RemoteDelay) or 0.1

	return function(room, generation)
		local now = os.clock()
		if state.itemsDirty ~= true and now < (state.nextMaintenanceAt or 0) then
			return
		end
		state.itemsDirty = false
		state.nextMaintenanceAt = now + interval
		captureItems(room)
		for _, itemName in ipairs(droppedItems) do
			local normalized = normalizeItemName(itemName)
			local model = state.roomItems[normalized]
			if model and model.Parent then
				if itemIsBurntCross(model) then
					state.roomItems[normalized] = nil
					continue
				end
				local itemsFolder = workspace:FindFirstChild("Items")
				local worldItem = itemsFolder and model:IsDescendantOf(itemsFolder)
				local insideRoom = worldItem and itemIsInsideRoom(model, room)
				if not insideRoom then
					state.outsideSince[model] = state.outsideSince[model] or now
					local retryAt = state.maintenanceBackoff[model] or 0
					if now - state.outsideSince[model] >= outsideGrace and now >= retryAt then
						setStatus("Maintaining room items")
						if restoreItem(model, room, generation) then
							state.outsideSince[model] = nil
							state.maintenanceBackoff[model] = nil
							state.itemsDirty = true
						else
							state.maintenanceBackoff[model] = now + retryBackoff
							state.outsideSince[model] = nil
							state.roomItems[normalized] = nil
							state.itemsDirty = true
						end
						return
					end
				else
					state.outsideSince[model] = nil
				end
				if insideRoom and poweredItems[normalized] then
					local enabledObject = enabledObjectFor(model)
					if enabledObject then
						local enabled = enabledObject:GetAttribute("Enabled") == true
						local power = state.itemPower[enabledObject]
						if not power then
							power = {
								Last = enabled,
								LastChangedAt = now,
								Transitions = {},
							}
							power.Connection = enabledObject:GetAttributeChangedSignal("Enabled"):Connect(function()
								if not state.enabled or not enabledObject.Parent then
									return
								end
								local changedAt = os.clock()
								local changed = enabledObject:GetAttribute("Enabled") == true
								if power.Last ~= changed then
									power.Last = changed
									power.LastChangedAt = changedAt
									table.insert(power.Transitions, changedAt)
									state.itemsDirty = true
								end
							end)
							state.itemPower[enabledObject] = power
						elseif power.Last ~= enabled then
							power.Last = enabled
							power.LastChangedAt = now
							table.insert(power.Transitions, now)
						end
						for index = #power.Transitions, 1, -1 do
							if now - power.Transitions[index] > 3 then
								table.remove(power.Transitions, index)
							end
						end
						local flickering = #power.Transitions >= 3
						if not enabled and not flickering
							and now - power.LastChangedAt >= 3
							and now >= (power.RetryAt or 0) then
							setStatus("Maintaining room items")
							for _, approach in ipairs(approachPositions(model, 4)) do
								if not actionIsSafe(generation) then
									return
								end
								if teleportNearTarget(model, approach, generation) then
									if not actionIsSafe(generation) then
										teleportToBaseCamp(teleportOptions(generation))
										return
									end
									local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
									local itemPosition = getPosition(model)
									if not root or not itemPosition or (root.Position - itemPosition).Magnitude > 10 then
										power.RetryAt = now + retryBackoff
										return
									end
									local events = Services.ReplicatedStorage:FindFirstChild("Events")
									local toggle = events and events:FindFirstChild("ToggleItemState")
									if toggle and toggle:IsA("RemoteEvent") then
										beginMutation(2.5)
										waitFor(generation, remoteDelay)
										if not actionIsSafe(generation) then
											return
										end
										if pcall(toggle.FireServer, toggle, model) then
											power.LastChangedAt = now
											power.RetryAt = now + 2
										else
											power.RetryAt = now + retryBackoff
										end
									end
									break
								end
							end
							return
						end
					end
				end
			end
		end
	end
end
