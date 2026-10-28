-- Initialize: the server entry point. Starts every service; services own the rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleLoader = require(ReplicatedStorage.Shared.ModuleLoader)

ModuleLoader.startChildren(script.Parent.Services)
