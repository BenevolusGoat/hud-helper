_G.HudHelperExample = RegisterMod("HudHelper Example", 1)
include("src_hudhelper.hud_helper")

HudHelper.RegisterHUDElement({
	Name = "HudHelperExample",
	Priority = HudHelper.Priority.NORMAL,
	XPadding = 0,
	YPadding = 30,
	Condition = function(player, playerHUDIndex, hudLayout)
		return playerHUDIndex == 1
	end,
	OnRender = function(player, playerHUDIndex, hudLayout, position)
		Isaac.RenderText("Rendering Text on the HUD!", position.X, position.Y, 1, 1, 1, 1)
	end,
	BypassGhostBaby = true,
}, HudHelper.HUDType.EXTRA)