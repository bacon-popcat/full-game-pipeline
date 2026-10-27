--!strict
-- ModuleLoader: the one place a container of ModuleScripts gets started. Every
-- bootstrapper calls this instead of writing its own scan-require-init loop.
--
--     function Module.init(...)   -- lowercase, no `self`, args explicit, optional
--
-- Non-ModuleScript children are skipped. `init` is task.spawn'd, so one module
-- throwing or yielding can't stall its siblings. The require itself is NOT
-- pcall'd -- a first-party module failing to load is a hard bug and should be loud.

local ModuleLoader = {}

-- Requires every ModuleScript child of `container` and spawns its `init`,
-- forwarding any extra arguments (UIController passes the HUD down this way).
function ModuleLoader.startChildren(container: Instance, ...: any)
	for _, module in container:GetChildren() do
		if not module:IsA("ModuleScript") then
			continue
		end

		local data = require(module) :: any
		if typeof(data) ~= "table" or typeof(data.init) ~= "function" then
			continue
		end

		task.spawn(data.init, ...)
	end
end

return ModuleLoader
