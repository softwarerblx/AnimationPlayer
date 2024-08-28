local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Replace this with your path to the AnimationPlayer module
local AnimationPlayer = require(ReplicatedStorage.AnimationPlayer)

-- Stops the ExampleAnimation AnimationTrack if it is currently playing
AnimationPlayer:StopAnimation("ExampleAnimation")

-- Starts the ExampleAnimation AnimationTrack if it is not currently playing
AnimationPlayer:PlayAnimation("ExampleAnimation")

-- Listens for whenever the "ExampleMarker" marker is reached for any client's "ExampleAnimation" AnimationTrack
AnimationPlayer:AddMarkerReachedEvent("ExampleAnimation", "ExampleMarker", "ExampleParameter", function(client: Player)
	print(`'ExampleMarker' was reached for 'ExampleAnimation' for {client.Name}`)
end, true)
