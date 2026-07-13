local QualifiedOneShot = {}
QualifiedOneShot.__index = QualifiedOneShot

local function asSet(values)
	local result = {}
	for _, value in ipairs(type(values) == "table" and values or {}) do
		result[value] = true
	end
	return result
end

function QualifiedOneShot.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "QualifiedOneShot",
		Category = "Discardable",
		Status = "Idle",
		TriggerTypes = asSet(options.TriggerTypes),
		Qualify = options.Qualify,
		Read = options.Read,
		ResultType = options.ResultType or "OneShotObservation",
		_context = nil,
		_result = nil,
	}, QualifiedOneShot)
end

QualifiedOneShot.New = QualifiedOneShot.new

function QualifiedOneShot:Start(context)
	if self.Status == "Discarded" then
		return
	end
	self._context = context or {}
	self.Status = "Waiting"
end

function QualifiedOneShot:OnEvent(event)
	if self.Status ~= "Waiting" or type(event) ~= "table" then
		return
	end
	local kind = event.Type or event.Kind
	if not self.TriggerTypes[kind] then
		return
	end
	if type(self.Qualify) == "function" and self.Qualify(event, self._context) ~= true then
		return
	end
	local result = type(self.Read) == "function" and self.Read(event, self._context) or event.Payload
	if result == nil then
		return
	end
	self._result = result
	if type(self._context.Emit) == "function" then
		self._context.Emit({
			Type = self.ResultType,
			HuntId = event.HuntId,
			Hunting = event.Hunting,
			Source = self.Name,
			ParentId = event.Id,
			Payload = result,
		})
	end
	self.Status = "Discarded"
end

function QualifiedOneShot:Stop()
	if self.Status ~= "Discarded" then
		self.Status = "Stopped"
	end
end

function QualifiedOneShot:Reset()
	self._result = nil
	self.Status = "Idle"
end

function QualifiedOneShot:Destroy()
	self._context = nil
	self.Status = "Destroyed"
end

function QualifiedOneShot:Snapshot()
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		Result = self._result,
	}
end

return QualifiedOneShot
