_G.HudHelperExample = RegisterMod("HudHelper Example", 1)
include("src_hudhelper.hud_helper")

HudHelper.RegisterHUDElement({
	Name = "HudHelperExample",
	Priority = HudHelper.Priority.NORMAL,
	Condition = function(player, playerHUDIndex, hudLayout)
		return playerHUDIndex == 1
	end,
	OnRender = function(player, playerHUDIndex, hudLayout, position)
		position = position + Vector(50, 50)
		Isaac.RenderText("Rendering Text on the HUD!", position.X, position.Y, 1, 1, 1, 1)
	end,
	BypassGhostBaby = true,
}, HudHelper.HUDType.BASE)