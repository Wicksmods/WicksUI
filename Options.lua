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

            quests = {
                order = 15,
                type  = "group",
                name  = "Quest Log & Tracker",
                inline = true,
                args = {
                    trackerEnabled = {
                        order = 1,
                        type  = "toggle",
                        name  = "Show quest tracker",
                        desc  = "Display the Wick quest tracker HUD on login. Replaces Blizzard's default watch frame.",
                        get   = function() return WUI.db.questtracker.enabled end,
                        set   = function(_, v)
                            WUI.db.questtracker.enabled = v
                            if v then
                                if ns.QuestTracker then ns.QuestTracker:Show() end
                            else
                                if ns.QuestTracker then ns.QuestTracker:Hide() end
                            end
                        end,
                    },
                    zoneOnly = {
                        order = 2,
                        type  = "toggle",
                        name  = "Show current zone only",
                        desc  = "Tracker only shows quests from your current zone.",
                        get   = function() return WUI.db.questtracker.showZoneOnly end,
                        set   = function(_, v)
                            WUI.db.questtracker.showZoneOnly = v
                            if ns.QuestTracker then ns.QuestTracker:Refresh() end
                        end,
                    },
                    maxQuests = {
                        order = 3,
                        type  = "range",
                        name  = "Max tracked quests",
                        desc  = "Maximum number of quests shown in the tracker HUD.",
                        min   = 1, max = 20, step = 1,
                        get   = function() return WUI.db.questtracker.maxQuests end,
                        set   = function(_, v)
                            WUI.db.questtracker.maxQuests = v
                            if ns.QuestTracker then ns.QuestTracker:Refresh() end
                        end,
                    },
                    trackerAlpha = {
                        order = 4,
                        type  = "range",
                        name  = "Tracker opacity",
                        desc  = "Transparency of the quest tracker HUD.",
                        min   = 0.2, max = 1.0, step = 0.05,
                        isPercent = true,
                        get   = function() return WUI.db.questtracker.alpha end,
                        set   = function(_, v)
                            WUI.db.questtracker.alpha = v
                            if ns.QuestTracker and ns.QuestTracker.frame then
                                ns.QuestTracker.frame:SetAlpha(v)
                            end
                        end,
                    },
                    openLog = {
                        order = 5,
                        type  = "execute",
                        name  = "Open quest log",
                        desc  = "Opens Wick's Quest Log panel.",
                        func  = function()
                            if ns.QuestLog then ns.QuestLog:Show() end
                        end,
                    },
                    resetPositions = {
                        order = 6,
                        type  = "execute",
                        name  = "Reset positions",
                        desc  = "Resets both the quest log and tracker to their default screen positions.",
                        func  = function()
                            WUI.db.questlog.x     = nil
                            WUI.db.questlog.y     = nil
                            WUI.db.questtracker.x = nil
                            WUI.db.questtracker.y = nil
                            -- Rebuild on next open
                            if ns.QuestLog and ns.QuestLog.frame then
                                ns.QuestLog.frame:ClearAllPoints()
                                ns.QuestLog.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
                            end
                            if ns.QuestTracker and ns.QuestTracker.frame then
                                ns.QuestTracker.frame:ClearAllPoints()
                                ns.QuestTracker.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
                            end
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
