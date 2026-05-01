local addonName, ns = ...

local Brackets = {}
ns.Brackets = Brackets

-- Always-on ElvUI panels. Decorated once after PLAYER_ENTERING_WORLD.
local ELVUI_PANELS = {
    "LeftChatPanel",
    "RightChatPanel",
    "LeftChatDataPanel",
    "RightChatDataPanel",
    "ElvUI_TopPanel",
    "ElvUI_BottomPanel",
    "ElvUI_MinimapHolder",
}

-- Lazy Blizzard frames. Many of these exist at login but are hidden, so
-- decorating once is enough; a few (auction, achievement) are LOD and only
-- exist after the user opens them — we hook _G periodically.
local BLIZZARD_FRAMES = {
    "CharacterFrame",
    "PetPaperDollFrame",
    "ReputationFrame",
    "HonorFrame",
    "TokenFrame",
    "QuestLogFrame",
    "QuestFrame",
    "MerchantFrame",
    "BankFrame",
    "GuildBankFrame",
    "MailFrame",
    "OpenMailFrame",
    "SendMailFrame",
    "GossipFrame",
    "TaxiFrame",
    "TradeFrame",
    "LootFrame",
    "FriendsFrame",
    "WhoFrame",
    "WorldMapFrame",
    "SpellBookFrame",
    "PVPFrame",
    "PVPBattlegroundFrame",
    "TalentFrame",
    "TabardFrame",
    "TradeSkillFrame",
    "CraftFrame",
    "AuctionFrame",
    "InspectFrame",
    "MacroFrame",
    "KeyBindingFrame",
}

local function felColor()
    local p = ns.WUI and ns.WUI.palette and ns.WUI.palette.fel
    return p or { 0.310, 0.780, 0.471, 1 }
end

local function bracketArm(host, point, axis, length, thickness)
    local fel = felColor()
    local t = host:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(fel[1], fel[2], fel[3], fel[4])
    t:SetPoint(point, host, point, 0, 0)
    if axis == "h" then
        t:SetSize(length, thickness)
    else
        t:SetSize(thickness, length)
    end
    return t
end

function Brackets:Decorate(frame)
    if not frame or frame.__wicksUI_bracketed then return end
    -- Blizzard frames (CharacterFrame, SpellBookFrame, etc.) have invisible
    -- padding outside the visible art, so anchoring to the outer frame puts
    -- brackets in dead space. ElvUI's S:HandleFrame attaches a `.backdrop`
    -- child sized to the visible region — anchor there when it exists.
    local target = frame.backdrop or frame
    local cfg = (ns.WUI and ns.WUI.db and ns.WUI.db.brackets) or { size = 10, thickness = 2 }
    local size, thickness = cfg.size or 10, cfg.thickness or 2
    frame.__wicksUI_brackets = {}
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        table.insert(frame.__wicksUI_brackets, bracketArm(target, point, "h", size, thickness))
        table.insert(frame.__wicksUI_brackets, bracketArm(target, point, "v", size, thickness))
    end
    frame.__wicksUI_bracketed = true
end

function Brackets:Remove(frame)
    if not frame or not frame.__wicksUI_brackets then return end
    for _, t in ipairs(frame.__wicksUI_brackets) do t:Hide() end
    frame.__wicksUI_brackets = nil
    frame.__wicksUI_bracketed = nil
end

local function decorateOnFirstShow(frame)
    if not frame or frame.__wicksUI_showHooked then return end
    frame.__wicksUI_showHooked = true
    -- Decorate immediately if visible (e.g. /reload mid-merchant), else on
    -- the next OnShow. HookScript leaves Blizzard's existing handlers intact.
    if frame:IsShown() then
        Brackets:Decorate(frame)
    end
    frame:HookScript("OnShow", function(self)
        if ns.WUI and ns.WUI.db and ns.WUI.db.brackets.enabled then
            Brackets:Decorate(self)
        end
    end)
end

function Brackets:ApplyAll()
    for _, name in ipairs(ELVUI_PANELS) do
        local f = _G[name]
        if f then self:Decorate(f) end
    end
    for _, name in ipairs(BLIZZARD_FRAMES) do
        local f = _G[name]
        if f then decorateOnFirstShow(f) end
    end
end

function Brackets:RemoveAll()
    for _, name in ipairs(ELVUI_PANELS) do
        local f = _G[name]
        if f then self:Remove(f) end
    end
    for _, name in ipairs(BLIZZARD_FRAMES) do
        local f = _G[name]
        if f then self:Remove(f) end
    end
end
