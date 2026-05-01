local addonName, ns = ...
local E   = ns.E
local WUI = ns.WUI

local Theme = {}
ns.Theme = Theme

-- Convert a {r,g,b,a} array (Wick palette form) to ElvUI's {r=,g=,b=,a=}
-- color table form, which is what E.db.general.* expects.
local function toElvColor(c)
    return { r = c[1], g = c[2], b = c[3], a = c[4] or 1 }
end

-- Writes the locked Wick palette into the user's current ElvUI profile and
-- pushes the changes through ElvUI's update funnels. Caller is responsible
-- for prompting ReloadUI (some color/texture changes only fully take effect
-- after a UI reload, especially statusbar texture changes on existing bars).
function Theme:Apply()
    if not E or not E.db or not E.db.general then return false end

    local p = WUI.palette

    E.db.general.bordercolor       = toElvColor(p.border)
    E.db.general.backdropcolor     = toElvColor(p.void)
    -- backdropfadecolor uses translucency (matches our ~0.85 panel opacity).
    local fade = { p.void[1], p.void[2], p.void[3], 0.85 }
    E.db.general.backdropfadecolor = toElvColor(fade)
    E.db.general.valuecolor        = toElvColor(p.fel)

    -- Statusbar / panel textures. "ElvUI Norm" is a flat 1px texture that
    -- ships with ElvUI itself, which matches the Wick "no gradient" rule.
    if E.db.general.uitexture       ~= nil then E.db.general.uitexture       = "ElvUI Norm" end
    if E.db.general.normTex         ~= nil then E.db.general.normTex         = "ElvUI Norm" end
    if E.db.general.glossTex        ~= nil then E.db.general.glossTex        = "ElvUI Norm" end
    if E.db.unitframe and E.db.unitframe.statusbar ~= nil then
        E.db.unitframe.statusbar = "ElvUI Norm"
    end

    -- Push changes through ElvUI's updaters. Not every TBC build of ElvUI
    -- exposes every one of these — guarded calls so missing ones are no-ops.
    if E.UpdateMedia          then E:UpdateMedia()          end
    if E.UpdateBorderColors   then E:UpdateBorderColors()   end
    if E.UpdateBackdropColors then E:UpdateBackdropColors() end
    if E.UpdateUnitFrames     then E:UpdateUnitFrames()     end

    if WUI.db then WUI.db.theme.applied = true end
    return true
end

-- Reverts the four palette fields to ElvUI defaults. Anything else the user
-- changed before clicking Apply is left untouched.
function Theme:Revert()
    if not E or not E.db or not E.db.general then return false end

    -- ElvUI's documented defaults (see ElvUI/Core/General/Defaults.lua).
    E.db.general.bordercolor       = { r = 0.10, g = 0.10, b = 0.10 }
    E.db.general.backdropcolor     = { r = 0.10, g = 0.10, b = 0.10 }
    E.db.general.backdropfadecolor = { r = 0.05, g = 0.05, b = 0.05, a = 0.80 }
    E.db.general.valuecolor        = { r = 1.00, g = 0.82, b = 0.00 }

    if E.UpdateMedia          then E:UpdateMedia()          end
    if E.UpdateBorderColors   then E:UpdateBorderColors()   end
    if E.UpdateBackdropColors then E:UpdateBackdropColors() end

    if WUI.db then WUI.db.theme.applied = false end
    return true
end
