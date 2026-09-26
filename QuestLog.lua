local addonName, ns = ...
local WUI = ns.WUI

-- ─── palette shortcuts ────────────────────────────────────────────────────────
local P  -- assigned in QuestLog:Init() once WUI.palette is ready

-- ─── constants ───────────────────────────────────────────────────────────────
local TITLE_H     = 28
local FILTER_H    = 24
local ROW_H       = 26
local DETAIL_W    = 240
local MIN_W, MIN_H = 520, 340
local DEFAULT_W, DEFAULT_H = 680, 480

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
    return f
end

local function ApplyBorder(f)
    local bdr = { top = NewTex(f, "BORDER"), bot = NewTex(f, "BORDER"),
                  lft = NewTex(f, "BORDER"), rgt = NewTex(f, "BORDER") }
    bdr.top:SetHeight(1); bdr.top:SetPoint("TOPLEFT"); bdr.top:SetPoint("TOPRIGHT")
    bdr.bot:SetHeight(1); bdr.bot:SetPoint("BOTTOMLEFT"); bdr.bot:SetPoint("BOTTOMRIGHT")
    bdr.lft:SetWidth(1);  bdr.lft:SetPoint("TOPLEFT"); bdr.lft:SetPoint("BOTTOMLEFT")
    bdr.rgt:SetWidth(1);  bdr.rgt:SetPoint("TOPRIGHT"); bdr.rgt:SetPoint("BOTTOMRIGHT")
    local function Repaint(c)
        for _, t in pairs(bdr) do t:SetColorTexture(rgba(c)) end
    end
    Repaint(P.border)
    f._bordertextures = bdr
    f._repaintBorder  = Repaint
    return bdr
end

local function AddCornerAccents(f, sz, th)
    sz = sz or 10; th = th or 2
    -- Textures on the outer frame get occluded by child frames at any layer.
    -- Use a dedicated overlay child frame that renders above all siblings.
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f:GetFrameLevel() + 10)
    overlay:EnableMouse(false)
    local function corner(hp, vp)
        local ht = NewTex(overlay, "OVERLAY"); ht:SetSize(sz, th)
        ht:SetPoint(hp..vp, f, hp..vp, 0, 0)
        ht:SetColorTexture(rgba(P.fel))
        local vt = NewTex(overlay, "OVERLAY"); vt:SetSize(th, sz)
        vt:SetPoint(hp..vp, f, hp..vp, 0, 0)
        vt:SetColorTexture(rgba(P.fel))
        return ht, vt
    end
    corner("TOP",    "LEFT")
    corner("TOP",    "RIGHT")
    corner("BOTTOM", "LEFT")
    local ht, vt = corner("BOTTOM", "RIGHT")
    f._brAccents = { ht, vt }
end

local function MakeButton(parent, label, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w or 72, h or 18)
    local bg = NewTex(btn, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(rgba(P.shadow))
    ApplyBorder(btn)
    local lbl = NewLabel(btn, 10, "OVERLAY")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetText(label)
    lbl:SetTextColor(rgba(P.text))
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(rgba(P.border))
        lbl:SetTextColor(rgba(P.fel))
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(rgba(P.shadow))
        lbl:SetTextColor(rgba(P.text))
    end)
    return btn, lbl
end

-- ─── module ──────────────────────────────────────────────────────────────────
local QL = {}
ns.QuestLog = QL

QL.frame       = nil
QL.listFrame   = nil   -- left column scroll child
QL.detailFrame = nil   -- right column
QL.rows        = {}    -- reusable row widgets
QL.selectedIdx = nil   -- quest log index currently shown in detail
QL.filter      = "all" -- "all" | "zone" | "level" | "tracked"
QL.sortMode    = "default" -- future: "name" | "level"

-- saved-var keys initialised in WUI.Init (merged into WicksUIDB)
local DB_DEFAULTS = {
    questlog = {
        x = nil, y = nil, w = DEFAULT_W, h = DEFAULT_H,
        detailW = DETAIL_W,
        filter = "all",
    },
}

-- ─── data helpers ─────────────────────────────────────────────────────────────
local function GetQuestZone(qLogIndex)
    -- No native TBC API for quest zone from log index; parse from tag text.
    -- GetQuestLogTitle returns: title, level, questTag, isHeader, isCollapsed,
    --   isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isHidden
    local _, _, tag = GetQuestLogTitle(qLogIndex)
    return tag or ""
end

-- Standard WoW difficulty color by level delta.
local function DifficultyColor(questLevel, playerLevel)
    local diff = questLevel - playerLevel
    if questLevel <= 0 then
        return 0.50, 0.50, 0.50  -- trivial (grey)
    elseif diff >= 5 then
        return 1.00, 0.12, 0.12  -- elite/skull (red)
    elseif diff >= 3 then
        return 1.00, 0.50, 0.25  -- hard (orange)
    elseif diff >= -2 then
        return 1.00, 1.00, 0.00  -- normal (yellow)
    elseif diff >= -10 then
        return 0.25, 0.75, 0.25  -- easy (green)
    else
        return 0.50, 0.50, 0.50  -- trivial (grey)
    end
end

local function BuildQuestList()
    local entries = {}
    local playerLevel = UnitLevel("player")
    local currentZone = GetZoneText()
    local n = GetNumQuestLogEntries()
    local currentZoneHeader = nil

    for i = 1, n do
        local title, level, tag, isHeader, isCollapsed, isComplete =
            GetQuestLogTitle(i)
        if not title then break end

        if isHeader then
            currentZoneHeader = title
        else
            local pass = false
            local f = QL.filter
            if f == "all" then
                pass = true
            elseif f == "zone" then
                pass = (currentZoneHeader == currentZone)
            elseif f == "level" then
                pass = (level and math.abs(level - playerLevel) <= 5)
            elseif f == "tracked" then
                pass = IsQuestWatched(i)
            end
            if pass then
                local dr, dg, db2 = DifficultyColor(level or 0, playerLevel)
                -- tag is the 3rd return: "Daily", "Heroic", "Dungeon", etc.
                local isDaily   = (tag == "Daily")
                local isWeekly  = (tag == "Weekly")
                local isHeroic  = (tag == "Heroic")
                entries[#entries + 1] = {
                    idx      = i,
                    title    = title or "",
                    level    = level or 0,
                    zone     = currentZoneHeader or "",
                    complete = isComplete,
                    watched  = IsQuestWatched(i),
                    isDaily  = isDaily,
                    isWeekly = isWeekly,
                    isHeroic = isHeroic,
                    dr = dr, dg = dg, db = db2,
                }
            end
        end
    end

    -- Sort: current zone first, then alphabetical by zone, completed last within zone
    table.sort(entries, function(a, b)
        local aZ = (a.zone == currentZone) and 0 or 1
        local bZ = (b.zone == currentZone) and 0 or 1
        if aZ ~= bZ then return aZ < bZ end
        if a.zone ~= b.zone then return a.zone < b.zone end
        local aC = (a.complete and a.complete ~= 0) and 1 or 0
        local bC = (b.complete and b.complete ~= 0) and 1 or 0
        if aC ~= bC then return aC < bC end
        return a.level < b.level
    end)

    return entries
end

-- ─── reward helpers ───────────────────────────────────────────────────────────
local ICON_SZ  = 36
local ICON_GAP = 6

-- Pre-computed LEFT offsets to center n icons (1–5) within DETAIL_W.
-- Offset is from the detailChild CENTER to the LEFT edge of the first icon.
-- Formula: -(n * ICON_SZ + (n-1) * ICON_GAP) / 2
local ICON_ROW_OFFSET = {}
for n = 1, 5 do
    ICON_ROW_OFFSET[n] = -math.floor((n * ICON_SZ + (n - 1) * ICON_GAP) / 2)
end

local function FormatMoney(copper)
    if not copper or copper <= 0 then return nil end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = "|cffFFD700" .. g .. "g|r" end
    if s > 0 then parts[#parts+1] = "|cffC0C0C0" .. s .. "s|r" end
    if c > 0 then parts[#parts+1] = "|cffB87333" .. c .. "c|r" end
    return table.concat(parts, " ")
end

local function MakeRewardIcon(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SZ, ICON_SZ)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.04, 0.08, 0.9)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    -- quality border (1px colored edge)
    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     0, 0)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(rgba(P.border))
    btn._border = border
    btn:SetScript("OnEnter", function(self)
        if not self._tooltipType then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- SetQuestLogItem / SetQuestLogChoiceItem are the TBC-native tooltip APIs
        -- for quest rewards — no item cache needed.
        if self._tooltipType == "choice" then
            GameTooltip:SetQuestLogItem("choice", self._rewardIdx)
        else
            GameTooltip:SetQuestLogItem("reward", self._rewardIdx)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- Quality border colors (matches WoW item quality)
local QUALITY_COLORS = {
    [0] = {0.62, 0.62, 0.62},  -- poor
    [1] = {1.00, 1.00, 1.00},  -- common
    [2] = {0.12, 1.00, 0.00},  -- uncommon
    [3] = {0.00, 0.44, 0.87},  -- rare
    [4] = {0.64, 0.21, 0.93},  -- epic
    [5] = {1.00, 0.50, 0.00},  -- legendary
}

-- ─── detail panel ─────────────────────────────────────────────────────────────
local function PopulateDetail(qLogIndex)
    if not QL.detailFrame then return end
    local df = QL.detailFrame
    QL.selectedIdx = qLogIndex

    local function HideRewards()
        df.rewardDiv:Hide()
        df.rewardHdr:Hide()
        df.rewardMoneyLbl:Hide()
        df.rewardXPLbl:Hide()
        for _, ic in ipairs(df.rewardIcons) do ic:Hide() end
        for _, ic in ipairs(df.choiceIcons) do ic:Hide() end
    end

    if not qLogIndex then
        df.titleLabel:SetText("")
        df.bodyLabel:SetText("")
        df.objLabel:SetText("")
        df.abandonBtn:Hide()
        df.shareBtn:Hide()
        df.trackBtn:Hide()
        HideRewards()
        return
    end

    SelectQuestLogEntry(qLogIndex)

    local title, level, tag, isHeader, _, isComplete = GetQuestLogTitle(qLogIndex)
    local desc, objectives = GetQuestLogQuestText(qLogIndex)

    df.titleLabel:SetText(("|cff4FC778[%d]|r %s"):format(level or 0, title or ""))

    -- Build objectives string (SelectQuestLogEntry already called above)
    local objLines = {}
    local numObj = GetNumQuestLeaderBoards()
    for i = 1, numObj do
        local objText, objType, finished = GetQuestLogLeaderBoard(i)
        local check = finished and "|cff4FC778[x]|r" or "|cffD4C8A1[ ]|r"
        objLines[#objLines + 1] = check .. " " .. (objText or "")
    end
    if isComplete and isComplete > 0 then
        objLines[#objLines + 1] = "|cff4FC778Quest complete!|r"
    end

    df.bodyLabel:SetText(desc or "")
    df.objLabel:SetText(table.concat(objLines, "\n"))

    -- ── rewards ──────────────────────────────────────────────────────────────
    -- SelectQuestLogEntry already called above
    local numChoices = GetNumQuestLogChoices() or 0
    local numRewards = GetNumQuestLogRewards()  or 0
    local money      = GetQuestLogRewardMoney() or 0
    local xp         = GetQuestLogRewardXP()    or 0
    local hasRewards = (numChoices > 0 or numRewards > 0 or money > 0 or xp > 0)

    HideRewards()

    if hasRewards then
        local anchorAbove = df.objLabel  -- rewards sit below objectives

        -- divider
        df.rewardDiv:ClearAllPoints()
        df.rewardDiv:SetPoint("TOPLEFT",  anchorAbove, "BOTTOMLEFT",  0, -14)
        df.rewardDiv:SetPoint("TOPRIGHT", anchorAbove, "BOTTOMRIGHT", 0, -14)
        df.rewardDiv:Show()

        -- header label
        local hdrText = ""
        if numChoices > 0 and numRewards > 0 then
            hdrText = "Choose One:"
        elseif numChoices > 0 then
            hdrText = "Choose One:"
        else
            hdrText = "You Will Receive:"
        end
        df.rewardHdr:ClearAllPoints()
        df.rewardHdr:SetPoint("TOP",   df.rewardDiv,   "BOTTOM", 0, -8)
        df.rewardHdr:SetPoint("LEFT",  df.detailChild, "LEFT",   0, 0)
        df.rewardHdr:SetPoint("RIGHT", df.detailChild, "RIGHT",  0, 0)
        df.rewardHdr:SetJustifyH("CENTER")
        df.rewardHdr:SetText(hdrText)
        df.rewardHdr:Show()

        -- Helper: populate and center a row of icons below anchorFrame.
        -- Returns the last icon placed (for anchoring the next row below it).
        local function PlaceIconRow(count, anchorFrame, getFn, poolTable, tooltipType)
            if count == 0 then return nil end
            local startX = ICON_ROW_OFFSET[math.min(count, 5)]
            for i = 1, count do
                local name, tex, itemCount, quality = getFn(i)
                if not poolTable[i] then
                    poolTable[i] = MakeRewardIcon(df.detailChild)
                end
                local ic = poolTable[i]
                ic._icon:SetTexture(tex)
                ic._tooltipType = tooltipType
                ic._rewardIdx   = i
                local qc = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
                ic._border:SetColorTexture(qc[1], qc[2], qc[3], 1)
                if not ic._countLbl then
                    ic._countLbl = ic:CreateFontString(nil, "OVERLAY")
                    ic._countLbl:SetFont("Fonts\\FRIZQT__.TTF", 8)
                    ic._countLbl:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", -1, 1)
                    ic._countLbl:SetTextColor(1, 1, 1)
                end
                ic._countLbl:SetText(itemCount and itemCount > 1 and tostring(itemCount) or "")
                ic:ClearAllPoints()
                if i == 1 then
                    ic:SetPoint("TOP",  anchorFrame, "BOTTOM", 0, -6)
                    ic:SetPoint("LEFT", anchorFrame, "CENTER", startX, 0)
                else
                    ic:SetPoint("LEFT", poolTable[i-1], "RIGHT", ICON_GAP, 0)
                    ic:SetPoint("TOP",  poolTable[i-1], "TOP",   0, 0)
                end
                ic:Show()
            end
            return poolTable[count]  -- last icon
        end

        -- Choice icons row
        local lastChoiceIcon = PlaceIconRow(numChoices, df.rewardHdr,
            GetQuestLogChoiceInfo, df.choiceIcons, "choice")

        -- "Also:" separator label between choice and reward rows
        local rewardAnchor = df.rewardHdr
        if numChoices > 0 then rewardAnchor = lastChoiceIcon end

        if numChoices > 0 and numRewards > 0 then
            if not df._alsoLbl then
                df._alsoLbl = NewLabel(df.detailChild, 10, "OVERLAY")
                df._alsoLbl:SetJustifyH("CENTER")
                df._alsoLbl:SetTextColor(rgba(P.fel))
            end
            df._alsoLbl:ClearAllPoints()
            df._alsoLbl:SetPoint("TOP",   rewardAnchor, "BOTTOM", 0, -10)
            df._alsoLbl:SetPoint("LEFT",  df.detailChild, "LEFT",  0, 0)
            df._alsoLbl:SetPoint("RIGHT", df.detailChild, "RIGHT", 0, 0)
            df._alsoLbl:SetText("You Will Also Receive:")
            df._alsoLbl:Show()
            rewardAnchor = df._alsoLbl
        elseif df._alsoLbl then
            df._alsoLbl:Hide()
        end

        -- Reward icons row
        local lastRewardIcon = PlaceIconRow(numRewards, rewardAnchor,
            GetQuestLogRewardInfo, df.rewardIcons, "reward")

        -- find the bottom of the last icon row for money/xp anchoring
        local lastIconInLastRow = lastRewardIcon or lastChoiceIcon
        if not lastIconInLastRow then lastIconInLastRow = df.rewardHdr end

        -- Money
        local moneyStr = FormatMoney(money)
        if moneyStr then
            df.rewardMoneyLbl:ClearAllPoints()
            df.rewardMoneyLbl:SetPoint("TOP",   lastIconInLastRow,  "BOTTOM", 0, -10)
            df.rewardMoneyLbl:SetPoint("LEFT",  df.detailChild, "LEFT",  0, 0)
            df.rewardMoneyLbl:SetPoint("RIGHT", df.detailChild, "RIGHT", 0, 0)
            df.rewardMoneyLbl:SetJustifyH("CENTER")
            df.rewardMoneyLbl:SetText(moneyStr)
            df.rewardMoneyLbl:Show()
            lastIconInLastRow = df.rewardMoneyLbl
        end

        -- XP
        if xp > 0 then
            df.rewardXPLbl:ClearAllPoints()
            df.rewardXPLbl:SetPoint("TOP",   lastIconInLastRow,  "BOTTOM", 0, -4)
            df.rewardXPLbl:SetPoint("LEFT",  df.detailChild, "LEFT",  0, 0)
            df.rewardXPLbl:SetPoint("RIGHT", df.detailChild, "RIGHT", 0, 0)
            df.rewardXPLbl:SetJustifyH("CENTER")
            df.rewardXPLbl:SetText(xp .. " XP")
            df.rewardXPLbl:Show()
        end
    end

    -- Track button label
    local isWatched = IsQuestWatched(qLogIndex)
    df.trackBtn._lbl:SetText(isWatched and "Untrack" or "Track")
    df.trackBtn:Show()

    -- Share: only if in party
    if UnitExists("party1") then
        df.shareBtn:Show()
    else
        df.shareBtn:Hide()
    end

    df.abandonBtn:Show()
end

-- ─── list rows ────────────────────────────────────────────────────────────────
local function GetOrCreateRow(parent, idx)
    if QL.rows[idx] then return QL.rows[idx] end

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    local bg = NewTex(row, "BACKGROUND")
    bg:SetAllPoints()
    row._bg = bg

    local title = NewLabel(row, 13, "OVERLAY")
    title:SetPoint("LEFT", row, "LEFT", 14, 0)
    title:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row._title = title

    local watchDot = NewTex(row, "OVERLAY")
    watchDot:SetSize(6, 6)
    watchDot:SetPoint("LEFT", row, "LEFT", 4, 0)
    watchDot:SetColorTexture(rgba(P.fel))
    row._watchDot = watchDot

    row:SetScript("OnClick", function(self)
        QL:SelectRow(self._questIdx)
    end)
    row:SetScript("OnEnter", function(self)
        if self._questIdx ~= QL.selectedIdx then
            self._bg:SetColorTexture(rgba(P.shadow))
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self._questIdx ~= QL.selectedIdx then
            self._bg:SetColorTexture(0, 0, 0, 0)
        end
    end)

    QL.rows[idx] = row
    return row
end

function QL:SelectRow(qLogIndex)
    -- Un-highlight old
    for _, row in ipairs(QL.rows) do
        if row._questIdx == QL.selectedIdx then
            row._bg:SetColorTexture(0, 0, 0, 0)
        end
    end
    QL.selectedIdx = qLogIndex
    -- Highlight new
    for _, row in ipairs(QL.rows) do
        if row._questIdx == qLogIndex then
            row._bg:SetColorTexture(rgba(P.border))
        end
    end
    PopulateDetail(qLogIndex)
end

local ZONE_H = 20  -- zone header row height

-- Pool of zone header label frames (reused each refresh)
local zoneHeaders = {}
local function GetOrCreateZoneHeader(parent, idx)
    if zoneHeaders[idx] then return zoneHeaders[idx] end
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(ZONE_H)
    local hbg = NewTex(h, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(rgba(P.shadow, 0.9))
    local htex = NewTex(h, "BORDER")
    htex:SetHeight(1)
    htex:SetPoint("BOTTOMLEFT",  h, "BOTTOMLEFT",  0, 0)
    htex:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    htex:SetColorTexture(rgba(P.border))
    local lbl = NewLabel(h, 12, "OVERLAY")
    lbl:SetPoint("LEFT", h, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", h, "RIGHT", -4, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(rgba(P.fel))
    h._lbl = lbl
    zoneHeaders[idx] = h
    return h
end

-- ─── list refresh ─────────────────────────────────────────────────────────────
function QL:Refresh()
    if not QL.frame or not QL.frame:IsShown() then return end
    if not QL.listChild then return end
    local entries = BuildQuestList()
    local parent  = QL.listChild

    -- hide all reusable widgets
    for _, row in ipairs(QL.rows) do row:Hide() end
    for _, h in ipairs(zoneHeaders) do h:Hide() end

    local lastWidget  = nil   -- last placed frame (header or row)
    local rowIdx      = 0     -- index into QL.rows pool
    local headerIdx   = 0     -- index into zoneHeaders pool
    local totalH      = 0
    local currentZone = GetZoneText()
    local lastZone    = nil

    for _, e in ipairs(entries) do
        -- Insert zone header when zone changes
        if e.zone ~= lastZone then
            lastZone = e.zone
            headerIdx = headerIdx + 1
            local h = GetOrCreateZoneHeader(parent, headerIdx)
            h:SetPoint("LEFT",  parent, "LEFT",  0, 0)
            h:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
            if lastWidget then
                h:SetPoint("TOP", lastWidget, "BOTTOM", 0, 0)
            else
                h:SetPoint("TOP", parent, "TOP", 0, 0)
            end
            local isCurrentZone = (e.zone == currentZone)
            local zoneName = (e.zone == "") and "Unknown Zone" or e.zone
            if isCurrentZone then
                h._lbl:SetText("|cff4FC778" .. zoneName .. "|r  (current)")
                h._lbl:SetTextColor(rgba(P.fel))
            else
                h._lbl:SetText(zoneName)
                h._lbl:SetTextColor(0.55, 0.52, 0.42)
            end
            h:Show()
            lastWidget = h
            totalH = totalH + ZONE_H
        end

        rowIdx = rowIdx + 1
        local row = GetOrCreateRow(parent, rowIdx)
        row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
        row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        if lastWidget then
            row:SetPoint("TOP", lastWidget, "BOTTOM", 0, 0)
        else
            row:SetPoint("TOP", parent, "TOP", 0, 0)
        end
        row._questIdx = e.idx

        -- Build suffix tags: [D] daily (blue), [W] weekly (blue), [H] heroic (cyan)
        local tags = ""
        if e.isHeroic then tags = tags .. " |cff00ccff[H]|r"   end
        if e.isDaily  then tags = tags .. " |cff6699ff[D]|r"   end
        if e.isWeekly then tags = tags .. " |cff6699ff[W]|r"   end

        -- Difficulty color, dimmed if complete
        if e.complete and e.complete ~= 0 then
            row._title:SetTextColor(0.45, 0.45, 0.45)
            row._title:SetText(("[%d] %s%s"):format(e.level, e.title, tags))
        else
            row._title:SetTextColor(e.dr, e.dg, e.db)
            row._title:SetText(("[%d] %s%s"):format(e.level, e.title, tags))
        end

        row._watchDot:SetShown(e.watched)
        if e.idx == QL.selectedIdx then
            row._bg:SetColorTexture(rgba(P.border))
        else
            row._bg:SetColorTexture(0, 0, 0, 0)
        end

        row:Show()
        lastWidget = row
        totalH = totalH + ROW_H
    end

    parent:SetHeight(math.max(totalH, 1))

    if QL.countLabel then
        QL.countLabel:SetText(("#%d quests"):format(#entries))
    end

    if QL.selectedIdx == nil and entries[1] then
        QL:SelectRow(entries[1].idx)
    end
end

-- ─── build frame ─────────────────────────────────────────────────────────────
function QL:Build()
    if QL.frame then return end
    local ok, err = pcall(function() QL:_Build() end)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040WQL Build error:|r " .. tostring(err))
    end
end
function QL:_Build()
    if QL.frame then return end

    local db = WUI.db.questlog

    -- ── outer frame ──────────────────────────────────────────────────────────
    local f = CreateFrame("Frame", "WicksUIQuestLogFrame", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(db.w, db.h)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 40)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H)
    else f:SetMinResize(MIN_W, MIN_H) end
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
    f:SetScript("OnSizeChanged", function(self)
        db.w, db.h = self:GetSize()
    end)
    f:SetScript("OnShow", function() QL:Refresh() end)
    QL.frame = f

    -- Background
    local bg = NewTex(f, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(rgba(P.void, 0.97))

    ApplyBorder(f)
    AddCornerAccents(f)

    -- ── title bar ────────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(TITLE_H)
    local titleBg = NewTex(titleBar, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(rgba(P.shadow))

    local titleLabel = NewLabel(titleBar, 13, "OVERLAY")
    titleLabel:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    titleLabel:SetText("|cffD4C8A1Wick's|r |cff4FC778Quest Log|r")

    QL.countLabel = NewLabel(titleBar, 9, "OVERLAY")
    QL.countLabel:SetPoint("RIGHT", titleBar, "RIGHT", -36, 0)
    QL.countLabel:SetTextColor(0.5, 0.5, 0.5)

    -- Close button
    local closeBtn, _ = MakeButton(titleBar, "x", 20, 18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function() QL:Hide() end)

    -- ── filter bar ───────────────────────────────────────────────────────────
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -TITLE_H)
    filterBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TITLE_H)
    filterBar:SetHeight(FILTER_H)
    local filterBg = NewTex(filterBar, "BACKGROUND")
    filterBg:SetAllPoints()
    filterBg:SetColorTexture(rgba(P.shadow, 0.7))

    local divH = NewTex(f, "BORDER")
    divH:SetHeight(1)
    divH:SetPoint("TOPLEFT",  filterBar, "BOTTOMLEFT",  0, 0)
    divH:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, 0)
    divH:SetColorTexture(rgba(P.border))

    local filters = { {"All","all"}, {"Zone","zone"}, {"±5 Level","level"}, {"Tracked","tracked"} }
    local filterBtns = {}
    local prevBtn = nil
    -- Buttons are initially anchored left; recentered over list pane after divV is built.
    for _, def in ipairs(filters) do
        local fb, fl = MakeButton(filterBar, def[1], 68, FILTER_H - 2)
        fb._filterKey = def[2]
        fl:SetFont("Fonts\\FRIZQT__.TTF", 9)
        if prevBtn then
            fb:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
        else
            fb:SetPoint("LEFT", filterBar, "LEFT", 4, 0)
        end
        fb:SetPoint("TOP", filterBar, "TOP", 0, -1)
        fb._lbl = fl
        fb:SetScript("OnClick", function(self)
            QL.filter = self._filterKey
            db.filter = QL.filter
            for _, b in ipairs(filterBtns) do
                local active = (b._filterKey == QL.filter)
                if active then b._lbl:SetTextColor(rgba(P.fel)) else b._lbl:SetTextColor(rgba(P.text)) end
            end
            QL:Refresh()
        end)
        filterBtns[#filterBtns + 1] = fb
        prevBtn = fb
    end
    -- set initial active highlight
    for _, b in ipairs(filterBtns) do
        local active = (b._filterKey == QL.filter)
        if active then b._lbl:SetTextColor(rgba(P.fel)) else b._lbl:SetTextColor(rgba(P.text)) end
    end
    QL.filterBtns = filterBtns

    local contentTop = TITLE_H + FILTER_H + 1

    -- ── vertical divider (list / detail split) ───────────────────────────────
    local divV = CreateFrame("Frame", nil, f)
    divV:SetWidth(5)
    divV:SetPoint("TOP",    f, "TOP",    0, -contentTop)
    divV:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    divV:SetPoint("RIGHT",  f, "RIGHT",  -db.detailW, 0)
    divV:EnableMouse(true)
    local dvTex = NewTex(divV, "BACKGROUND")
    dvTex:SetAllPoints()
    dvTex:SetColorTexture(rgba(P.border))
    divV:SetScript("OnEnter", function() dvTex:SetColorTexture(rgba(P.fel, 0.6)) end)
    divV:SetScript("OnLeave", function() dvTex:SetColorTexture(rgba(P.border)) end)
    QL.divV = divV

    -- Center filter tabs over the list pane. Computed in OnSizeChanged so it works
    -- at any frame width (including after resize).
    filterBar:SetScript("OnSizeChanged", function(self)
        local listW = divV:GetLeft() and self:GetLeft() and (divV:GetLeft() - self:GetLeft()) or 0
        if listW < 10 then return end
        local GROUP_W = #filterBtns * 68 + (#filterBtns - 1) * 2
        local startX = math.floor((listW - GROUP_W) / 2)
        filterBtns[1]:ClearAllPoints()
        filterBtns[1]:SetPoint("TOPLEFT", filterBar, "TOPLEFT", startX, -1)
        for i = 2, #filterBtns do
            filterBtns[i]:ClearAllPoints()
            filterBtns[i]:SetPoint("LEFT", filterBtns[i-1], "RIGHT", 2, 0)
            filterBtns[i]:SetPoint("TOP",  filterBtns[i-1], "TOP",   0, 0)
        end
    end)

    -- ── quest list (left side) ────────────────────────────────────────────────
    local listScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -contentTop)
    listScroll:SetPoint("BOTTOMRIGHT", divV, "BOTTOMLEFT", -16, 0)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(db.w - DETAIL_W - 36)
    listChild:SetHeight(1)
    listScroll:SetScrollChild(listChild)
    QL.listChild = listChild
    QL.listScroll = listScroll

    -- Skin the scrollbar: hide up/down buttons, recolor track + thumb
    local sb = listScroll.ScrollBar or _G[(listScroll:GetName() or "") .. "ScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        if sb.scrollUp         then sb.scrollUp:Hide()         end
        if sb.scrollDown       then sb.scrollDown:Hide()       end
        -- Recolor the thumb
        local thumb = sb.ThumbTexture or sb.thumbTexture
        if thumb then
            thumb:SetColorTexture(rgba(P.border))
            thumb:SetWidth(6)
        end
        sb:SetWidth(6)
        -- Hide the default track texture
        if sb.Background then sb.Background:SetAlpha(0) end
        if sb.backdrop    then sb.backdrop:Hide()        end
    end

    local listRefreshed = false
    listScroll:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w and w > 10 then
            listChild:SetWidth(w)
            -- First time we get a real width, populate the rows.
            if not listRefreshed then
                listRefreshed = true
                QL:Refresh()
            end
        end
    end)

    -- ── detail panel (right side) ─────────────────────────────────────────────
    local df = CreateFrame("Frame", nil, f)
    df:SetPoint("TOPLEFT",     divV, "TOPRIGHT",     0, 0)
    df:SetPoint("BOTTOMRIGHT", f,    "BOTTOMRIGHT",  0, 0)
    df:SetPoint("TOP",         f,    "TOP",           0, -contentTop)

    local dfBg = NewTex(df, "BACKGROUND")
    dfBg:SetAllPoints()
    dfBg:SetColorTexture(rgba(P.shadow, 0.5))

    -- scroll for detail text
    local detailScroll = CreateFrame("ScrollFrame", nil, df, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",     df, "TOPLEFT",     4, -4)
    detailScroll:SetPoint("BOTTOMRIGHT", df, "BOTTOMRIGHT", -8, 28)

    local detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetWidth(detailScroll:GetWidth() or DETAIL_W)
    detailChild:SetHeight(1)
    detailScroll:SetScrollChild(detailChild)
    df.detailChild = detailChild
    detailScroll:SetScript("OnSizeChanged", function(self)
        detailChild:SetWidth(self:GetWidth())
    end)

    -- Skin detail scrollbar
    local dsb = detailScroll.ScrollBar or _G[(detailScroll:GetName() or "") .. "ScrollBar"]
    if dsb then
        if dsb.ScrollUpButton   then dsb.ScrollUpButton:Hide()   end
        if dsb.ScrollDownButton then dsb.ScrollDownButton:Hide() end
        if dsb.scrollUp         then dsb.scrollUp:Hide()         end
        if dsb.scrollDown       then dsb.scrollDown:Hide()       end
        local thumb = dsb.ThumbTexture or dsb.thumbTexture
        if thumb then thumb:SetColorTexture(rgba(P.border)); thumb:SetWidth(6) end
        dsb:SetWidth(6)
        if dsb.Background then dsb.Background:SetAlpha(0) end
    end

    local titleLbl = NewLabel(detailChild, 12, "OVERLAY")
    titleLbl:SetPoint("TOPLEFT",  detailChild, "TOPLEFT",  0, 0)
    titleLbl:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, 0)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(true)
    df.titleLabel = titleLbl

    local divD = NewTex(detailChild, "BORDER")
    divD:SetHeight(1)
    divD:SetPoint("TOPLEFT",  detailChild, "TOPLEFT",  0, -26)
    divD:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, -26)
    divD:SetColorTexture(rgba(P.border))

    local bodyLbl = NewLabel(detailChild, 11, "OVERLAY")
    bodyLbl:SetPoint("TOPLEFT",  detailChild, "TOPLEFT",  0, -32)
    bodyLbl:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, -32)
    bodyLbl:SetJustifyH("LEFT")
    bodyLbl:SetWordWrap(true)
    bodyLbl:SetTextColor(0.75, 0.70, 0.58)
    df.bodyLabel = bodyLbl

    local objLbl = NewLabel(detailChild, 11, "OVERLAY")
    objLbl:SetPoint("TOPLEFT",  bodyLbl, "BOTTOMLEFT",  0, -8)
    objLbl:SetPoint("TOPRIGHT", bodyLbl, "BOTTOMRIGHT", 0, -8)
    objLbl:SetJustifyH("LEFT")
    objLbl:SetWordWrap(true)
    df.objLabel = objLbl

    -- ── rewards section ───────────────────────────────────────────────────────
    local rewardDiv = NewTex(detailChild, "BORDER")
    rewardDiv:SetHeight(1)
    rewardDiv:SetColorTexture(rgba(P.border))
    df.rewardDiv = rewardDiv

    local rewardHdr = NewLabel(detailChild, 10, "OVERLAY")
    rewardHdr:SetJustifyH("LEFT")
    rewardHdr:SetTextColor(rgba(P.fel))
    df.rewardHdr = rewardHdr

    -- pools of reward icon buttons (created on demand, reused)
    df.rewardIcons  = {}  -- "must get" items
    df.choiceIcons  = {}  -- "choose one" items

    local rewardMoneyLbl = NewLabel(detailChild, 10, "OVERLAY")
    rewardMoneyLbl:SetJustifyH("LEFT")
    rewardMoneyLbl:SetTextColor(rgba(P.text))
    df.rewardMoneyLbl = rewardMoneyLbl

    local rewardXPLbl = NewLabel(detailChild, 10, "OVERLAY")
    rewardXPLbl:SetJustifyH("LEFT")
    rewardXPLbl:SetTextColor(0.6, 0.6, 0.6)
    df.rewardXPLbl = rewardXPLbl

    -- action buttons row at bottom of detail panel — centered as a group
    -- 3 buttons × 68px + 2 gaps × 8px = 220px total group width
    -- each button CENTER-anchored at -74, 0, +74 relative to df CENTER
    local trackBtn, tLbl = MakeButton(df, "Track", 68, 18)
    trackBtn:SetPoint("BOTTOM", df, "BOTTOM", -74, 4)
    trackBtn._lbl = tLbl
    trackBtn:SetScript("OnClick", function()
        if not QL.selectedIdx then return end
        if IsQuestWatched(QL.selectedIdx) then
            RemoveQuestWatch(QL.selectedIdx)
        else
            AddQuestWatch(QL.selectedIdx)
        end
        QL:Refresh()
        PopulateDetail(QL.selectedIdx)
        if ns.QuestTracker then ns.QuestTracker:Refresh() end
    end)
    df.trackBtn = trackBtn

    local shareBtn, _ = MakeButton(df, "Share", 68, 18)
    shareBtn:SetPoint("BOTTOM", df, "BOTTOM", 0, 4)
    shareBtn:SetScript("OnClick", function()
        if not QL.selectedIdx then return end
        SelectQuestLogEntry(QL.selectedIdx)
        if C_QuestLog and C_QuestLog.PushQuest then
            local questID = select(8, GetQuestLogTitle(QL.selectedIdx))
            if questID then C_QuestLog.PushQuest(questID) end
        else
            QuestLogPushQuest()
        end
    end)
    df.shareBtn = shareBtn

    local abandonBtn, aLbl = MakeButton(df, "Abandon", 68, 18)
    abandonBtn:SetPoint("BOTTOM", df, "BOTTOM", 74, 4)
    aLbl:SetTextColor(1, 0.4, 0.4)
    abandonBtn:SetScript("OnClick", function()
        if not QL.selectedIdx then return end
        SelectQuestLogEntry(QL.selectedIdx)
        SetAbandonQuest()
        local title = GetAbandonQuestName and GetAbandonQuestName() or select(1, GetQuestLogTitle(QL.selectedIdx))
        StaticPopup_Show("ABANDON_QUEST", title)
    end)
    df.abandonBtn = abandonBtn

    QL.detailFrame = df

    -- ── resize grip — invisible hotspot; the BR corner bracket is the visual ──
    local grip = CreateFrame("Frame", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp",   function() f:StopMovingOrSizing() end)
    grip:SetScript("OnEnter", function()
        -- Brighten the BR bracket on hover as a resize hint
        for _, t in ipairs(f._brAccents or {}) do t:SetColorTexture(1, 1, 1, 0.9) end
    end)
    grip:SetScript("OnLeave", function()
        for _, t in ipairs(f._brAccents or {}) do t:SetColorTexture(rgba(P.fel)) end
    end)

    f:Hide()
end

-- ─── public API ──────────────────────────────────────────────────────────────
function QL:Show()
    if not QL.frame then QL:Build() end
    QL.frame:Show()
end

function QL:Hide()
    if QL.frame then QL.frame:Hide() end
end

function QL:Toggle()
    if QL.frame and QL.frame:IsShown() then
        QL:Hide()
    else
        QL:Show()
    end
end

-- ─── debug ───────────────────────────────────────────────────────────────────
SLASH_WQLDBG1 = "/wqldbg"
SlashCmdList["WQLDBG"] = function()
    local p = function(s) DEFAULT_CHAT_FRAME:AddMessage(s) end
    local n = GetNumQuestLogEntries()
    p("|cff4FC778WQL Debug:|r entries=" .. tostring(n))
    for i = 1, math.min(n, 5) do
        local title, level, tag, isHeader = GetQuestLogTitle(i)
        p(("  [%d] header=%s level=%s title=%s"):format(i, tostring(isHeader), tostring(level), tostring(title)))
    end
    local db = WUI.db and WUI.db.questlog
    p(("  db.x=%s db.y=%s filter=%s"):format(tostring(db and db.x), tostring(db and db.y), tostring(db and db.filter)))
    p(("  QL.frame=%s shown=%s"):format(tostring(QL.frame ~= nil), tostring(QL.frame and QL.frame:IsShown())))
    if QL.listScroll then
        p(("  listScroll w=%s h=%s"):format(tostring(QL.listScroll:GetWidth()), tostring(QL.listScroll:GetHeight())))
    else
        p("  listScroll=nil")
    end
    if QL.listChild then
        p(("  listChild w=%s h=%s"):format(tostring(QL.listChild:GetWidth()), tostring(QL.listChild:GetHeight())))
    else
        p("  listChild=nil")
    end
    p(("  rows built=%d"):format(#QL.rows))
    -- Force a refresh right now and report
    p("  forcing Refresh...")
    QL:Refresh()
    p(("  rows after refresh=%d"):format(#QL.rows))
    for i, row in ipairs(QL.rows) do
        p(("  row[%d] shown=%s questIdx=%s"):format(i, tostring(row:IsShown()), tostring(row._questIdx)))
        if i >= 5 then break end
    end
end

-- ─── init (called from WUI:Init) ─────────────────────────────────────────────
function QL:Init()
    P = WUI.palette

    -- Merge defaults
    if WUI.db then
        if not WUI.db.questlog then WUI.db.questlog = {} end
        local db = WUI.db.questlog
        for k, v in pairs(DB_DEFAULTS.questlog) do
            if db[k] == nil then db[k] = v end
        end
        QL.filter = db.filter or "all"
    end

    -- Register for quest update events
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    ev:SetScript("OnEvent", function()
        if QL.frame and QL.frame:IsShown() then
            QL:Refresh()
        end
    end)

    -- Install Blizzard intercepts on PLAYER_ENTERING_WORLD — this fires after
    -- all addons and the Blizzard UI have fully initialised, so QuestLogFrame
    -- and ToggleQuestLog are guaranteed to exist. PLAYER_LOGIN fires mid-init
    -- inside ElvUI's hook chain and is already past by the time we'd register.
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- Any time Blizzard's frame tries to show, close it silently.
        if QuestLogFrame then
            QuestLogFrame:HookScript("OnShow", function()
                QuestLogFrame:Hide()
            end)
        end

        -- Overwrite the global so the 'L' keybind (TOGGLEQUESTLOG) and any
        -- addon calling ToggleQuestLog() goes to us instead of Blizzard.
        ToggleQuestLog = function()
            QL:Toggle()
        end

        -- Also cover ShowQuestLog (micro-bar, some addons).
        ShowQuestLog = function()
            QL:Show()
        end
    end)
end
