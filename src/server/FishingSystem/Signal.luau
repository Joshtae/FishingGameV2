--!strict
--[[
	Server-only signal utility for FishingSystem modules.
	API: Signal.new(), :Connect(callback), :Once(callback), :Fire(...), :Wait(), :Destroy().
]]
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_event = Instance.new("BindableEvent"),
		_connections = {},
	}, Signal)
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "Signal callback must be a function")
	local connection = self._event.Event:Connect(callback)
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	self._event:Fire(...)
end

function Signal:Wait()
	return self._event.Event:Wait()
end

function Signal:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._event:Destroy()
	table.clear(self._connections)
end

return Signal
