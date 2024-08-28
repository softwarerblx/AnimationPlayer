local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Animations = require(script:WaitForChild("PlayerAnimations"))

local localPlayer = Players.LocalPlayer
local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()

local AnimationPlayer = {
	PlayedData = {},
	MarkerReachedData = {},
	StoppedData = {},
	PlayerConnections = {},
}

function AnimationPlayer:_init()
	AnimationPlayer:_initializeAnimationData()

	Players.PlayerAdded:Connect(function(client: Player)
		AnimationPlayer:_onPlayerAdded(client)
	end)

	Players.PlayerRemoving:Connect(function(client: Player)
		AnimationPlayer:_onPlayerRemoving(client)
	end)

	for _, client: Player in Players:GetPlayers() do
		AnimationPlayer:_onPlayerAdded(client)
	end
end

function AnimationPlayer:_getNameFromAnimationTrack(animationTrack: AnimationTrack)
	local animationId = string.gsub(animationTrack.Animation.AnimationId, "^rbxassetid://0", "rbxassetid://")

	for animationName: string, animationData in Animations do
		if animationData.Id == animationId then
			return animationName
		end
	end
end

function AnimationPlayer:_initializeAnimationData()
	for animationName: string, animationData in Animations do
		local keyframeSequence = nil
		local success = pcall(function()
			keyframeSequence = KeyframeSequenceProvider:GetKeyframeSequenceAsync(animationData.Id)
		end)

		if success then
			local markerData = Animations[animationName].MarkerData
			if not markerData then
				markerData = {}
			end

			Animations[animationName].MarkerData = markerData

			for index: number, animationKeyframe: Keyframe in keyframeSequence:GetChildren() do
				if not animationKeyframe:IsA("Keyframe") then
					continue
				end

				local keyframeMarkers = animationKeyframe:GetMarkers()
				for _, animationMarker: KeyframeMarker in keyframeMarkers do
					table.insert(markerData, {
						Name = animationMarker.Name,
						Value = animationMarker.Value,
						Time = animationKeyframe.Time,
					})
				end
			end

			table.sort(markerData, function(a, b)
				return a.Time > b.Time
			end)
		end
	end
end

function AnimationPlayer:_loadAnimations(animator: Animator)
	local returnValue = {}
	for animationName: string, animationData in Animations do
		local animation = Instance.new("Animation")
		animation.AnimationId = animationData.Id
		animation.Name = animationName
		animation.Parent = animator

		local animationTrack = animator:LoadAnimation(animation)
		local animationPriority = animationData.Priority

		if animationPriority then
			animationTrack.Priority = animationPriority
		end

		local animationType = animationData.AnimationType
		if animationType then
			animationTrack:SetAttribute("AnimationType", animationType)
		end

		returnValue[animationName] = animationTrack
	end

	return returnValue
end

function AnimationPlayer._onPlayerAdded(self, client: Player)
	local playerConnections = {}

	self.PlayerConnections[client] = playerConnections

	if client.Character then
		self:_onCharacterAdded(client, client.Character)

		playerConnections.CharacterAdded = client.CharacterAdded:Connect(function(character: Model)
			self:_onCharacterAdded(client, character)
		end)

		playerConnections.CharacterRemoving = client.CharacterRemoving:Connect(function(character: Model)
			self:_onCharacterRemoving(client, character)
		end)
	end

	playerConnections.CharacterAdded = client.CharacterAdded:Connect(function(character: Model)
		self:_onCharacterAdded(client, character)
	end)

	playerConnections.CharacterRemoving = client.CharacterRemoving:Connect(function(character: Model)
		self:_onCharacterRemoving(client, character)
	end)
end

function AnimationPlayer._onPlayerRemoving(self, client: Player)
	local playerConnections = self.PlayerConnections[client]
	if playerConnections then
		for _, connection: RBXScriptConnection in playerConnections do
			connection:Disconnect()
			connection = nil
		end

		playerConnections = nil
	end
end

function AnimationPlayer._onCharacterAdded(self, client: Player, character: Model)
	local humanoid: Humanoid = character:WaitForChild("Humanoid")
	local animator: Animator = humanoid:WaitForChild("Animator")

	if client == localPlayer then
		self.LoadedAnimations = self:_loadAnimations(animator)
	end

	local playerConnections = self.PlayerConnections[client]
	if playerConnections then
		playerConnections.AnimationPlayed = animator.AnimationPlayed:Connect(function(animationTrack: AnimationTrack)
			self:_onAnimationPlayed(character, animationTrack)
		end)
	end

	task.defer(function()
		for _, playingAnimation: AnimationTrack in animator:GetPlayingAnimationTracks() do
			self:_onAnimationPlayed(character, playingAnimation, true)
		end
	end)
end

function AnimationPlayer._onCharacterRemoving(self, client: Player, character: Model)
	local playerConnections = self.PlayerConnections[client]
	if playerConnections then
		return
	end

	if playerConnections.AnimationPlayed then
		playerConnections.AnimationPlayed:Disconnect()
		playerConnections.AnimationPlayed = nil
	end
end

function AnimationPlayer._onAnimationPlayed(
	self,
	character: Model,
	animationTrack: AnimationTrack,
	alreadyPlaying: boolean?
)
	local client = Players:GetPlayerFromCharacter(character)
	local animationName = self:_getNameFromAnimationTrack(animationTrack)
	local markerReachedConnections = {}
	local stoppedConnections = {}

	local playedData = self.PlayedData[animationName]
	if playedData then
		for eventName: string, eventData in playedData do
			eventData.Callback(client)
		end
	end

	local markerReachedData = self.MarkerReachedData[animationName]
	if markerReachedData then
		if alreadyPlaying then
			local markerData = Animations[animationName].MarkerData
			if markerData then
				for _, data in markerData do
					if data.Time <= animationTrack.TimePosition then
						for eventName: string, eventData in markerReachedData do
							if not eventData.AllowPostReached then
								continue
							end

							if eventData.Marker == data.Name then
								eventData.Callback(client, data.Value)

								break
							end
						end
					end
				end
			end
		end

		for eventName: string, eventData in markerReachedData do
			table.insert(
				markerReachedConnections,
				animationTrack:GetMarkerReachedSignal(eventData.Marker):Connect(function(parameter: string)
					eventData.Callback(client, parameter)
				end)
			)
		end
	end

	local stoppedData = self.StoppedData[animationName]
	if stoppedData then
		for eventName: string, eventData in stoppedData do
			table.insert(
				stoppedConnections,
				animationTrack.Stopped:Once(function()
					eventData.Callback(client)
				end)
			)
		end
	end

	animationTrack.Stopped:Once(function()
		for _, markerReachedConnection: RBXScriptConnection in markerReachedConnections do
			markerReachedConnection:Disconnect()
			markerReachedConnection = nil
		end

		markerReachedConnections = nil
	end)
end

function AnimationPlayer.GetAnimationTrack(self, animationName: string)
	return self.LoadedAnimations[animationName]
end

function AnimationPlayer.GetAnimationTracks(self)
	local loadedAnimations = {}
	for animationName: string, animationTrack: AnimationTrack in self.LoadedAnimations do
		loadedAnimations[animationName] = animationTrack
	end

	return loadedAnimations
end

function AnimationPlayer.PlayAnimation(self, animationName: string, ...)
	local animationTrack = self.LoadedAnimations[animationName]
	if animationTrack and not animationTrack.IsPlaying then
		animationTrack:Play(...)
	end

	return animationTrack
end

function AnimationPlayer.AdjustSpeed(self, animationName: string, speed: number)
	local animationTrack = self.LoadedAnimations[animationName]
	if animationTrack then
		animationTrack:AdjustSpeed(speed)
	end

	return animationTrack
end

function AnimationPlayer.AdjustWeight(self, animationName: string, weight: number)
	local animation = self.LoadedAnimations[animationName]
	if animation then
		local adjustedWeight = math.clamp(weight, 0.0001, 1)
		animation:AdjustWeight(adjustedWeight)
	end

	return animation
end

function AnimationPlayer.SetTimePosition(self, animationName: string, timePosition: number)
	local animationTrack = self.LoadedAnimations[animationName]
	if animationTrack then
		animationTrack.TimePosition = timePosition
	end

	return animationTrack
end

function AnimationPlayer.AddPlayedEvent(self, animationName: string, eventName: string, callback)
	local playedData = self.PlayedData[animationName]
	if not playedData then
		playedData = {}

		self.PlayedData[animationName] = playedData
	end

	if playedData[eventName] then
		playedData[eventName] = nil
	end

	playedData[eventName] = {
		Callback = callback,
	}
end

function AnimationPlayer.AddMarkerReachedEvent(
	self,
	animationName: string,
	eventName: string,
	markerName: string,
	callback,
	allowPostReached: boolean?
)
	local markerReachedData = self.MarkerReachedData[animationName]
	if not markerReachedData then
		markerReachedData = {}

		self.MarkerReachedData[animationName] = markerReachedData
	end

	if markerReachedData[eventName] then
		markerReachedData[eventName] = nil
	end

	markerReachedData[eventName] = {
		Marker = markerName,
		Callback = callback,
		AllowPostReached = allowPostReached or nil,
	}
end

function AnimationPlayer.AddStoppedEvent(self, animationName: string, eventName: string, callback)
	local stoppedData = self.StoppedData[animationName]
	if not stoppedData then
		stoppedData = {}

		self.StoppedData[animationName] = stoppedData
	end

	if stoppedData[eventName] then
		stoppedData[eventName] = nil
	end

	stoppedData[eventName] = {
		Callback = callback,
	}

	self.StoppedData[animationName] = stoppedData
end

function AnimationPlayer.RemovePlayedEvent(self, animationName: string, eventName: string)
	local playedData = self.PlayedData[animationName]
	if not playedData then
		return
	end

	if playedData[eventName] then
		playedData[eventName] = nil
	end
end

function AnimationPlayer.RemoveMarkerReachedEvent(self, animationName: string, eventName: string)
	local markerReachedData = self.MarkerReachedData[animationName]
	if not markerReachedData then
		return
	end

	if markerReachedData[eventName] then
		markerReachedData[eventName] = nil
	end
end

function AnimationPlayer.RemoveStoppedEvent(self, animationName: string, eventName: string)
	local stoppedData = self.StoppedData[animationName]
	if not stoppedData then
		return
	end

	if stoppedData[eventName] then
		stoppedData[eventName] = nil
	end
end

function AnimationPlayer.StopAnimation(self, animationName: string, ...)
	local animation = self.LoadedAnimations[animationName]
	if animation and animation.IsPlaying then
		animation:Stop(...)
	end

	return animation
end

AnimationPlayer:_init()

return AnimationPlayer
