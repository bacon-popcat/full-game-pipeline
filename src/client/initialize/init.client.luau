-- Initialize: the client entry point. Starts every controller; controllers own the rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleLoader = require(ReplicatedStorage.Shared.ModuleLoader)

ModuleLoader.startChildren(script.Parent.Controllers)
