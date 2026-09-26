local addonName, ns = ...
local WUI = ns.WUI

-- ─── palette shortcuts ────────────────────────────────────────────────────────
local P  -- assigned in QuestTracker:Init()

local function p(s) DEFAULT_CHAT_FRAME:AddMessage("|cff4FC778WQT:|r " .. tostring(s)) end

-- ─── constants ───────────────────────────────────────────────────────────────
local TRACKER_W  = 220
local TITLE_SIZE = 12
local OBJ_SIZE   = 11
local ZONE_SIZE  = 10
local HEADER_H   = 20
local ZONE_H     = 18
local TITLE_PAD  = 3   -- gap above each quest title
local OBJ_INDENT = 8   -- left indent for objective lines
local PADDING    = 8
local MAX_QUESTS = 10

local DB_DEFAULTS = {
    questtracker = {
        x = nil, y = nil,
        w = TRACKER_W, h = 300,
        maxQuests = MAX_QUESTS,
        enabled      = true,
        showZoneOnly = false,
        alpha        = 0.85,
    },
}

-- ─── helpers ─────────────────────────────────────────────────────────────────
local function rgba(c, a)
    return c[1], c[2], c[3], a or c[4] or 1
end

local function NewTex(parent, layer)
    return parent:CreateTexture(nil, layer or "BACKGROUND")
end

local function NewLabel(parent, size, layer)
    local f = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontNormal")
    f:SetFont("Fonts\\FRIZQT__.TTF", size or 11)
    f:SetWordWrap(false)
    return f
end

local function DifficultyColor(questLevel, playerLevel)
    local diff = questLevel - playerLevel
    if diff >= 5  then return 0.80, 0.10, 0.10 end
    if diff >= 3  then return 1.00, 0.50, 0.25 end
    if diff >= -2 then return 1.00, 1.00, 0.00 end
    if diff >= -9 then return 0.25, 0.75, 0.25 end
    return 0.60, 0.60, 0.60
end

-- ─── module ──────────────────────────────────────────────────────────────────
local QT = {}
ns.QuestTracker = QT

QT.frame   = nil
QT.content = nil

-- pools: each entry is a table { titleFS, objFS[] }
QT.questPool = {}
QT.zonePool  = {}

-- ─── data ────────────────────────────────────────────────────────────────────
local function GetWatchedQuests()
    local list = {}
    local n = GetNumQuestLogEntries()
    local currentZone = GetZoneText()
    local playerLevel = UnitLevel("player") or 70

    for i = 1, n do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if not title then break end
        if not isHeader and IsQuestWatched(i) then
            SelectQuestLogEntry(i)
            local objLines = {}
            local done, total = 0, 0
            local numObj = GetNumQuestLeaderBoards()
            for j = 1, numObj do
                local objText, _, finished = GetQuestLogLeaderBoard(j)
                total = total + 1
                if finished then done = done + 1 end
                objLines[#objLines + 1] = { text = objText or "", finished = finished }
            end

            -- Walk backwards to find zone header
            local zone = ""
            for h = i - 1, 1, -1 do
                local ht, _, _, hIsHdr = GetQuestLogTitle(h)
                if hIsHdr and ht then zone = ht; break end
            end

            -- Quest item (usable item for this quest, if any)
            local itemIcon, itemName = nil, nil
            local itemLink, itemTex = GetQuestLogSpecialItemInfo(i)
            if itemTex and itemLink then
                itemIcon = itemTex
                -- Prefer cached name from GetItemInfo; fall back to parsing the link
                local cachedName = GetItemInfo(tonumber(itemLink:match("item:(%d+)")) or 0)
                itemName = cachedName or itemLink:match("%[(.-)%]") or nil
            end

            list[#list + 1] = {
                idx        = i,
                itemIcon   = itemIcon,
                itemName   = itemName,
                title      = title,
                level      = level or 0,
                complete   = isComplete,
                done       = done,
                total      = total,
                zone       = zone,
                inZone     = (zone == currentZone),
                objectives = objLines,
                playerLevel = playerLevel,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.inZone ~= b.inZone then return a.inZone end
        if (a.complete ~= 0) ~= (b.complete ~= 0) then
            return (a.complete or 0) == 0
        end
        return a.zone < b.zone
    end)

    return list
end

-- ─── zone header pool ────────────────────────────────────────────────────────
local function GetOrCreateZoneHeader(parent, idx)
    if QT.zonePool[idx] then return QT.zonePool[idx] end

    local zh = CreateFrame("Frame", nil, parent)
    zh:SetHeight(ZONE_H)

    local lbl = NewLabel(zh, ZONE_SIZE, "OVERLAY")
    lbl:SetPoint("BOTTOMLEFT", zh, "BOTTOMLEFT", PADDING, 2)
    lbl:SetPoint("RIGHT",      zh, "RIGHT",     -PADDING, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetTextColor(rgba({ 0.67, 0.60, 0.45 }))
    zh._lbl = lbl

    local div = NewTex(zh, "BORDER")
    div:SetHeight(1)
    div:SetPoint("BOTTOMLEFT",  zh, "BOTTOMLEFT",  PADDING, 0)
    div:SetPoint("BOTTOMRIGHT", zh, "BOTTOMRIGHT", -PADDING, 0)
    div:SetColorTexture(rgba({ 0.22, 0.19, 0.34 }, 0.9))

    QT.zonePool[idx] = zh
    return zh
end

-- ─── quest block pool ────────────────────────────────────────────────────────
-- Each pool entry: { frame, titleFS, objFS[1..n], _questIdx }
-- We keep up to 20 objective FontStrings per block and hide unused ones.

local MAX_OBJ_PER_BLOCK = 12

local function GetOrCreateQuestBlock(parent, idx)
    if QT.questPool[idx] then return QT.questPool[idx] end

    local blk = CreateFrame("Button", nil, parent)
    blk:EnableMouse(true)
    blk:RegisterForClicks("AnyUp")

    local bg = NewTex(blk, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    blk._bg = bg

    -- Quest item button: plain Button (no secure template — quest items aren't
    -- used in combat, so RunMacroText is fine and lets us keep full script control).
    local ICON_SIZE = TITLE_SIZE + 3
    local itemBtn = CreateFrame("Button", nil, blk)
    itemBtn:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
    itemBtn:SetPoint("TOPLEFT", blk, "TOPLEFT", PADDING, -TITLE_PAD + 1)
    itemBtn:EnableMouse(true)
    itemBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    itemBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if self._itemName then RunMacroText("/use " .. self._itemName) end
        elseif button == "RightButton" then
            QT:ShowRowMenu(blk._questIdx)
        end
    end)
    -- Dark bg behind icon for the 1px cushion
    local iconBg = itemBtn:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0.05, 0.04, 0.08, 0.9)
    -- Icon texture inset 1px inside the button
    local iconTex = itemBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT",     itemBtn, "TOPLEFT",     1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", itemBtn, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    itemBtn._icon = iconTex
    -- Hover highlight
    local iconHl = itemBtn:CreateTexture(nil, "HIGHLIGHT")
    iconHl:SetAllPoints()
    iconHl:SetColorTexture(1, 1, 1, 0.2)
    itemBtn:Hide()
    blk._itemBtn = itemBtn

    local titleFS = NewLabel(blk, TITLE_SIZE, "OVERLAY")
    titleFS:SetPoint("TOPLEFT",  blk, "TOPLEFT",  PADDING, -TITLE_PAD)
    titleFS:SetPoint("TOPRIGHT", blk, "TOPRIGHT", -PADDING, -TITLE_PAD)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
    blk._title = titleFS

    local objFS = {}
    for j = 1, MAX_OBJ_PER_BLOCK do
        local fs = NewLabel(blk, OBJ_SIZE, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        objFS[j] = fs
    end
    blk._objFS = objFS

    blk:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if ns.QuestLog then
                ns.QuestLog:Show()
                ns.QuestLog:SelectRow(self._questIdx)
            end
        elseif button == "RightButton" then
            QT:ShowRowMenu(self._questIdx)
        end
    end)
    blk:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(rgba(P.shadow, 0.5))
    end)
    blk:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0, 0, 0, 0)
    end)

    QT.questPool[idx] = blk
    return blk
end

-- ─── context menu ─────────────────────────────────────────────────────────────
-- Mirrors WicksLedger's working pattern: TOOLTIP strata, OnLeave to dismiss,
-- no dismiss-catcher frame. OnMouseUp on the row (not OnClick) to open it.

local ctxMenu = nil

local function BuildContextMenu()
    ctxMenu = CreateFrame("Frame", nil, UIParent)
    ctxMenu:SetFrameStrata("TOOLTIP")
    ctxMenu:SetClampedToScreen(true)
    ctxMenu:EnableMouse(true)
    local bg = ctxMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.12, 0.98)
    local function mkEdge(a, b, isH)
        local t = ctxMenu:CreateTexture(nil, "BORDER")
        if isH then t:SetHeight(1) else t:SetWidth(1) end
        t:SetPoint(a, ctxMenu, a); t:SetPoint(b, ctxMenu, b)
        t:SetColorTexture(0.22, 0.19, 0.34, 1)
    end
    mkEdge("TOPLEFT","TOPRIGHT",true); mkEdge("BOTTOMLEFT","BOTTOMRIGHT",true)
    mkEdge("TOPLEFT","BOTTOMLEFT",false); mkEdge("TOPRIGHT","BOTTOMRIGHT",false)
    ctxMenu:Hide()
    ctxMenu:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then self:Hide() end
    end)
    ctxMenu._items = {}
end

function QT:ShowRowMenu(qLogIndex)
    if not qLogIndex then return end
    local ok, err = pcall(function()
    if not ctxMenu then BuildContextMenu() end

    for _, btn in ipairs(ctxMenu._items) do btn:Hide() end
    ctxMenu._items = {}

    local ITEM_H  = 22
    local menuW   = 160
    local yOff    = -4
    local inParty = UnitExists("party1")

    local function addItem(label, isRed, fn)
        local btn = CreateFrame("Button", nil, ctxMenu)
        btn:SetSize(menuW - 8, ITEM_H)
        btn:SetPoint("TOPLEFT", ctxMenu, "TOPLEFT", 4, yOff)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 11)
        lbl:SetAllPoints(); lbl:SetJustifyH("LEFT"); lbl:SetJustifyV("MIDDLE")
        lbl:SetPoint("LEFT", btn, "LEFT", 6, 0)
        if isRed then lbl:SetTextColor(1, 0.4, 0.4) else lbl:SetTextColor(0.831, 0.784, 0.631) end
        lbl:SetText(label)
        btn:SetScript("OnEnter", function() lbl:SetTextColor(0.310, 0.780, 0.471) end)
        btn:SetScript("OnLeave", function()
            if isRed then lbl:SetTextColor(1, 0.4, 0.4) else lbl:SetTextColor(0.831, 0.784, 0.631) end
            if not ctxMenu:IsMouseOver() then ctxMenu:Hide() end
        end)
        btn:SetScript("OnClick", function() ctxMenu:Hide(); fn() end)
        yOff = yOff - ITEM_H
        table.insert(ctxMenu._items, btn)
    end

    local watched = IsQuestWatched(qLogIndex)
    addItem(watched and "Untrack" or "Track", false, function()
        if IsQuestWatched(qLogIndex) then RemoveQuestWatch(qLogIndex) else AddQuestWatch(qLogIndex) end
        QT:Refresh()
        if ns.QuestLog then ns.QuestLog:Refresh() end
    end)

    if inParty then
        addItem("Share", false, function()
            SelectQuestLogEntry(qLogIndex)
            if C_QuestLog and C_QuestLog.PushQuest then
                local questID = select(8, GetQuestLogTitle(qLogIndex))
                if questID then C_QuestLog.PushQuest(questID) end
            else
                QuestLogPushQuest()
            end
        end)
    end

    addItem("Abandon", true, function()
        SelectQuestLogEntry(qLogIndex)
        SetAbandonQuest()
        local title = GetAbandonQuestName and GetAbandonQuestName() or select(1, GetQuestLogTitle(qLogIndex))
        StaticPopup_Show("ABANDON_QUEST", title)
    end)

    addItem("Open in Log", false, function()
        if ns.QuestLog then ns.QuestLog:Show(); ns.QuestLog:SelectRow(qLogIndex) end
    end)

    ctxMenu:SetSize(menuW, -yOff + 4)

    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    ctxMenu:ClearAllPoints()
    ctxMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    ctxMenu:Show()
    end) -- pcall
    if not ok then p("ShowRowMenu ERROR: " .. tostring(err)) end
end

-- ─── refresh ──────────────────────────────────────────────────────────────────
SLASH_WQTDBG1 = "/wqtdbg"
SlashCmdList["WQTDBG"] = function()
    p("frame=" .. tostring(QT.frame))
    p("content=" .. tostring(QT.content))
    if QT.frame then p("shown=" .. tostring(QT.frame:IsShown())) end
    local quests = GetWatchedQuests()
    p("watched=" .. #quests)
    for i, q in ipairs(quests) do
        p(i .. " [" .. q.zone .. "] " .. q.title .. " objs=" .. #q.objectives)
    end
    p("questPool size=" .. #QT.questPool)
    p("zonePool size=" .. #QT.zonePool)
    -- force a refresh and catch errors
    local ok, err = pcall(function() QT:Refresh() end)
    if not ok then p("Refresh error: " .. tostring(err)) end
end

function QT:Refresh()
    if not QT.frame or not QT.frame:IsShown() then return end
    local db     = WUI.db.questtracker
    local quests = GetWatchedQuests()

    if db.showZoneOnly then
        local filtered = {}
        for _, q in ipairs(quests) do
            if q.inZone then filtered[#filtered + 1] = q end
        end
        quests = filtered
    end
    local cap = math.min(db.maxQuests, #quests)

    -- hide all pooled blocks and zone headers
    for _, blk in ipairs(QT.questPool) do blk:Hide() end
    for _, zh  in ipairs(QT.zonePool)  do zh:Hide()  end

    local parent    = QT.content
    local curY      = -4                -- Y offset from content top (scroll child)
    local blkCount  = 0
    local zoneCount = 0
    local lastZone  = nil

    -- FontString line height estimates
    local titleLineH = TITLE_SIZE + 3
    local objLineH   = OBJ_SIZE   + 2

    for i = 1, cap do
        local q = quests[i]

        -- Zone header on zone change
        if q.zone ~= lastZone then
            zoneCount = zoneCount + 1
            local zh = GetOrCreateZoneHeader(parent, zoneCount)
            local zoneName = (q.zone ~= "") and q.zone or "Unknown"
            zh._lbl:SetText(zoneName:upper())
            zh:ClearAllPoints()
            zh:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, curY)
            zh:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, curY)
            zh:Show()
            curY    = curY - ZONE_H
            lastZone = q.zone
        end

        -- Quest block
        blkCount = blkCount + 1
        local blk = GetOrCreateQuestBlock(parent, blkCount)
        blk._questIdx = q.idx
        blk:ClearAllPoints()
        blk:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, curY)
        blk:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, curY)

        -- Quest item button
        local ICON_SIZE = TITLE_SIZE + 3
        if q.itemIcon and q.itemName then
            blk._itemBtn._icon:SetTexture(q.itemIcon)
            blk._itemBtn._itemName = q.itemName
            blk._itemBtn:Show()
            blk._title:ClearAllPoints()
            blk._title:SetPoint("TOPLEFT",  blk, "TOPLEFT",  PADDING + ICON_SIZE + 5, -TITLE_PAD)
            blk._title:SetPoint("TOPRIGHT", blk, "TOPRIGHT", -PADDING, -TITLE_PAD)
        else
            blk._itemBtn:Hide()
            blk._title:ClearAllPoints()
            blk._title:SetPoint("TOPLEFT",  blk, "TOPLEFT",  PADDING, -TITLE_PAD)
            blk._title:SetPoint("TOPRIGHT", blk, "TOPRIGHT", -PADDING, -TITLE_PAD)
        end

        -- Title colour
        local r, g, b
        if q.complete and q.complete ~= 0 then
            r, g, b = rgba(P.fel)
        else
            r, g, b = DifficultyColor(q.level, q.playerLevel)
        end
        blk._title:SetText(q.title)
        blk._title:SetTextColor(r, g, b, 1)

        -- Objectives
        local numObj = math.min(#q.objectives, MAX_OBJ_PER_BLOCK)
        local blkH = TITLE_PAD + titleLineH

        for j = 1, MAX_OBJ_PER_BLOCK do
            local fs = blk._objFS[j]
            if j <= numObj then
                local obj = q.objectives[j]
                -- anchor each obj line below the previous
                fs:ClearAllPoints()
                if j == 1 then
                    fs:SetPoint("TOPLEFT",  blk, "TOPLEFT",  PADDING + OBJ_INDENT, -(TITLE_PAD + titleLineH))
                    fs:SetPoint("TOPRIGHT", blk, "TOPRIGHT", -PADDING, -(TITLE_PAD + titleLineH))
                else
                    fs:SetPoint("TOPLEFT",  blk._objFS[j-1], "BOTTOMLEFT",  0, -1)
                    fs:SetPoint("TOPRIGHT", blk._objFS[j-1], "BOTTOMRIGHT", 0, -1)
                end
                local objTxt = "- " .. (obj.text or "")
                if obj.finished then
                    fs:SetText("|cff808080" .. objTxt .. "|r")
                else
                    fs:SetText("|cffC8BF9A" .. objTxt .. "|r")
                end
                fs:Show()
                blkH = blkH + objLineH + 1
            else
                fs:Hide()
            end
        end

        -- Complete message if no objectives listed
        if q.complete and q.complete ~= 0 and numObj == 0 then
            local fs = blk._objFS[1]
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT",  blk, "TOPLEFT",  PADDING + OBJ_INDENT, -(TITLE_PAD + titleLineH))
            fs:SetPoint("TOPRIGHT", blk, "TOPRIGHT", -PADDING, -(TITLE_PAD + titleLineH))
            fs:SetText("|cff4FC778- Complete!|r")
            fs:Show()
            blkH = blkH + objLineH + 1
        end

        blkH = blkH + 4  -- bottom padding
        blk:SetHeight(blkH)
        blk:Show()
        curY = curY - blkH
    end

    -- Empty state
    if cap == 0 then
        if not QT._emptyLabel then
            local el = NewLabel(parent, 11, "OVERLAY")
            el:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PADDING, -8)
            el:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING, -8)
            el:SetJustifyH("CENTER")
            el:SetTextColor(0.45, 0.42, 0.36)
            QT._emptyLabel = el
        end
        QT._emptyLabel:SetText("No watched quests.")
        QT._emptyLabel:Show()
        curY = curY - 20
    else
        if QT._emptyLabel then QT._emptyLabel:Hide() end
    end

    -- Size the content frame to its content; outer frame stays at user's chosen size
    local contentH = math.max(-curY + 4, 20)
    parent:SetHeight(contentH)
    -- Re-clamp scroll in case content shrank
    if QT.ClampScroll then QT.ClampScroll() end
end

-- ─── build ────────────────────────────────────────────────────────────────────
function QT:Build()
    if QT.frame then return end
    local db = WUI.db.questtracker

    local f = CreateFrame("Frame", "WicksUIQuestTrackerFrame", UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(db.w, db.h)
    f:SetClampedToScreen(true)
    if db.x ~= nil and db.y ~= nil then
        f:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = UIParent:GetCenter()
        local fx, fy = self:GetCenter()
        db.x = fx - cx
        db.y = fy - cy
    end)
    f:SetAlpha(db.alpha)
    QT.frame = f

    -- Transparent background
    local bg = NewTex(f, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(rgba(P.void, 0.60))

    -- 1px border
    local function mkEdge(a, b, isH)
        local t = NewTex(f, "BORDER")
        if isH then t:SetHeight(1) else t:SetWidth(1) end
        t:SetPoint(a, f, a, 0, 0)
        t:SetPoint(b, f, b, 0, 0)
        t:SetColorTexture(rgba(P.border, 0.6))
    end
    mkEdge("TOPLEFT",    "TOPRIGHT",    true)
    mkEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    mkEdge("TOPLEFT",    "BOTTOMLEFT",  false)
    mkEdge("TOPRIGHT",   "BOTTOMRIGHT", false)

    -- L-bracket corners on a top-level overlay child so they aren't occluded.
    -- EnableMouse(false) so the overlay doesn't eat clicks from buttons below.
    local bracketOverlay = CreateFrame("Frame", nil, f)
    bracketOverlay:SetAllPoints(f)
    bracketOverlay:SetFrameLevel(f:GetFrameLevel() + 10)
    bracketOverlay:EnableMouse(false)
    local function corner(hp, vp)
        local ht = NewTex(bracketOverlay, "OVERLAY"); ht:SetSize(10, 2)
        ht:SetPoint(hp..vp, f, hp..vp, 0, 0)
        ht:SetColorTexture(rgba(P.fel))
        local vt = NewTex(bracketOverlay, "OVERLAY"); vt:SetSize(2, 10)
        vt:SetPoint(hp..vp, f, hp..vp, 0, 0)
        vt:SetColorTexture(rgba(P.fel))
    end
    corner("TOP",    "LEFT")
    corner("TOP",    "RIGHT")
    corner("BOTTOM", "LEFT")
    corner("BOTTOM", "RIGHT")

    -- Header strip
    local headerBg = NewTex(f, "BACKGROUND")
    headerBg:SetHeight(HEADER_H)
    headerBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    headerBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    headerBg:SetColorTexture(rgba(P.shadow, 0.85))

    local headerLabel = NewLabel(f, 10, "OVERLAY")
    headerLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -4)
    headerLabel:SetText("|cffD4C8A1Wick's|r |cff4FC778Quests|r")

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    closeBtn:SetPoint("TOP",   f, "TOP",   0, -3)
    local closeLbl = NewLabel(closeBtn, 9, "OVERLAY")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetTextColor(rgba(P.text))
    closeLbl:SetText("x")
    closeBtn:SetScript("OnClick", function() QT:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeLbl:SetTextColor(rgba(P.fel)) end)
    closeBtn:SetScript("OnLeave", function() closeLbl:SetTextColor(rgba(P.text)) end)

    -- Scroll indicator on right edge (visual only)
    local sbBg = NewTex(f, "BACKGROUND")
    sbBg:SetWidth(4)
    sbBg:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    0, -HEADER_H)
    sbBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    sbBg:SetColorTexture(rgba(P.shadow, 0.8))

    local sbThumb = NewTex(f, "BORDER")
    sbThumb:SetWidth(4)
    sbThumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)
    sbThumb:SetHeight(20)
    sbThumb:SetColorTexture(rgba(P.border, 0.9))
    QT.sbThumb = sbThumb

    -- Clipper: clips rendering so content doesn't spill below the frame edge.
    -- EnableMouse(false) so it doesn't intercept clicks meant for quest blocks.
    -- Child Buttons with EnableMouse(true) still receive events directly in TBC.
    local clipper = CreateFrame("Frame", nil, f)
    clipper:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -HEADER_H)
    clipper:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  0)
    clipper:SetClipsChildren(true)
    clipper:EnableMouse(false)

    local content = CreateFrame("Frame", nil, clipper)
    content:SetPoint("TOPLEFT",  clipper, "TOPLEFT",  0, 0)
    content:SetPoint("TOPRIGHT", clipper, "TOPRIGHT", 0, 0)
    content:SetHeight(1)
    QT.content      = content
    QT.scrollOffset = 0

    local function ClampScroll()
        local frameH   = f:GetHeight() - HEADER_H
        local contentH = content:GetHeight() or 0
        local maxScroll = math.max(0, contentH - frameH)
        QT.scrollOffset = math.max(0, math.min(QT.scrollOffset, maxScroll))
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT",  clipper, "TOPLEFT",  0,  QT.scrollOffset)
        content:SetPoint("TOPRIGHT", clipper, "TOPRIGHT", 0,  QT.scrollOffset)
        -- Move thumb
        if maxScroll > 0 then
            local frac = QT.scrollOffset / maxScroll
            local trackH = math.max(1, frameH)
            local thumbY = -math.floor(frac * (trackH - 20))
            sbThumb:ClearAllPoints()
            sbThumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H + thumbY)
            sbThumb:Show()
        else
            sbThumb:Hide()
        end
    end
    QT.ClampScroll = ClampScroll

    -- Mouse wheel on the outer frame drives scrolling
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        QT.scrollOffset = QT.scrollOffset - delta * 30
        ClampScroll()
    end)

    -- Resize grip
    local grip = CreateFrame("Frame", nil, f)
    grip:SetSize(10, 10)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(160, 80)
    else f:SetMinResize(160, 80) end
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        db.w = f:GetWidth()
        db.h = f:GetHeight()
        -- Update content width to match new frame width
        if QT.content then
            QT.content:SetWidth(math.max(1, f:GetWidth() - 5))
        end
        if QT.ClampScroll then QT.ClampScroll() end
    end)

    f:Hide()
end

-- ─── public API ──────────────────────────────────────────────────────────────
function QT:Show()
    if not QT.frame then QT:Build() end
    QT.frame:Show()
    QT:Refresh()
end

function QT:Hide()
    if QT.frame then QT.frame:Hide() end
end

function QT:Toggle()
    if QT.frame and QT.frame:IsShown() then
        QT:Hide()
    else
        QT:Show()
    end
end

-- ─── init ────────────────────────────────────────────────────────────────────
function QT:Init()
    P = WUI.palette

    if WUI.db then
        if not WUI.db.questtracker then WUI.db.questtracker = {} end
        local db = WUI.db.questtracker
        for k, v in pairs(DB_DEFAULTS.questtracker) do
            if db[k] == nil then db[k] = v end
        end
        -- Clamp saved size to sane bounds in case a bad resize was persisted
        db.w = math.max(160, math.min(db.w or 220, 600))
        db.h = math.max(80,  math.min(db.h or 300, 800))
    end

    -- Auto-watch: fill empty slots with zone-matching incomplete quests.
    -- Never evicts manually tracked quests.
    local function AutoWatch()
        local maxSlots    = GetMaxQuestWatches and GetMaxQuestWatches() or 5
        local currentZone = GetZoneText()
        local n           = GetNumQuestLogEntries()

        local usedSlots = 0
        for i = 1, n do
            local _, _, _, isHeader = GetQuestLogTitle(i)
            if not isHeader and IsQuestWatched(i) then
                usedSlots = usedSlots + 1
            end
        end

        local freeSlots = maxSlots - usedSlots
        if freeSlots <= 0 then return end

        local candidates = {}
        local zoneHeader = nil
        for i = 1, n do
            local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
            if not title then break end
            if isHeader then
                zoneHeader = title
            elseif not IsQuestWatched(i) and not (isComplete and isComplete ~= 0) then
                SelectQuestLogEntry(i)
                local done, total = 0, 0
                local numObj = GetNumQuestLeaderBoards()
                for j = 1, numObj do
                    local _, _, finished = GetQuestLogLeaderBoard(j)
                    total = total + 1
                    if finished then done = done + 1 end
                end
                candidates[#candidates + 1] = {
                    idx      = i,
                    inZone   = (zoneHeader == currentZone),
                    fraction = total > 0 and (done / total) or 0,
                }
            end
        end

        table.sort(candidates, function(a, b)
            if a.inZone ~= b.inZone then return a.inZone end
            return a.fraction > b.fraction
        end)

        for i = 1, math.min(freeSlots, #candidates) do
            AddQuestWatch(candidates[i].idx)
        end
    end

    -- Suppress Blizzard's watch frame. Done here and re-enforced on
    -- PLAYER_ENTERING_WORLD because QuestWatchFrame re-registers events itself.
    local function SuppressBlizzardWatcher()
        if QuestWatchFrame then
            QuestWatchFrame:UnregisterAllEvents()
            QuestWatchFrame:SetScript("OnEvent", nil)
            QuestWatchFrame:Hide()
            QuestWatchFrame:SetParent(WorldFrame)
            -- Keep it hidden if something tries to show it
            QuestWatchFrame:HookScript("OnShow", function(self) self:Hide() end)
        end
    end

    -- Event listener
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    ev:RegisterEvent("QUEST_WATCH_UPDATE")
    ev:RegisterEvent("ZONE_CHANGED")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            SuppressBlizzardWatcher()
            AutoWatch()
            local db = WUI.db.questtracker
            if db.enabled then QT:Show() end
            return
        end
        if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
            AutoWatch()
        end
        if QT.frame and QT.frame:IsShown() then
            QT:Refresh()
        end
    end)

    -- Show tracker if enabled (may be before PLAYER_ENTERING_WORLD fires)
    local db = WUI.db.questtracker
    if db.enabled then
        QT:Show()
    end
end
