local dagger 			= {}
	dagger.isEquipped = false

local userInputService 	= game:GetService("UserInputService")
local httpService 		= game:GetService("HttpService")
local replicatedStorage = game:GetService("ReplicatedStorage")


local abilityAnimations = game:GetService("ReplicatedStorage"):WaitForChild("assets"):WaitForChild("abilityAnimations")


	local modules = require(replicatedStorage.modules)
		local network 		= modules.load("network")
		local utilities 	= modules.load("utilities")
		local detection 	= modules.load("detection")
		local placeSetup 	= modules.load("placeSetup")

local currentDamageGUID = httpService:GenerateGUID(false)

local animationInterface = require(script.Parent.Parent.Parent:WaitForChild("contents"):WaitForChild("animationInterface"))--network:invoke("getPlayerCoreService", "animationInterface")

-- internal stuff specific to the dagger
local animationControllerLoaded
local attackSequenceLength
local animationsForAnimationController

local slashAnimationConnection

local isWithinSlash1Window 		= false
local isWithinSlash2Window 		= false
local isWithinDamageSequence 	= false
local canPlayerDoubleSlash 		= false
local canPlayerTripleSlash 		= false

local currentWeaponManifest
local myClientCharacterContainer
local playerAbilitiesSlotDataCollection

local player 			= game.Players.LocalPlayer
local isPlayerSprinting = false

local function onCharacterStateChanged(state, value)
	if state == "isSprinting" then
		isPlayerSprinting = value
	end
end

local function doesPlayerHaveAbilityUnlocked(abilityId, variant)
	if playerAbilitiesSlotDataCollection then
		for _, abilitySlotData in pairs(playerAbilitiesSlotDataCollection) do
			if abilitySlotData.id == abilityId and abilitySlotData.rank > 0 then
				if variant then
					return abilitySlotData.variant == variant
				else
					return true
				end
			end
		end
	end

	return false
end

local isDamageSequenceEnabled = false
local function startDamageSequencePolling()
	if isDamageSequenceEnabled then return end
	isDamageSequenceEnabled = true

	while isDamageSequenceEnabled do
		if animationsForAnimationController.daggerAnimations.strike1.IsPlaying or animationsForAnimationController.daggerAnimations.strike2.IsPlaying or animationsForAnimationController.daggerAnimations.strike3.IsPlaying then
			if isWithinDamageSequence then
				network:invoke("performClientDamageCycle", "equipment", nil, currentDamageGUID)
			end

			wait(1 / 20)
		else
			break
		end
	end

	isDamageSequenceEnabled = false
end

local function onSlashAnimationTrackStopped()
	currentDamageGUID = httpService:GenerateGUID(false)

	if slashAnimationConnection then
		slashAnimationConnection:disconnect()
		slashAnimationConnection = nil
	end

	if slashAnimationKeyframeConnection then
		slashAnimationKeyframeConnection:disconnect()
		slashAnimationKeyframeConnection = nil
	end

	if currentWeaponManifest and currentWeaponManifest:FindFirstChild("Trail") then
		currentWeaponManifest.Trail.Enabled = false
	end
end

-- slash1PeriodStart
-- slash2PeriodStart
-- startDamageSequence
-- stopDamageSequence
local function onSlashAnimationKeyframeReached(keyframeName)
	if keyframeName == "slash1PeriodStart" then
		currentWeaponManifest.Trail.Color = ColorSequence.new(Color3.new(1,0,0))
		isWithinSlash1Window = true
--		delay(3 / 10, function()
--			isWithinSlash1Window = false
--		end)
	elseif keyframeName == "slash2PeriodStart" then
		currentWeaponManifest.Trail.Color = ColorSequence.new(Color3.new(0,1,0))
		isWithinSlash2Window = true
--		delay(3 / 10, function()
--			isWithinSlash2Window = false
--		end)
	elseif keyframeName == "startDamageSequence" then
		currentWeaponManifest.Trail.Color = ColorSequence.new(Color3.new(1,1,1))
		local swingSound = currentWeaponManifest:FindFirstChild("Swing")
		if swingSound == nil then
			swingSound = Instance.new("Sound")
			swingSound.Volume = 1
			swingSound.MaxDistance = 50
			swingSound.SoundId = "rbxassetid://2069260907"
			swingSound.Name = "Swing"
			swingSound.Parent = currentWeaponManifest
		end

		swingSound:Play()
		isWithinDamageSequence = true

		if currentWeaponManifest and currentWeaponManifest:FindFirstChild("Trail") then
			currentWeaponManifest.Trail.Enabled = true
		end
	elseif keyframeName == "stopDamageSequence" then
		isWithinDamageSequence = false

		if currentWeaponManifest and currentWeaponManifest:FindFirstChild("Trail") then
			currentWeaponManifest.Trail.Enabled = false
		end
	end
end

function dagger:attack()
	-- make sure we can't slash if these conditions are true

	if not animationsForAnimationController or not animationsForAnimationController.daggerAnimations then
		return
	elseif isPlayerSprinting then
		return
	elseif not currentWeaponManifest then
		return
	elseif not player.Character or not player.Character.PrimaryPart or player.Character.PrimaryPart.state.Value == "dead" then
		return
	elseif animationsForAnimationController.daggerAnimations.strike1.IsPlaying and ((not isWithinSlash2Window) or (not canPlayerDoubleSlash))then --or not canPlayerDoubleSlash
		return
	elseif animationsForAnimationController.daggerAnimations.strike2.IsPlaying and not isWithinSlash1Window then
		return
	elseif animationsForAnimationController.daggerAnimations.strike3.IsPlaying then
		return
	end

	-- have to do it this way for now, no reference to ability animations  in animationsForAnimationController
	local animController = myClientCharacterContainer.entity.AnimationController
	for i, track in pairs(animController:GetPlayingAnimationTracks()) do
		if track.Name == "rock_throw_upper" or track.Name == "rock_throw_upper_loop" then
			return
		end
	end

	if animationsForAnimationController.daggerAnimations.strike1.IsPlaying and isWithinSlash2Window then
		isWithinSlash1Window = false
		isWithinSlash2Window = false
		if slashAnimationConnection then
			slashAnimationConnection:disconnect()
			slashAnimationConnection = nil
		end

		if slashAnimationKeyframeConnection then
			slashAnimationKeyframeConnection:disconnect()
			slashAnimationKeyframeConnection = nil
		end

		animationsForAnimationController.daggerAnimations.strike1:Stop()

		slashAnimationConnection 			= animationsForAnimationController.daggerAnimations.strike2.Stopped:connect(onSlashAnimationTrackStopped)
		slashAnimationKeyframeConnection 	= animationsForAnimationController.daggerAnimations.strike2.KeyframeReached:connect(onSlashAnimationKeyframeReached)

		animationInterface:replicateClientAnimationSequence("daggerAnimations", "strike2")

		-- start damage sequence
		currentDamageGUID = httpService:GenerateGUID(false)
		spawn(startDamageSequencePolling)
	elseif (not animationsForAnimationController.daggerAnimations.strike1.IsPlaying) and ((not animationsForAnimationController.daggerAnimations.strike2.IsPlaying) or isWithinSlash1Window) then
		if canPlayerTripleSlash and isWithinSlash1Window then
			isWithinSlash1Window = false
			isWithinSlash2Window = false
			if slashAnimationConnection then
				slashAnimationConnection:disconnect()
				slashAnimationConnection = nil
			end

			if slashAnimationKeyframeConnection then
				slashAnimationKeyframeConnection:disconnect()
				slashAnimationKeyframeConnection = nil
			end

			animationsForAnimationController.daggerAnimations.strike2:Stop()

			slashAnimationConnection 			= animationsForAnimationController.daggerAnimations.strike3.Stopped:connect(onSlashAnimationTrackStopped)
			slashAnimationKeyframeConnection 	= animationsForAnimationController.daggerAnimations.strike3.KeyframeReached:connect(onSlashAnimationKeyframeReached)

			animationInterface:replicateClientAnimationSequence("daggerAnimations", "strike3")

			-- start damage sequence
			currentDamageGUID = httpService:GenerateGUID(false)
			spawn(startDamageSequencePolling)
		else
			isWithinSlash1Window = false
			isWithinSlash2Window = false
			if slashAnimationConnection then
				slashAnimationConnection:disconnect()
				slashAnimationConnection = nil
			end

			if slashAnimationKeyframeConnection then
				slashAnimationKeyframeConnection:disconnect()
				slashAnimationKeyframeConnection = nil
			end

			animationsForAnimationController.daggerAnimations.strike2:Stop()

			slashAnimationConnection = animationsForAnimationController.daggerAnimations.strike1.Stopped:connect(function()
				isWithinDamageSequence = false
			end)

			slashAnimationKeyframeConnection = animationsForAnimationController.daggerAnimations.strike1.KeyframeReached:connect(onSlashAnimationKeyframeReached)

			animationInterface:replicateClientAnimationSequence("daggerAnimations", "strike1")

			-- start damage sequence
			currentDamageGUID = httpService:GenerateGUID(false)
			spawn(startDamageSequencePolling)
		end
	end
end

function dagger:equip()
	isWithinSlash1Window 	= false
	isWithinSlash2Window 	= false
	isWithinDamageSequence 	= false
	isDamageSequenceEnabled = false
	--local
	myClientCharacterContainer = network:invoke("getMyClientCharacterContainer")

	if myClientCharacterContainer then
		currentWeaponManifest 				= network:invoke("getCurrentWeaponManifest")
		animationsForAnimationController 	= animationInterface:getAnimationsForAnimationController(myClientCharacterContainer.entity.AnimationController)

	--	local grip = myClientCharacterContainer.entity:FindFirstChild("Grip", true)
	--	if grip then
	--		-- force an update
	--		onGripPropertyChanged(grip, "Part1")
	--	end
	end
end

function dagger:unequip()

end

local function onPropogationRequestToSelf(propogationNameTag, propogationValue)
	if propogationNameTag == "abilities" then
		playerAbilitiesSlotDataCollection = propogationValue

		canPlayerDoubleSlash = doesPlayerHaveAbilityUnlocked(3)
		canPlayerTripleSlash = doesPlayerHaveAbilityUnlocked(3, "tripleSlash")
	end
end

local function main()
	onPropogationRequestToSelf("abilities", network:invoke("getCacheValueByNameTag", "abilities"))

	network:connect("propogationRequestToSelf", "Event", onPropogationRequestToSelf)
	network:connect("characterStateChanged", "Event", onCharacterStateChanged)
end

main()

return dagger