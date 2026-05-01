local addonName, ns = ...

ns.addonName = addonName
ns.errors = {}
ns.status = { initRan = false, hookInstalled = false, optionsRegistered = false }

-- TBC Classic Anniversary 2.5.5 moved these to the C_AddOns namespace;
-- fall back to the legacy globals only if the new API isn't there.
local IsAddOnLoaded    = (C_AddOns and C_AddOns.IsAddOnLoaded)    or _G.IsAddOnLoaded
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ns.IsAddOnLoaded    = IsAddOnLoaded
ns.GetAddOnMetadata = GetAddOnMetadata

-- Register the diagnostic slash command FIRST, so /wui always works even if
-- the rest of the file errors. This is the load-time fault detector.
SLASH_WICKSUI1 = "/wui"
SlashCmdList["WICKSUI"] = function()
    local function p(line) DEFAULT_CHAT_FRAME:AddMessage(line) end
    local function tf(v) return v and "yes" or "no" end
    p("|cff4FC778Wick's UI|r status:")
    local loaded = IsAddOnLoaded and IsAddOnLoaded("WicksUI")
    p(("  AddOn loaded:  %s"):format(tf((loaded or 0) ~= 0 and loaded ~= false)))
    p(("  ElvUI global:  %s"):format(tf(_G.ElvUI ~= nil)))
    p(("  AceAddon lib:  %s"):format(tf(LibStub and LibStub("AceAddon-3.0", true) ~= nil)))
    p(("  EP plugin lib: %s"):format(tf(LibStub and LibStub("LibElvUIPlugin-1.0", true) ~= nil)))
    p(("  Init ran:      %s"):format(tf(ns.status.initRan)))
    p(("  EP hook set:   %s"):format(tf(ns.status.hookInstalled)))
    p(("  Options reg:   %s"):format(tf(ns.status.optionsRegistered)))
    p(("  ns.AddOptions: %s"):format(tf(ns.AddOptions ~= nil)))
    p(("  ns.Brackets:   %s"):format(tf(ns.Brackets ~= nil)))
    p(("  ns.Theme:      %s"):format(tf(ns.Theme ~= nil)))
    if #ns.errors > 0 then
        p(("|cffff4040Errors (%d):|r"):format(#ns.errors))
        for i, e in ipairs(ns.errors) do
            p(("  %d. %s"):format(i, tostring(e)))
        end
    else
        p("  No load-time errors recorded.")
    end
end

local function tryStep(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        table.insert(ns.errors, ("[%s] %s"):format(label, err or "unknown"))
    end
    return ok
end

-- ---- ElvUI integration ----
local E, EP, AceAddon, WUI

if not tryStep("require ElvUI", function()
    assert(_G.ElvUI, "ElvUI global not present (Dependencies missing or load order)")
    E = unpack(_G.ElvUI)
    assert(E, "ElvUI unpack returned nil for E")
end) then return end

if not tryStep("require LibElvUIPlugin", function()
    EP = LibStub("LibElvUIPlugin-1.0")
    assert(EP, "LibElvUIPlugin-1.0 not found via LibStub")
end) then return end

if not tryStep("require AceAddon", function()
    AceAddon = (E.Libs and E.Libs.AceAddon) or LibStub("AceAddon-3.0")
    assert(AceAddon, "AceAddon-3.0 not found")
end) then return end

if not tryStep("create plugin addon", function()
    WUI = AceAddon:NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
    assert(WUI, "AceAddon:NewAddon returned nil")
    ns.WUI = WUI
    ns.E   = E
    ns.EP  = EP
    WUI.title   = "|cffD4C8A1Wick's|r |cff4FC778UI|r"
    WUI.version = GetAddOnMetadata(addonName, "Version")
    WUI.palette = {
        fel    = { 0.310, 0.780, 0.471, 1 },
        void   = { 0.051, 0.039, 0.078, 1 },
        shadow = { 0.090, 0.067, 0.141, 1 },
        border = { 0.220, 0.188, 0.345, 1 },
        text   = { 0.831, 0.784, 0.631, 1 },
    }
end) then return end

local DEFAULTS = {
    brackets = { enabled = true, size = 10, thickness = 2 },
    theme    = { applied = false },
}

local function deepCopy(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then out[k] = deepCopy(v) else out[k] = v end
    end
    return out
end

local function mergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            mergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function WUI:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(("|cff4FC778Wick's UI:|r %s"):format(tostring(msg)))
end

function WUI:Init()
    WicksUIDB = WicksUIDB or deepCopy(DEFAULTS)
    mergeDefaults(WicksUIDB, DEFAULTS)
    self.db = WicksUIDB
    ns.status.initRan = true

    if ns.AddOptions then
        local ok, err = pcall(EP.RegisterPlugin, EP, addonName, ns.AddOptions)
        if ok then
            ns.status.optionsRegistered = true
        else
            table.insert(ns.errors, ("[RegisterPlugin] %s"):format(err or "?"))
        end
    end

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:Print(("v%s loaded."):format(self.version or "?"))
end

function WUI:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if ns.Brackets and ns.Brackets.ApplyAll and self.db and self.db.brackets.enabled then
        ns.Brackets:ApplyAll()
    end
end

-- HookInitialize fires when ElvUI's plugin system is ready. We try the EP
-- method directly first (works in BenikUI / TBC 2.5.5); fall back to
-- E.Libs.EP if the LibStub-grabbed copy doesn't expose it for some reason.
tryStep("install EP hook", function()
    local target = (EP.HookInitialize and EP) or (E.Libs and E.Libs.EP)
    assert(target and target.HookInitialize, "HookInitialize not available")
    target:HookInitialize(WUI, WUI.Init)
    ns.status.hookInstalled = true
end)
