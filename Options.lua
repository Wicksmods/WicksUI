local addonName, ns = ...
local E   = ns.E
local WUI = ns.WUI

local function reloadPrompt()
    if E and E.StaticPopup_Show then
        E:StaticPopup_Show("PRIVATE_RL")
    elseif StaticPopup_Show then
        StaticPopup_Show("CONFIRM_RELOAD_UI")
    end
end

-- Builds the Wick's UI option group under ElvUI → Plugins. Called by ElvUI
-- via EP:RegisterPlugin(addonName, ns.AddOptions) — see Init.lua.
function ns.AddOptions()
    if not (E and E.Options and E.Options.args) then return end

    E.Options.args.WicksUI = {
        order  = 100,
        type   = "group",
        name   = WUI.title,
        childGroups = "tab",
        args = {
            header = {
                order = 1,
                type  = "header",
                name  = ("Wick's UI v%s — theme for ElvUI"):format(WUI.version or "0.1.0"),
            },
            description = {
                order = 2,
                type  = "description",
                name  = "Wick brand palette + 10/2 fel-green L-bracket chrome on ElvUI panels. Brackets apply automatically; the palette is opt-in via the button below (writes to your current ElvUI profile and prompts a reload).",
                fontSize = "medium",
            },

            brackets = {
                order = 10,
                type  = "group",
                name  = "Brackets",
                inline = true,
                args = {
                    enabled = {
                        order = 1,
                        type  = "toggle",
                        name  = "Show L-brackets",
                        desc  = "Adds 10x2 fel-green L-shaped corner brackets to the chat, datatext, and minimap panels.",
                        get   = function() return WUI.db.brackets.enabled end,
                        set   = function(_, v)
                            WUI.db.brackets.enabled = v
                            if v then
                                ns.Brackets:ApplyAll()
                            else
                                ns.Brackets:RemoveAll()
                            end
                        end,
                    },
                    size = {
                        order = 2,
                        type  = "range",
                        name  = "Arm length",
                        desc  = "Length of each L-bracket arm in pixels.",
                        min   = 4, max = 24, step = 1,
                        get   = function() return WUI.db.brackets.size end,
                        set   = function(_, v)
                            WUI.db.brackets.size = v
                            ns.Brackets:RemoveAll()
                            if WUI.db.brackets.enabled then ns.Brackets:ApplyAll() end
                        end,
                    },
                    thickness = {
                        order = 3,
                        type  = "range",
                        name  = "Arm thickness",
                        desc  = "Thickness of each L-bracket arm in pixels.",
                        min   = 1, max = 6, step = 1,
                        get   = function() return WUI.db.brackets.thickness end,
                        set   = function(_, v)
                            WUI.db.brackets.thickness = v
                            ns.Brackets:RemoveAll()
                            if WUI.db.brackets.enabled then ns.Brackets:ApplyAll() end
                        end,
                    },
                    reapply = {
                        order = 4,
                        type  = "execute",
                        name  = "Re-apply brackets",
                        desc  = "Re-attach brackets after a profile change or panel layout swap.",
                        func  = function()
                            ns.Brackets:RemoveAll()
                            if WUI.db.brackets.enabled then ns.Brackets:ApplyAll() end
                        end,
                    },
                },
            },

            theme = {
                order = 20,
                type  = "group",
                name  = "Palette",
                inline = true,
                args = {
                    status = {
                        order = 1,
                        type  = "description",
                        name  = function()
                            if WUI.db.theme.applied then
                                return "|cff4FC778Wick palette is applied to this profile.|r"
                            else
                                return "|cffD4C8A1Wick palette has not been applied to this profile.|r"
                            end
                        end,
                        fontSize = "medium",
                    },
                    apply = {
                        order = 2,
                        type  = "execute",
                        name  = "Apply Wick palette",
                        desc  = "Writes the locked Wick palette (border, backdrop, accent) and the flat 'ElvUI Norm' statusbar texture into your current ElvUI profile, then prompts a UI reload.",
                        func  = function()
                            if ns.Theme:Apply() then
                                WUI:Print("Wick palette applied. Reload to finish.")
                                reloadPrompt()
                            end
                        end,
                    },
                    revert = {
                        order = 3,
                        type  = "execute",
                        name  = "Revert palette",
                        desc  = "Restores ElvUI's default border / backdrop / accent colors. Other settings are left untouched.",
                        func  = function()
                            if ns.Theme:Revert() then
                                WUI:Print("Reverted to ElvUI defaults. Reload to finish.")
                                reloadPrompt()
                            end
                        end,
                    },
                },
            },
        },
    }
end
