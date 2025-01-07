local Mod = HudHelperExample
local emptyShaderName = "HudHelperEmptyShader"

local VERSION = 1.01 -- do not modify
local game = Game()

-- debug
local FORCE_VERSION_UPDATE = false

local CACHED_CALLBACKS
local CACHED_ELEMENTS

---Initializes data that should not be reset when a newer version of the mod is loaded.
local function InitMod()
	---@class HUDInfo
	---@field Name string @The name of the HUD element.
	---@field Priority integer @The priority of the HUD element. The lower the number, the higher the priority.
	---@field Condition fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout): boolean @A function that returns true if the HUD element should be drawn.
	---@field OnRender fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout, position: Vector) @Runs for each player, if the condition is true.
	---@field BypassGhostBaby boolean? @default: `false`. Set to `true` to ignore if your player is a co-op baby and continue rendering.
	---@field PreRenderCallback boolean? @default: `false`. Set to `true` to specify your callback should on the PRE version of a render callback rather than POST.
	---@class HUDInfo_Active: HUDInfo
	---@field Condition fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout, slot: ActiveSlot): boolean @A function that returns true if the HUD element should be drawn.
	---@field OnRender fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout, position: Vector, alpha: integer, scale: integer, slot: ActiveSlot) @Runs for each player, if the condition is true.

	---@class HUDInfo_Health: HUDInfo
	---@field OnRender fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout, position: Vector, maxColumns: integer) @Runs for each player, if the condition is true.

	---@class HUDInfo_PocketItem: HUDInfo
	---@field OnRender fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout, position: Vector, alpha: integer, scale: integer) @Runs for each player, if the condition is true.

	---@class HUDInfo_Extra: HUDInfo
	---@field YPadding integer | fun(player: EntityPlayer, playerHUDIndex: integer, hudLayout: HUDLayout): integer @The height of the HUD element. This is used to calculate the padding between HUD elements.
	---@field XPadding integer | table<integer, integer> @The padding between the HUD element and vanilla ui, by player index.

	---@class HUDCallback
	---@field Priority integer
	---@field Function function
	---@field Args any[]

	local HudHelper = RegisterMod(("[%s] HUD Helper"):format(Mod.Name), 1)
	HudHelper.HUD_ELEMENTS = {
		Base = CACHED_ELEMENTS and CACHED_ELEMENTS.Base or {}, ---@type HUDInfo[]
		Actives = CACHED_ELEMENTS and CACHED_ELEMENTS.Actives or {}, ---@type HUDInfo_Active[]
		Health = CACHED_ELEMENTS and CACHED_ELEMENTS.Health or {}, ---@type HUDInfo_Health[]
		PocketItems = CACHED_ELEMENTS and CACHED_ELEMENTS.PocketItems or {}, ---@type HUDInfo_PocketItem[]
		Extra = CACHED_ELEMENTS and CACHED_ELEMENTS.Extra or {}, ---@type HUDInfo_Extra[]
		--maybe?
		--Trinkets = {}
	}
	HudHelper.Version = VERSION
	HudHelper.ItemSpecificOffset = {
		[CollectibleType.COLLECTIBLE_JAR_OF_FLIES] = Vector(4, 2),
	}
	---@enum HUDType
	HudHelper.HUDType = {
		BASE = 0, --Top left corner of each HUD
		ACTIVE = 1, --Renders on every active item. This includes Esau's unique positioning of their active and inside secondary slots
		HEALTH = 2, --Location of the first heart of each HUD. Currently not does support Strawmen players(?)
		POCKET = 3, --Renders on the primary pocket item slot of each HUD
		EXTRA = 4
	}
	HudHelper.HUDTypeToTable = {
		[0] = HudHelper.HUD_ELEMENTS.Base,
		[1] = HudHelper.HUD_ELEMENTS.Actives,
		[2] = HudHelper.HUD_ELEMENTS.Health,
		[3] = HudHelper.HUD_ELEMENTS.PocketItems,
		[4] = HudHelper.HUD_ELEMENTS.Extra,
	}
	---@enum HUDLayout
	HudHelper.HUDLayout = {
		P1 = 1,
		P1_MAIN_TWIN = 2,
		P1_OTHER_TWIN = 3,
		COOP = 4,
		STRAWMAN_HEARTS = 5,
		TWIN_COOP = 6 --Rep+ exclusive
	}

	---@type table<ModCallbacks, function[]>
	HudHelper.AddedCallbacks = {
		[ModCallbacks.MC_USE_ITEM] = {},
		[ModCallbacks.MC_POST_RENDER] = {}
	} -- for any vanilla callback functions added by this library

	if REPENTOGON then
		HudHelper.AddedCallbacks[ModCallbacks.MC_PRE_PLAYERHUD_RENDER_HEARTS] = {}
		HudHelper.AddedCallbacks[ModCallbacks.MC_POST_PLAYERHUD_RENDER_HEARTS] = {}
		HudHelper.AddedCallbacks[ModCallbacks.MC_PRE_PLAYERHUD_RENDER_ACTIVE_ITEM] = {}
		HudHelper.AddedCallbacks[ModCallbacks.MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM] = {}
		HudHelper.AddedCallbacks[ModCallbacks.MC_POST_HUD_RENDER] = {}
	else
		HudHelper.AddedCallbacks[ModCallbacks.MC_GET_SHADER_PARAMS] = {}
	end

	HudHelper.Callbacks = {}

	---@type table<string, HUDCallback[]>
	HudHelper.Callbacks.RegisteredCallbacks = game:GetFrameCount() == 0 and CACHED_CALLBACKS or {}

	return HudHelper
end

---Initializes data and functions that get overwritten when a newer version of the mod is loaded.
local function InitFunctions()
	local HUD_ELEMENTS = HudHelper.HUD_ELEMENTS

	---List of HudHelper.HUDPlayers, indexed by corner of which corner of the HUD they're in.
	---@type table<integer, EntityPtr[] | nil>
	HudHelper.HUDPlayers = {}

	HudHelper.HUDTwinBlacklist = {
		[PlayerType.PLAYER_THESOUL_B] = true,
	}

	---@param entityPtr EntityPtr
	---@return EntityPlayer?
	local function tryGetPlayerFromPtr(entityPtr)
		if entityPtr
			and entityPtr.Ref
			and entityPtr.Ref:ToPlayer()
		then
			local player = entityPtr.Ref:ToPlayer()
			if player
				and player:Exists()
				and player.Variant == 0
			then
				return player
			end
		end
	end

	--#region Constants
	HudHelper.EXTRA_HUD_PADDING_TOP = Vector(0, 6)
	HudHelper.EXTRA_HUD_PADDING_BOTTOM = Vector(0, 3)

	HudHelper.Priority = {
		VANILLA = -1,
		HIGHEST = 0,
		HIGH = 10,
		NORMAL = 20,
		LOW = 30,
		LOWEST = 40,
		EID = 1000,
	}

	HudHelper.Callbacks.ID = {
		CHECK_HUD_HIDDEN = "HUDHELPER_CHECK_HUD_HIDDEN",
	}
	for _, v in pairs(HudHelper.Callbacks.ID) do
		if not HudHelper.Callbacks.RegisteredCallbacks[v] then
			HudHelper.Callbacks.RegisteredCallbacks[v] = {}
		end
	end

	HudHelper.CallbackPriority = {
		HIGHEST = 0,
		HIGH = 10,
		NORMAL = 20,
		LOW = 30,
		LOWEST = 40,
	}
	--#endregion

	--#region Helper Functions
	HudHelper.Utils = {}

	local condensedCoopHUD = false

	---@param player EntityPlayer
	local function canAddTwinHUD(player)
		local twinPlayer = player:GetOtherTwin()
		if player:GetPlayerType() == PlayerType.PLAYER_LAZARUS_B
			or player:GetPlayerType() == PlayerType.PLAYER_LAZARUS2_B
		then
			return false
		end

		if twinPlayer                                             --You have a twin player
			and GetPtrHash(player:GetMainTwin()) == GetPtrHash(player) --Are the main of the 2 twins
			and not HudHelper.HUDTwinBlacklist[twinPlayer:GetPlayerType()] --Ensure your twin is allowed a HUD
		then
			return true
		end

		return false
	end

	---@param player EntityPlayer
	function HudHelper.Utils.FillPlayerHUDInventory(player)
		player = player:GetPlayerType() == PlayerType.PLAYER_THESOUL_B and player:GetMainTwin() or player
		player:AddCollectible(CollectibleType.COLLECTIBLE_MOMS_PURSE)
		player:AddCollectible(CollectibleType.COLLECTIBLE_POLYDACTYLY)
		player:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG)
		player:AddCollectible(CollectibleType.COLLECTIBLE_D6)
		player:AddCollectible(CollectibleType.COLLECTIBLE_TAMMYS_HEAD)
		player:AddTrinket(TrinketType.TRINKET_AAA_BATTERY)
		player:AddTrinket(TrinketType.TRINKET_SWALLOWED_PENNY)
		player:AddCard(Card.CARD_FOOL)
		player:AddCard(Card.CARD_MAGICIAN)
	end

	---@param player EntityPlayer
	function HudHelper.Utils.GetEffectiveMaxHealth(player)
		return player:GetEffectiveMaxHearts() + player:GetSoulHearts() +
			(player:GetBrokenHearts() * 2)
	end

	function HudHelper.Utils.GetBookOffset(player)
		if player:IsCoopGhost() then return Vector.Zero end
		if (player:HasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES)
				and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES)
			or (player:GetPlayerType() == PlayerType.PLAYER_JUDAS and player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)) then
			return Vector(0, -4)
		end
		return Vector.Zero
	end

	---Returns the numbered index of the player corresponding with their placement on the HUD. 1 for P1, 2 for P2, etc
	---@param player EntityPlayer
	---@return integer
	function HudHelper.Utils.GetHUDPlayerNumberIndex(player)
		for index, hudPlayerTable in pairs(HudHelper.HUDPlayers) do
			for _, hudPlayer in pairs(hudPlayerTable) do
				local _player = tryGetPlayerFromPtr(hudPlayer)
				if _player and GetPtrHash(player) == GetPtrHash(_player) then
					return index
				end
			end
		end
		return -1
	end

	---@generic T
	---@param value T
	---@vararg string
	---@return T
	function HudHelper.Utils.CheckValueType(valueName, value, ...)
		local types = { ... }
		for i = 1, #types do
			if type(value) == types[i] then
				return value
			end
		end
		error(valueName .. " must be one of the following types: " .. table.concat({ ... }, ", "), 2)
	end

	---@generic T
	---@param val T | fun(...): T
	---@param ... any
	---@return T
	function HudHelper.Utils.ProcessFuncOrValue(val, ...)
		if type(val) == "function" then
			return val(...)
		else
			return val
		end
	end

	---@param vec Vector
	function HudHelper.Utils.CopyVector(vec)
		return Vector(vec.X, vec.Y)
	end

	---Executes given function for every player
	---Return anything to end the loop early
	---@param func fun(player: EntityPlayer, playerNum?: integer): any?
	function HudHelper.Utils.ForEachPlayer(func)
		if REPENTOGON then
			for i, player in ipairs(PlayerManager.GetPlayers()) do
				if func(player, i) then
					return true
				end
			end
		else
			for i = 0, game:GetNumPlayers() - 1 do
				if func(Isaac.GetPlayer(i), i) then
					return true
				end
			end
		end
	end

	---@param playerType PlayerType
	function HudHelper.Utils.AnyoneIsPlayerType(playerType)
		if REPENTOGON then return PlayerManager.AnyoneIsPlayerType(playerType) end
		local isType = false
		HudHelper.Utils.ForEachPlayer(function(player)
			if player:ToPlayer():GetPlayerType() == playerType then
				isType = true
			end
		end)
		return isType
	end

	---@param playerHUDIndex integer
	---@return HUDLayout
	function HudHelper.Utils.GetHUDLayout(playerHUDIndex)
		local hudPlayer = HudHelper.HUDPlayers[playerHUDIndex][1]
		local player = tryGetPlayerFromPtr(hudPlayer)
		if not player then return HudHelper.HUDLayout.P1 end

		if not REPENTANCE_PLUS then
			if playerHUDIndex == 1 then
				if canAddTwinHUD(player) then
					return HudHelper.HUDLayout.P1_MAIN_TWIN
				else
					return HudHelper.HUDLayout.P1
				end
			else
				if playerHUDIndex == 5 then
					return HudHelper.HUDLayout.P1_OTHER_TWIN
				else
					return HudHelper.HUDLayout.COOP
				end
			end
		else
			if playerHUDIndex == 1 then
				if not condensedCoopHUD and not player:GetOtherTwin() then
					return HudHelper.HUDLayout.P1
				elseif not condensedCoopHUD and player:GetOtherTwin() then
					return HudHelper.HUDLayout.P1_MAIN_TWIN
				elseif HudHelper.HUDPlayers[playerHUDIndex][2] then
					return HudHelper.HUDLayout.TWIN_COOP
				else
					return HudHelper.HUDLayout.COOP
				end
			else
				if playerHUDIndex == 5 then
					return HudHelper.HUDLayout.P1_OTHER_TWIN
				elseif HudHelper.HUDPlayers[playerHUDIndex][2] then
					return HudHelper.HUDLayout.TWIN_COOP
				else
					return HudHelper.HUDLayout.COOP
				end
			end
		end
	end

	local tempest = Font()
	tempest:Load("font/pftempestasevencondensed.fnt")

	--Literally just rendering font, but with the screenshake offset, because the game is funny like that
	---@param text string
	---@param pos Vector
	---@param kColor? KColor @Default: KColor.White
	---@param font? Font @Default: Tempest
	function HudHelper.Utils.RenderFont(text, pos, kColor, font)
		pos = pos + game.ScreenShakeOffset
		font = font or tempest
		font:DrawString(text, pos.X, pos.Y, kColor or KColor.White)
	end

	local getBookOffset = HudHelper.Utils.GetBookOffset
	local checkValueType = HudHelper.Utils.CheckValueType
	local processFuncOrValue = HudHelper.Utils.ProcessFuncOrValue
	local copyVector = HudHelper.Utils.CopyVector

	--#endregion

	--#region Custom Callbacks

	---@param id string
	---@param priority integer
	---@param func function
	---@param ... any
	function HudHelper.Callbacks.AddPriorityCallback(id, priority, func, ...)
		local callbacks = HudHelper.Callbacks.RegisteredCallbacks[id]
		local callback = {
			Priority = priority,
			Function = func,
			Args = { ... },
		}

		if #callbacks == 0 then
			callbacks[#callbacks + 1] = callback
		else
			for i = #callbacks, 1, -1 do
				if callbacks[i].Priority <= priority then
					table.insert(callbacks, i + 1, callback)
					return
				end
			end
			table.insert(callbacks, 1, callback)
		end
	end

	---@param id string
	---@param func function
	---@param ... any
	function HudHelper.Callbacks.AddCallback(id, func, ...)
		HudHelper.Callbacks.AddPriorityCallback(id, HudHelper.CallbackPriority.NORMAL, func, ...)
	end

	---@param id string
	---@param func function
	function HudHelper.Callbacks.RemoveCallback(id, func)
		local callbacks = HudHelper.Callbacks.RegisteredCallbacks[id]
		for i = #callbacks, 1, -1 do
			if callbacks[i].Function == func then
				table.remove(callbacks, i)
			end
		end
	end

	--#endregion

	function HudHelper.ShouldHideHUD()
		if ModConfigMenu and ModConfigMenu.IsVisible
			or not game:GetHUD():IsVisible() and not (TheFuture or {}).HiddenHUD
			or game:GetSeeds():HasSeedEffect(SeedEffect.SEED_NO_HUD)
		then
			return true
		end

		local callbacks = HudHelper.Callbacks.RegisteredCallbacks[HudHelper.Callbacks.ID.CHECK_HUD_HIDDEN]
		for i = 1, #callbacks do
			if callbacks[i].Function() then
				return true
			end
		end

		return false
	end

	--#region Offset Functions

	---Gives the location of the player's HUD as a vector, starting from the top left corner.
	---@param playerHUDIndex integer
	---@return Vector
	---@function
	---@scope Mod.HudHelper
	function HudHelper.GetHUDPosition(playerHUDIndex)
		playerHUDIndex = math.min(4, playerHUDIndex)
		local hudOffsetOption = Options.HUDOffset
		local width, height = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
		local cornerOffsets = {
			Vector((hudOffsetOption * 20), (hudOffsetOption * 12)),
			Vector((-hudOffsetOption * 24) + width, (hudOffsetOption * 12)),
			Vector((hudOffsetOption * 22), (-hudOffsetOption * 6) + height),
			Vector((-hudOffsetOption * 16) + width, (-hudOffsetOption * 6) + height)
		}
		local REP_HUD_OFFSET = {
			Vector.Zero,
			Vector(-159, 0),
			Vector(10, -39),
			Vector(-167, -39)
		}
		local REP_PLUS_OFFSET = {
			Vector(0, 6),
			Vector(-175, 6),
			Vector(10, -39),
			Vector(-183, -39)
		}

		local hudOffset = REPENTANCE_PLUS and REP_PLUS_OFFSET or REP_HUD_OFFSET
		local hudPos = cornerOffsets[playerHUDIndex] + hudOffset[playerHUDIndex]
		return hudPos
	end

	function HudHelper.GetResourcesOffset(specificResource)
		local bethanyChecks = {
			PlayerType.PLAYER_BETHANY,
			PlayerType.PLAYER_BETHANY_B
		}
		local hasBB = HudHelper.Utils.AnyoneIsPlayerType(PlayerType.PLAYER_BLUEBABY_B)
		local offset = 0
		local hudLayout = HudHelper.Utils.GetHUDLayout(1)
		local p1TwinOffset = 0
		local poopAndBombsOffset = 0
		local bethOffset = 0
		local repPlusOffset = REPENTANCE_PLUS and -4 or 0

		--Tainted BB + Others
		HudHelper.Utils.ForEachPlayer(function(player)
			local playerType = player:GetPlayerType()
			if hasBB and playerType ~= PlayerType.PLAYER_BLUEBABY_B then
				offset = 9
				poopAndBombsOffset = 9
			end
		end)

		--J&E
		if hudLayout == HudHelper.HUDLayout.P1_MAIN_TWIN
			or hudLayout == HudHelper.HUDLayout.TWIN_COOP
		then
			offset = offset + 14
			p1TwinOffset = 14
		end

		local bethStupidOffset = 0
		--The Beths (why are they so fucking stupid)
		for i, playerType in ipairs(bethanyChecks) do
			if HudHelper.Utils.AnyoneIsPlayerType(playerType) then
				if i == 1 and poopAndBombsOffset > 0 then
					offset = offset + 2
				end
				offset = offset + 9 + bethStupidOffset
				bethOffset = bethOffset + 9 + bethStupidOffset
				bethStupidOffset = bethStupidOffset + 2
			end
		end

		--Keys or Bombs only
		if specificResource then
			if specificResource == "Bombs" then
				return Vector(0, repPlusOffset + (offset > 0 and -1 or 0))
			elseif specificResource == "Keys" then
				local keysOffset = p1TwinOffset + poopAndBombsOffset
				if poopAndBombsOffset == 0 and bethOffset > 0 then
					keysOffset = keysOffset - 2
				end
				return Vector(0, repPlusOffset + keysOffset)
			end
		end
		return Vector(0, repPlusOffset + offset)
	end

	---Gives the location of where the custom hud (turnover, throwing bag, etc) should be drawn.
	---
	---Starts its position from GetHUDOffset.
	---@param playerHUDIndex integer
	function HudHelper.GetExtraHUDOffset(playerHUDIndex)
		local REP_EXTRA_OFFSET = {
			Vector(50, 33),
			Vector(50, 50),
			Vector(50, -20),
			Vector(50, -20),
		}
		local REP_PLUS_EXTRA_OFFSET = {
			Vector(50, 29),
			Vector(50, 41),
			Vector(50, -20),
			Vector(50, -20),
		}
		local customOffset = REP_EXTRA_OFFSET
		local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)
		playerHUDIndex = math.min(4, playerHUDIndex)
		if REPENTANCE_PLUS then
			customOffset = REP_PLUS_EXTRA_OFFSET
			if playerHUDIndex == 1 and #HudHelper.GetHUDPlayers() > 2 then
				customOffset[1] = Vector(50, 41)
			end
		end
		if hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN then
			customOffset[playerHUDIndex] = Vector(80, -20)
		end
		return copyVector(customOffset[playerHUDIndex])
	end

	function HudHelper.GetItemSpecificOffset(itemID)
		return HudHelper.ItemSpecificOffset[itemID] or Vector.Zero
	end

	---@param player EntityPlayer
	---@param itemID CollectibleType
	---@param slot ActiveSlot
	function HudHelper.ShouldActiveBeDisplayed(player, itemID, slot)
		local config = Isaac.GetItemConfig()

		return not HudHelper.ShouldHideHUD()
			and not player:IsCoopGhost()
			and itemID ~= CollectibleType.COLLECTIBLE_NULL
			and player:HasCollectible(itemID, true)
			and config:GetCollectible(itemID).Type == ItemType.ITEM_ACTIVE
			and player:GetActiveItem(slot) == itemID
			and (slot <= ActiveSlot.SLOT_SECONDARY --Fine to display if you simply have the item
				or (player:GetCard(0) == 0 --Otherwise, assumed to be in first slot if no cards or pills are there.
					and player:GetPill(0) == 0
				)
			)
	end

	---Gives the location of the player's active item HUD as a vector
	---@param player EntityPlayer
	---@param playerHUDIndex integer
	---@param slot ActiveSlot
	---@return Vector
	function HudHelper.GetActiveHUDOffset(player, playerHUDIndex, slot)
		local itemSpecificOffset = HudHelper.GetItemSpecificOffset(player:GetActiveItem(slot)) + getBookOffset(player)
		local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)

		if slot <= ActiveSlot.SLOT_SECONDARY then
			playerHUDIndex = math.min(4, playerHUDIndex)
			local activeOffset = Vector(4, 0)
			local additionalOffset = Vector.Zero
			if hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN then
				additionalOffset = REPENTANCE_PLUS and Vector(143, 0) or Vector(127, 0)
			end
			if slot == ActiveSlot.SLOT_SECONDARY then
				if hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN then
					additionalOffset = REPENTANCE_PLUS and Vector(159, -4) or Vector(153, 0)
				elseif (hudLayout == HudHelper.HUDLayout.P1_MAIN_TWIN or hudLayout == HudHelper.HUDLayout.COOP) and REPENTANCE_PLUS then
					additionalOffset = Vector(-1, -4)
				else
					additionalOffset = Vector(-9, 0)
				end
			end
			if hudLayout == HudHelper.HUDLayout.TWIN_COOP then
				additionalOffset = additionalOffset + Vector(19, 4)
			end

			return activeOffset + additionalOffset + itemSpecificOffset
		else
			return HudHelper.GetPocketHUDOffset(playerHUDIndex, player) + itemSpecificOffset
		end
	end

	---@param player EntityPlayer
	---@param nameOrHUD string | HUDInfo
	---@return Vector
	function HudHelper.GetExtraHUDPadding(player, nameOrHUD)
		local playerHUDIndex = HudHelper.Utils.GetHUDPlayerNumberIndex(player)
		if playerHUDIndex == -1 then
			return Vector.Zero
		end
		local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)
		local isAtTop = playerHUDIndex <= 2
		local padding = isAtTop and HudHelper.EXTRA_HUD_PADDING_TOP or HudHelper.EXTRA_HUD_PADDING_BOTTOM

		local hud
		if type(nameOrHUD) == "table" then
			hud = nameOrHUD
		else
			for _, searchHUD in ipairs(HUD_ELEMENTS.Extra) do
				if searchHUD.Name == nameOrHUD and searchHUD.Condition(player, playerHUDIndex, hudLayout) then
					hud = searchHUD
				end
			end
		end

		local yPadding = processFuncOrValue(hud.YPadding, player, playerHUDIndex, hudLayout) + padding.Y
		if not isAtTop then
			yPadding = -yPadding
		end
		local xPadding = hud.XPadding[math.min(4, playerHUDIndex)] + padding.X
		local pos = Vector(xPadding, yPadding)

		return pos
	end

	---@param playerHUDIndex integer
	---@return Vector
	function HudHelper.GetHealthHUDOffset(playerHUDIndex)
		local healthOffset = Vector(48, 12)
		local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)
		playerHUDIndex = math.min(4, playerHUDIndex)

		if hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN
		then
			healthOffset = Vector(119, 12)
		end
		return healthOffset
	end

	---@param playerHUDIndex integer
	---@param player EntityPlayer
	---@return Vector
	function HudHelper.GetPocketHUDOffset(playerHUDIndex, player)
		local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)
		playerHUDIndex = math.min(4, playerHUDIndex)
		local isActive = player:GetCard(0) == 0 and player:GetPill(0) == 0
		local pocketPosOffset = isActive and Vector(-24, -18) or Vector(-3, 0)
		if hudLayout == HudHelper.HUDLayout.P1_MAIN_TWIN and not REPENTANCE_PLUS then
			pocketPosOffset = pocketPosOffset + (isActive and Vector(11, 41) or Vector(14, 41))
		elseif hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN then
			if isActive then
				pocketPosOffset = pocketPosOffset + (REPENTANCE_PLUS and Vector(150, 43) or Vector(160, -5))
			else
				pocketPosOffset = pocketPosOffset + (REPENTANCE_PLUS and Vector(138, 33) or Vector(160, -5))
			end
		elseif playerHUDIndex == 1 and hudLayout == HudHelper.HUDLayout.P1 then
			---Should be mindful that this is relative to bottom right HUD and should be combined with that HUD's position
			pocketPosOffset = pocketPosOffset + (REPENTANCE_PLUS and Vector(171, 27) or Vector(155, 27))
		elseif hudLayout == HudHelper.HUDLayout.TWIN_COOP then
			pocketPosOffset = pocketPosOffset + (isActive and Vector(60, 45) or Vector(48, 35))
		else
			if isActive then
				pocketPosOffset = pocketPosOffset + (REPENTANCE_PLUS and Vector(60, 45) or Vector(12, 44))
			else
				pocketPosOffset = pocketPosOffset + (REPENTANCE_PLUS and Vector(48, 35) or Vector(15, 44))
			end
			if REPENTANCE_PLUS then
				if player:GetTrinket(0) ~= 0 then
					pocketPosOffset = pocketPosOffset + Vector(13, 0)
				end
				if player:GetTrinket(1) ~= 0 then
					pocketPosOffset = pocketPosOffset + Vector(16, 0)
				end
			end
		end
		return pocketPosOffset
	end

	---@param HUDSprite Sprite
	---@param charge number
	---@param maxCharge number
	---@param position Vector
	---@function
	function HudHelper.RenderChargeBar(HUDSprite, charge, maxCharge, position)
		if HudHelper.ShouldHideHUD() or not Options.ChargeBars then
			return
		end

		if game:GetRoom():GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then
			return
		end

		local chargePercent = math.min(charge / maxCharge, 1)

		if chargePercent == 1 then
			-- ChargedHUD:IsPlaying("StartCharged") and not
			if HUDSprite:IsFinished("Charged") or HUDSprite:IsFinished("StartCharged") then
				if not HUDSprite:IsPlaying("Charged") then
					HUDSprite:Play("Charged", true)
				end
			elseif not HUDSprite:IsPlaying("Charged") then
				if not HUDSprite:IsPlaying("StartCharged") then
					HUDSprite:Play("StartCharged", true)
				end
			end
		elseif chargePercent > 0 and chargePercent < 1 then
			if not HUDSprite:IsPlaying("Charging") then
				HUDSprite:Play("Charging")
			end
			local frame = math.floor(chargePercent * 100)
			HUDSprite:SetFrame("Charging", frame)
		elseif chargePercent == 0 and not HUDSprite:IsPlaying("Disappear") and not HUDSprite:IsFinished("Disappear") then
			HUDSprite:Play("Disappear", true)
		end

		HUDSprite:Render(position)
		if Isaac.GetFrameCount() % 2 == 0 and not game:IsPaused() then
			HUDSprite:Update()
		end
	end

	--#endregion

	--#region HUD Element Functions

	---@param params HUDInfo | HUDInfo_Active | HUDInfo_Health | HUDInfo_PocketItem | HUDInfo_Extra
	---@param hudType? HUDType
	function HudHelper.RegisterHUDElement(params, hudType)
		local hudElements = HudHelper.HUDTypeToTable[hudType]
		if not hudElements then hudElements = HudHelper.HUD_ELEMENTS.Base end

		local targetIndex = #hudElements + 1
		for i, hud in ipairs(hudElements) do
			if hud.Name == params.Name then
				targetIndex = i
			end
		end
		local xPadding = checkValueType("XPadding", params.XPadding, "number", "table", "nil")

		if params.XPadding then
			if type(xPadding) == "number" then
				xPadding = {
					xPadding,
					xPadding,
					xPadding,
					xPadding,
				}
			end
		end

		hudElements[targetIndex] = {
			Name = checkValueType("Name", params.Name, "string"),
			Priority = checkValueType("Priority", params.Priority, "number"),
			Condition = checkValueType("Condition", params.Condition, "function"),
			OnRender = checkValueType("OnRender", params.OnRender, "function"),
			XPadding = xPadding,
			YPadding = checkValueType("YPadding", params.YPadding, "number", "function", "nil"),
			BypassGhostBaby = checkValueType("BypassGhostBaby", params.BypassGhostBaby, "boolean", "nil"),
			PreRenderCallback = checkValueType("PreRenderCallback", params.PreRenderCallback, "boolean", "nil")
		}

		table.sort(hudElements, function(a, b)
			return a.Priority < b.Priority
		end)
	end

	--- Removes all HUD elements with the given name.
	---@param name string @The string you used when registering your HUD element.
	---@param hudType HUDType
	function HudHelper.UnregisterHUDElement(name, hudType)
		local hudElements = HudHelper.HUDTypeToTable[hudType]
		if not hudElements then return end

		for i = #hudElements, 1, -1 do
			if hudElements[i].Name == name then
				table.remove(hudElements, i)
			end
		end
	end

	--#endregion

	--#region Render HUD Elements

	---HUDInfo object of last HUD element that was rendered, indexed by player number
	HudHelper.LastAppliedHUD = {
		Base = {}, ---@type table<integer, HUDInfo>
		Actives = {}, ---@type table<integer, HUDInfo_Active>
		Health = {}, ---@type table<integer, HUDInfo_Health>
		PocketItems = {}, ---@type table<integer, HUDInfo_PocketItem>
		Extra = {}, ---@type table<integer, HUDInfo_Extra>
	}

	local numPlayers = 0
	local TWIN_COOP_OFFSET = Vector(0, 32)

	---@param playerIndex integer
	local function addActivePlayers(playerIndex)
		local numHudPlayers = 0
		for _, _ in ipairs(HudHelper.HUDPlayers) do
			numHudPlayers = numHudPlayers + 1
		end
		local player = Isaac.GetPlayer(playerIndex)
		if not player
			or player.Parent
			or numHudPlayers == 4
			or GetPtrHash(player:GetMainTwin()) ~= GetPtrHash(player)
		then
			return
		end

		local hudPlayer = {}
		HudHelper.HUDPlayers[numHudPlayers + 1] = hudPlayer
		table.insert(hudPlayer, EntityPtr(player))
		local twinPlayer = player:GetOtherTwin()

		if not condensedCoopHUD
			and #HudHelper.HUDPlayers == 1
			and canAddTwinHUD(player)
		then
			HudHelper.HUDPlayers[5] = {}
			--I fucking hate this game because P4 can take up the same corner as P1 Esau
			--So I'm doing this in order to give both huds different layouts
			HudHelper.HUDPlayers[5][1] = EntityPtr(twinPlayer)
		end
		if REPENTANCE_PLUS
			and (#HudHelper.HUDPlayers > 1 or condensedCoopHUD)
			and canAddTwinHUD(player)
		then
			table.insert(hudPlayer, EntityPtr(twinPlayer))
		end
	end

	function HudHelper.GetHUDPlayers()
		local players = {}
		for _, hudPlayer in pairs(HudHelper.HUDPlayers) do
			for _, entityPtr in pairs(hudPlayer) do
				local player = tryGetPlayerFromPtr(entityPtr)
				if player then
					table.insert(players, player)
				end
			end
		end
		return players
	end

	---@param player EntityPlayer
	---@param playerHUDIndex integer
	---@param hudLayout HUDLayout
	---@param pos Vector
	---@param hud HUDInfo
	local function renderBaseHUDs(player, playerHUDIndex, hudLayout, pos, hud)
		hud.OnRender(player, playerHUDIndex, hudLayout, pos)
		HudHelper.LastAppliedHUD.Base[playerHUDIndex] = hud
	end

	---@param player EntityPlayer
	---@param playerHUDIndex integer
	---@param hudLayout HUDLayout
	---@param pos Vector
	---@param hud HUDInfo_Active
	local function renderActiveHUDs(player, playerHUDIndex, hudLayout, pos, hud, i)
		if REPENTOGON then return end
		for slot = ActiveSlot.SLOT_POCKET, ActiveSlot.SLOT_PRIMARY, -1 do
			local cornerHUD = math.min(4, playerHUDIndex)
			if slot == ActiveSlot.SLOT_POCKET
				and playerHUDIndex == 1
				and hudLayout == HudHelper.HUDLayout.P1
			then
				cornerHUD = 4
			end

			pos = HudHelper.GetHUDPosition(cornerHUD) + HudHelper.GetActiveHUDOffset(player, playerHUDIndex, slot)
			if i == 2 then
				pos = pos + TWIN_COOP_OFFSET
			end
			local scale = 1
			local alpha = 1

			if hudLayout == HudHelper.HUDLayout.P1_MAIN_TWIN
				or hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN
				or hudLayout == HudHelper.HUDLayout.TWIN_COOP
			then
				if REPENTANCE_PLUS then
					if slot == ActiveSlot.SLOT_SECONDARY then
						scale = 0.245
					else
						scale = 0.5
					end
				else
					if slot == ActiveSlot.SLOT_SECONDARY then
						scale = 0.5
					end
				end
				local dropTrigger = not game:IsPaused()
					and player.ControlsEnabled
					and Input.IsActionPressed(ButtonAction.ACTION_DROP, player.ControllerIndex)
				if Options.JacobEsauControls and Options.JacobEsauControls == 1 then
					alpha = i == 1 and 1 or 0.25
					if dropTrigger then
						alpha = i == 1 and 0.25 or 1
					end
				elseif not Options.JacobEsauControls or Options.JacobEsauControls == 0 then
					alpha = slot < ActiveSlot.SLOT_POCKET and 1 or 0.25
					if dropTrigger then
						alpha = slot < ActiveSlot.SLOT_POCKET and 0.25 or 1
					end
				end
			elseif slot == ActiveSlot.SLOT_SECONDARY
				or slot == ActiveSlot.SLOT_POCKET and (condensedCoopHUD or playerHUDIndex ~= 1)
			then
				scale = 0.5
			end
			if not hud.Condition(player, playerHUDIndex, hudLayout, slot) then goto continue end
			hud.OnRender(player, playerHUDIndex, hudLayout, pos, alpha, scale, slot)
			HudHelper.LastAppliedHUD.Actives[playerHUDIndex] = hud
			::continue::
		end
	end

	---@param player EntityPlayer
	---@param slot ActiveSlot
	---@param offset Vector
	---@param alpha number
	---@param scale number
	---@param isPreCallback boolean
	local function renderActiveHUDs_REPENTOGON(_, player, slot, offset, alpha, scale, isPreCallback)
		if not player:Exists()
			or player:GetActiveItem(slot) == CollectibleType.COLLECTIBLE_NULL
			or HudHelper.ShouldHideHUD()
			or player.Variant ~= 0
			or not HudHelper.HUDPlayers[1]
			or not HudHelper.HUDPlayers[1][1]
			or not tryGetPlayerFromPtr(HudHelper.HUDPlayers[1][1])
		then
			return
		end
		local playerHUDIndex = HudHelper.Utils.GetHUDPlayerNumberIndex(player)
		if playerHUDIndex == -1 then return end
		local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)

		for _, hud in ipairs(HUD_ELEMENTS.Actives) do
			if (not player:IsCoopGhost() or hud.BypassGhostBaby)
				and hud.Condition(player, playerHUDIndex, hudLayout, slot)
				and ((not hud.PreRenderCallback and not isPreCallback) or (hud.PreRenderCallback and isPreCallback))
			then
				hud.OnRender(player, playerHUDIndex, hudLayout, offset, alpha, scale, slot)
				HudHelper.LastAppliedHUD.Actives[playerHUDIndex] = hud
			end
		end
	end

	---@param player EntityPlayer
	---@param playerHUDIndex integer
	---@param hudLayout HUDLayout
	---@param pos Vector
	---@param hud HUDInfo_Health
	local function renderHeartHUDs(player, playerHUDIndex, hudLayout, pos, hud)
		if REPENTOGON then return end
		local maxColumns = 6

		if not REPENTANCE_PLUS
			and (
				hudLayout == HudHelper.HUDLayout.COOP
				or hudLayout == HudHelper.HUDLayout.STRAWMAN_HEARTS
			) then
			maxColumns = 3
		end
		hud.OnRender(player, playerHUDIndex, hudLayout, pos, maxColumns)
		HudHelper.LastAppliedHUD.Health[playerHUDIndex] = hud
	end

	---@param offset Vector
	---@param sprite Sprite
	---@param pos Vector
	---@param unkFloat number
	---@param player EntityPlayer
	---@param isPreCallback boolean
	local function renderHeartHUDs_REPENTOGON(_, offset, sprite, pos, unkFloat, player, isPreCallback)
		if not player:Exists()
			or HudHelper.ShouldHideHUD()
			or player.Variant ~= 0
			or not HudHelper.HUDPlayers[1]
			or not HudHelper.HUDPlayers[1][1]
			or not tryGetPlayerFromPtr(HudHelper.HUDPlayers[1][1])
		then
			return
		end

		local maxColumns = 6
		local playerHUDIndex = HudHelper.Utils.GetHUDPlayerNumberIndex(player)
		local hudLayout = playerHUDIndex == -1 and HudHelper.HUDLayout.STRAWMAN_HEARTS or
			HudHelper.Utils.GetHUDLayout(playerHUDIndex)

		if not REPENTANCE_PLUS
			and (
				hudLayout == HudHelper.HUDLayout.COOP
				or hudLayout == HudHelper.HUDLayout.STRAWMAN_HEARTS
			) then
			maxColumns = 3
		end

		for _, hud in ipairs(HUD_ELEMENTS.Health) do
			if (not player:IsCoopGhost() or hud.BypassGhostBaby)
				and hud.Condition(player, playerHUDIndex, hudLayout)
				and ((not hud.PreRenderCallback and not isPreCallback) or (hud.PreRenderCallback and isPreCallback))
			then
				hud.OnRender(player, playerHUDIndex, hudLayout, pos, maxColumns)
				HudHelper.LastAppliedHUD.Health[playerHUDIndex] = hud
			end
		end
	end

	---@param player EntityPlayer
	---@param playerHUDIndex integer
	---@param hudLayout HUDLayout
	---@param pos Vector
	---@param hud HUDInfo_PocketItem
	local function renderPocketItemHUDs(player, playerHUDIndex, hudLayout, pos, hud, i)
		local scale = 1
		local alpha = 1

		if hudLayout == HudHelper.HUDLayout.P1_MAIN_TWIN
			or hudLayout == HudHelper.HUDLayout.P1_OTHER_TWIN
			or hudLayout == HudHelper.HUDLayout.TWIN_COOP
		then
			if REPENTANCE_PLUS then
				scale = 0.5
			end
			local dropTrigger = not game:IsPaused()
				and player.ControlsEnabled
				and Input.IsActionPressed(ButtonAction.ACTION_DROP, player.ControllerIndex)
			if Options.JacobEsauControls and Options.JacobEsauControls == 1 then
				alpha = i == 1 and 1 or 0.25
				if dropTrigger then
					alpha = i == 1 and 0.25 or 1
				end
			elseif not Options.JacobEsauControls or Options.JacobEsauControls == 0 then
				alpha = 0.25
				if dropTrigger then
					alpha = 1
				end
			end
		elseif condensedCoopHUD or playerHUDIndex ~= 1 then
			scale = 0.5
		end

		hud.OnRender(player, playerHUDIndex, hudLayout, pos, alpha, scale)
		HudHelper.LastAppliedHUD.PocketItems[playerHUDIndex] = hud
	end

	local extraYPadding = 0

	---@param player EntityPlayer
	---@param playerHUDIndex integer
	---@param hudLayout HUDLayout
	---@param pos Vector
	---@param hud HUDInfo_Extra
	local function renderExtraHUDs(player, playerHUDIndex, hudLayout, pos, hud)
		pos = pos + Vector(0, extraYPadding)
		local customPadding = HudHelper.GetExtraHUDPadding(player, hud)
		hud.OnRender(player, playerHUDIndex, hudLayout, pos + Vector(customPadding.X, 0))
		HudHelper.LastAppliedHUD.Extra[playerHUDIndex] = hud
		extraYPadding = extraYPadding + customPadding.Y
	end

	function HudHelper.PopulateHUDPlayers()
		HudHelper.HUDPlayers = {}
		local numHUDPlayers = 0
		condensedCoopHUD = false

		if REPENTANCE_PLUS then
			for playerIndex = 0, game:GetNumPlayers() - 1 do
				local player = Isaac.GetPlayer(playerIndex)
				if player
					and not player.Parent
					and not HudHelper.HUDTwinBlacklist[player:GetPlayerType()]
					and GetPtrHash(player:GetMainTwin()) == GetPtrHash(player)
				then
					numHUDPlayers = numHUDPlayers + 1

					if numHUDPlayers > 1 then
						if canAddTwinHUD(player) then
							numHUDPlayers = numHUDPlayers + 1
						end
						if numHUDPlayers >= 3 then
							condensedCoopHUD = true
						end
					end
				end
			end
		end
		for playerIndex = 0, game:GetNumPlayers() - 1 do
			addActivePlayers(playerIndex)
			numPlayers = game:GetNumPlayers()
		end
	end

	function HudHelper.RenderHUDs(isPreCallback)
		if HudHelper.ShouldHideHUD() then
			return
		end

		if not HudHelper.HUDPlayers[1]
			or not HudHelper.HUDPlayers[1][1]
			or tryGetPlayerFromPtr(HudHelper.HUDPlayers[1][1]) == nil
			or numPlayers ~= game:GetNumPlayers()
		then
			HudHelper.PopulateHUDPlayers()
		end
		for playerHUDIndex, hudPlayer in pairs(HudHelper.HUDPlayers) do
			for i, entityPtr in pairs(hudPlayer) do
				local player = tryGetPlayerFromPtr(entityPtr)
				if not player then goto continue end
				local hudLayout = HudHelper.Utils.GetHUDLayout(playerHUDIndex)

				for hudName, hudTable in pairs(HudHelper.HUD_ELEMENTS) do
					extraYPadding = 0
					for _, hud in ipairs(hudTable) do
						if not ((not player:IsCoopGhost() or hud.BypassGhostBaby)
								and (hudName ~= "Actives" and hud.Condition(player, playerHUDIndex, hudLayout))
								and ((not hud.PreRenderCallback and not isPreCallback) or (hud.PreRenderCallback and isPreCallback))
							) then
							goto continue2
						end
						local pos = HudHelper.GetHUDPosition(playerHUDIndex)
						if i == 2 then
							pos = pos + TWIN_COOP_OFFSET
						end
						if hudName == "Base" and i ~= 2 then
							---@cast hud HUDInfo
							renderBaseHUDs(player, playerHUDIndex, hudLayout, pos, hud)
						elseif hudName == "Actives" then
							---@cast hud HUDInfo_Active
							renderActiveHUDs(player, playerHUDIndex, hudLayout, pos, hud, i)
						elseif hudName == "PocketItems" then
							---@cast hud HUDInfo_PocketItem
							if hudLayout == HudHelper.HUDLayout.P1 and not condensedCoopHUD then
								pos = HudHelper.GetHUDPosition(4)
								if i == 2 then
									pos = pos + TWIN_COOP_OFFSET
								end
							end
							pos = pos + HudHelper.GetPocketHUDOffset(playerHUDIndex, player)
							renderPocketItemHUDs(player, playerHUDIndex, hudLayout, pos, hud, i)
						elseif hudName == "Health" then
							---@cast hud HUDInfo_Health
							pos = pos + HudHelper.GetHealthHUDOffset(playerHUDIndex)
							if i == 2 then
								--WHYYYYY ARE HEARTS NOT OFFSET THE SAME AMOUNT AS ACTIVES WHYYYYYY
								pos = pos + Vector(0, 2)
							end
							renderHeartHUDs(player, playerHUDIndex, hudLayout, pos, hud)
						elseif hudName == "Extra" then
							pos = pos + HudHelper.GetExtraHUDOffset(playerHUDIndex)
							---@cast hud HUDInfo_Extra
							renderExtraHUDs(player, playerHUDIndex, hudLayout, pos, hud)
						end
						::continue2::
					end
				end

				::continue::
			end
		end
		if #HudHelper.HUD_ELEMENTS.Health == 0 then return end
		for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_PLAYER)) do
			local player = ent:ToPlayer()
			if player and player.Parent and not player:IsDead() and player.Variant == 0 then
				local playerPos = Isaac.WorldToRenderPosition(player.Position + player.PositionOffset)
				local heartOffset = Vector(0, (-30 * player.SpriteScale.Y))
				local flyingOffset = player:IsFlying() and Vector(0, -4) or Vector.Zero
				local position = playerPos + heartOffset + flyingOffset
				local numHearts = (player:GetEffectiveMaxHearts() + player:GetSoulHearts()) / 2
				local xOffset = 0
				for i = 1, math.min(6, numHearts) do
					xOffset = 5 * (i - 1)
				end
				position = position - Vector(xOffset, 0)

				for _, hud in ipairs(HudHelper.HUD_ELEMENTS.Health) do
					if hud.Condition(player, -1, HudHelper.HUDLayout.STRAWMAN_HEARTS)
						and ((not hud.PreRenderCallback and not isPreCallback) or (hud.PreRenderCallback and isPreCallback))
					then
						renderHeartHUDs(player, -1, HudHelper.HUDLayout.STRAWMAN_HEARTS, position, hud)
					end
				end
			end
		end
	end

	-- Unregister previous callbacks
	for callback, funcs in pairs(HudHelper.AddedCallbacks) do
		for i = 1, #funcs do
			HudHelper:RemoveCallback(callback, funcs[i])
		end
	end

	local function preRenderHeartHUDs_REPENTOGON(_, offset, sprite, pos, unkFloat, player)
		renderHeartHUDs_REPENTOGON(_, offset, sprite, pos, unkFloat, player, true)
	end

	local function postRenderHeartHUDs_REPENTOGON(_, offset, sprite, pos, unkFloat, player)
		renderHeartHUDs_REPENTOGON(_, offset, sprite, pos, unkFloat, player, false)
	end

	local function preRenderActiveHUDs_REPENTOGON(_, player, slot, offset, alpha, scale)
		renderActiveHUDs_REPENTOGON(_, player, slot, offset, alpha, scale, true)
	end

	local function postRenderActiveHUDs_REPENTOGON(_, player, slot, offset, alpha, scale)
		renderActiveHUDs_REPENTOGON(_, player, slot, offset, alpha, scale, false)
	end

	local function resetHUDPlayersOnLazBBirthrightFlip(_, _, _, player)
		local playerType = player:GetPlayerType()
		if (playerType == PlayerType.PLAYER_LAZARUS_B
				or playerType == PlayerType.PLAYER_LAZARUS2_B)
			and player:GetOtherTwin()
		then
			HudHelper.PopulateHUDPlayers()
		end
	end

	-- Register new callbacks
	if REPENTOGON then
		HudHelper:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, function() HudHelper.RenderHUDs(false) end)
		table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_POST_HUD_RENDER], HudHelper.RenderHUDs)
		HudHelper:AddCallback(ModCallbacks.MC_PRE_PLAYERHUD_RENDER_ACTIVE_ITEM, preRenderActiveHUDs_REPENTOGON)
		table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM],
			preRenderActiveHUDs_REPENTOGON)
		HudHelper:AddCallback(ModCallbacks.MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM, postRenderActiveHUDs_REPENTOGON)
		table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM],
			postRenderActiveHUDs_REPENTOGON)
		HudHelper:AddCallback(ModCallbacks.MC_PRE_PLAYERHUD_RENDER_HEARTS, preRenderHeartHUDs_REPENTOGON)
		table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_PRE_PLAYERHUD_RENDER_HEARTS], preRenderHeartHUDs_REPENTOGON)
		HudHelper:AddCallback(ModCallbacks.MC_POST_PLAYERHUD_RENDER_HEARTS, postRenderHeartHUDs_REPENTOGON)
		table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_POST_PLAYERHUD_RENDER_HEARTS],
			postRenderHeartHUDs_REPENTOGON)
	else
		local function getShaderParams(_, name)
			if name == emptyShaderName then
				HudHelper.RenderHUDs(false)
			end
		end
		HudHelper:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, getShaderParams)
		table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_GET_SHADER_PARAMS], getShaderParams)
	end

	HudHelper:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, CallbackPriority.LATE,
		function() HudHelper.RenderHUDs(true) end)
	HudHelper:AddCallback(ModCallbacks.MC_USE_ITEM, resetHUDPlayersOnLazBBirthrightFlip, CollectibleType
	.COLLECTIBLE_FLIP)
	table.insert(HudHelper.AddedCallbacks[ModCallbacks.MC_USE_ITEM], resetHUDPlayersOnLazBBirthrightFlip)

	--#endregion

	--Register HUD elements. Previous versions of these get overwritten.
	HudHelper.RegisterHUDElement({
		Name = "Tainted Isaac",
		Priority = HudHelper.Priority.VANILLA,
		XPadding = 0,
		YPadding = 20,
		Condition = function(player, playerHUDIndex)
			return player:GetPlayerType() == PlayerType.PLAYER_ISAAC_B
				and (REPENTANCE_PLUS or playerHUDIndex == 1)
		end,
		OnRender = function() end, -- handled by the game
	}, HudHelper.HUDType.EXTRA)
	HudHelper.RegisterHUDElement({
		Name = "Tainted Blue Baby",
		Priority = HudHelper.Priority.VANILLA,
		XPadding = 0,
		YPadding = 17,
		Condition = function(player, playerHUDIndex)
			return player:GetPlayerType() == PlayerType.PLAYER_BLUEBABY_B
				and (REPENTANCE_PLUS or playerHUDIndex == 1)
		end,
		OnRender = function() end, -- handled by the game
	}, HudHelper.HUDType.EXTRA)
	HudHelper.RegisterHUDElement({
		Name = "P1 Main Twin",
		Priority = HudHelper.Priority.VANILLA,
		XPadding = 0,
		YPadding = 16,
		Condition = function(player, playerHUDIndex, hudLayout)
			return hudLayout == HudHelper.P1_MAIN_TWIN
		end,
		OnRender = function() end, -- handled by the game
	}, HudHelper.HUDType.EXTRA)
	HudHelper.RegisterHUDElement({
		Name = "P1 Other Twin",
		Priority = HudHelper.Priority.VANILLA,
		XPadding = 15,
		YPadding = 0,
		Condition = function(player, playerHUDIndex, hudLayout)
			return hudLayout == HudHelper.P1_OTHER_TWIN
		end,
		OnRender = function() end, -- handled by the game
	}, HudHelper.HUDType.EXTRA)
	HudHelper.RegisterHUDElement({
		Name = "Heart Cap",
		Priority = HudHelper.Priority.VANILLA,
		XPadding = 0,
		YPadding = function(player)
			if HudHelper.Utils.GetEffectiveMaxHealth(player) > 36 then
				return 20
			else
				return 10
			end
		end,
		Condition = function(player)
			--Maybe do something if they're not P1?
			return HudHelper.Utils.GetEffectiveMaxHealth(player) > 24
		end,
		OnRender = function() end, -- handled by the game
	}, HudHelper.HUDType.EXTRA)

	--EID support. Adds a custom position modifier to work with other HUD elements registered under HudHelper
	--If any elements are active, gets rid of EID's own position modifiers as HudHelper already accounts for them
	--If none are active, resets the modifier
	HudHelper.RegisterHUDElement({
		Name = "Reset EID",
		Priority = HudHelper.Priority.EID,
		XPadding = 0,
		YPadding = 0,
		Condition = function(player, playerHUDIndex)
			return EID
				and game:GetFrameCount() > 0
				and EID.player
				and EID.player.FrameCount > 0
				and playerHUDIndex == 1
				and not HudHelper.LastAppliedHUD.Extra[1]
				and EID.PositionModifiers["HudHelper"]
				and EID.PositionModifiers["HudHelper"].Y ~= 0
		end,
		OnRender = function()
			EID:addTextPosModifier("HudHelper", Vector.Zero)
		end
	}, HudHelper.HUDType.EXTRA)

	HudHelper.RegisterHUDElement({
		Name = "EID",
		Priority = HudHelper.Priority.EID,
		XPadding = 0,
		YPadding = 0,
		Condition = function(player, playerHUDIndex)
			return EID
				and game:GetFrameCount() > 0
				and EID.player
				and EID.player.FrameCount > 0
				and playerHUDIndex == 1
				and HudHelper.LastAppliedHUD.Extra[1]
				and HudHelper.LastAppliedHUD.Extra[1].Name ~= "Reset EID"
		end,
		OnRender = function(_, _, _, position)
			local posYModifier = 0
			local offset = -40
			local vanillaOffsets = {
				"Tainted HUD",
				"J&E HUD",
				"18 Heart HUD",
				"24 Heart HUD"
			}
			for _, offsetName in ipairs(vanillaOffsets) do
				if EID.PositionModifiers[offsetName] then
					offset = offset - EID.PositionModifiers[offsetName].Y
				end
			end

			posYModifier = position.Y + offset

			EID:addTextPosModifier(
				"HudHelper",
				Vector(0, math.max(0, posYModifier))
			)
		end
	}, HudHelper.HUDType.EXTRA)
end

if HudHelper and (VERSION > HudHelper.Version or FORCE_VERSION_UPDATE) then
	InitFunctions()
	HudHelper.Version = VERSION
else
	if HudHelper then
		CACHED_CALLBACKS = HudHelper.Callbacks.RegisteredCallbacks
		CACHED_ELEMENTS = HudHelper.HUD_ELEMENTS
	end
	HudHelper = InitMod()
	InitFunctions()
end
