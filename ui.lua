local API = _G.AltUp_API

if not API then
  -- Safety: if core didn't load, bail
  return
end

local FN = _G.AltUp_Fn
if not FN then
  print("|cffff0000AltUpgrades:|r functions.lua not loaded (check TOC order/filename).")
end


-- Persisted UI state (which tab was last used)
AltUpDB = AltUpDB or {}
AltUpDB.uiState = AltUpDB.uiState or { mode = "BAGS" }  -- "BAGS" or "VAULT"

------------------------------------------------------------
-- Styling: LibSharedMedia + ElvUI optional skin
------------------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- sensible defaults if LSM is missing, but prefer user’s LSM selections
local FONT_NAME = "Expressway"           -- common with ElvUI packs
local BAR_NAME  = "ElvUI Norm"           -- statusbar texture many users have
local BG_NAME   = "Solid"                -- background fill

local function FetchFont(size, flags)
  local path = LSM and LSM:Fetch("font", FONT_NAME) or "Fonts\\FRIZQT__.TTF"
  return path, size or 12, flags or "OUTLINE"
end

local function FetchBar()
  return (LSM and LSM:Fetch("statusbar", BAR_NAME)) or "Interface\\Buttons\\WHITE8x8"
end

local function FetchBG()
  return (LSM and LSM:Fetch("background", BG_NAME)) or "Interface\\Buttons\\WHITE8x8"
end

-- Robust ElvUI detection (works with/without C_AddOns)
local function IsLoaded(addon)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded(addon)
  elseif IsAddOnLoaded then
    return IsAddOnLoaded(addon)
  else
    return false
  end
end

local E, L, V, P, G
local S -- ElvUI Skins module
if IsLoaded("ElvUI") and ElvUI then
  ---@diagnostic disable-next-line: undefined-global
  E, L, V, P, G = unpack(ElvUI)
  if E and E.GetModule then
    S = E:GetModule("Skins")
  end
end

-- Apply a consistent look. If ElvUI is present, let it handle borders/colors.
local function SkinFrame(frame)
  frame:SetBackdrop(nil) -- let ElvUI or our code set it cleanly
  if S and S.HandleFrame then
    -- ElvUI will set its own template/backdrop/colors
    S:HandleFrame(frame, true) -- 'true' = default template
  else
    -- Fallback Blizzard-style with SharedMedia textures
    frame:SetBackdrop({
      bgFile   = FetchBG(),
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      tile = true, tileSize = 16, edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
  end
end

------------------------------------------------------------
-- Basic frame
------------------------------------------------------------
local UI = CreateFrame("Frame", "AltUpgradesUI", UIParent, "BackdropTemplate")
SkinFrame(UI)  -- make the main window pretty

UI:SetSize(480, 360)
UI:SetPoint("CENTER")
UI:SetMovable(true)
UI:EnableMouse(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", UI.StartMoving)
UI:SetScript("OnDragStop", UI.StopMovingOrSizing)
UI:Hide()

-- Title
local Title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
Title:SetPoint("TOPLEFT", 12, -10)
Title:SetText("AltUpgrades")

-- Titles / labels
do
  local f, s, fl = FetchFont(14, "OUTLINE")
  Title:SetFont(f, s, fl)
end

-- Subtle status/banner line under the title
local Beta = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Beta:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -2)
Beta:SetText("|cffffd100Beta:|r rapid updates — expect frequent changes")

do
  local ADDON = ...
  local GETMETA = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local VER = GETMETA and GETMETA(ADDON, "Version") or "dev"
  if tostring(VER):lower():find("alpha") then
    Beta:SetText("|cffff0000ALPHA:|r experimental build — expect frequent changes")
  end
end


-- Close button
local Close = CreateFrame("Button", nil, UI, "UIPanelCloseButton")
Close:SetPoint("TOPRIGHT", 0, 0)

-- Refresh button (now refreshes the *active tab*)
local RefreshBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
RefreshBtn:SetSize(80, 22)
RefreshBtn:SetPoint("TOPRIGHT", Close, "BOTTOMRIGHT", 0, -2)
RefreshBtn:SetText("Refresh")

-- Status line
local Status = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Status:SetPoint("TOPLEFT", Beta, "BOTTOMLEFT", 0, -6)
Status:SetText("Ready.")
do
  local f, s, fl = FetchFont(12, "")
  Status:SetFont(f, s, fl)
end

------------------------------------------------------------
-- Scroll list
------------------------------------------------------------
local Scroll = CreateFrame("ScrollFrame", "AltUpgradesUIScroll", UI, "UIPanelScrollFrameTemplate")
Scroll:SetPoint("TOPLEFT", 12, -50)
Scroll:SetPoint("BOTTOMRIGHT", -28, 12)

local Content = CreateFrame("Frame", nil, Scroll)
Content:SetSize(1, 1)  -- width will expand with lines
Scroll:SetScrollChild(Content)

-- Row background texture via SharedMedia (nice subtle striping)
local function StyleRowBG(tex, isAlt)
  tex:SetTexture(FetchBar())
  tex:SetVertexColor(1, 1, 1, isAlt and 0.08 or 0.12)
end

-- Rows
local ROW_HEIGHT = 22
local rows = {}

local function CreateRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(Scroll:GetWidth() - 8, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, - (index - 1) * ROW_HEIGHT)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  StyleRowBG(row.bg, index % 2 == 0)

  row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.left:SetPoint("LEFT", 6, 0)
  row.left:SetJustifyH("LEFT")

  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.right:SetPoint("RIGHT", -6, 0)
  row.right:SetJustifyH("RIGHT")

  local rf, rs, rfl = FetchFont(12, "")
  row.left:SetFont(rf, rs, rfl)
  row.right:SetFont(rf, rs, rfl)

  -- Tooltip on hover (differs per tab)
  row:SetScript("OnEnter", function(self)
    if not self.data then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.data.name or "Item", 1, 1, 1)
    if self.data.link then GameTooltip:AddLine(self.data.link, 0.6, 0.8, 1) end
    GameTooltip:AddLine(" ")

    local mode = (AltUpDB.uiState and AltUpDB.uiState.mode) or "BAGS"
    if mode == "VAULT" then
      GameTooltip:AddLine("Owner / Upgrade:", 0.8, 1, 0.8)
      GameTooltip:AddLine(("• %s: +%d ilvl"):format(self.data.owner or "?", self.data.delta or 0), 0.9, 0.9, 0.9)
    else
      GameTooltip:AddLine("Upgrades for:", 0.8, 1, 0.8)
      local ups = self.data.upgrades or {}
      for i = 1, math.min(#ups, 12) do
  local u = ups[i]
  if u.note then
    GameTooltip:AddLine(("• %s: +%d ilvl  |cffffff00(⚠ %s)|r"):format(u.key, u.delta, u.note), 0.9, 0.9, 0.9)
  else
    GameTooltip:AddLine(("• %s: +%d ilvl"):format(u.key, u.delta), 0.9, 0.9, 0.9)
  end
end

      if #ups > 12 then
        GameTooltip:AddLine(("…and %d more"):format(#ups - 12), 0.7, 0.7, 0.7)
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Click to print to chat (context aware)
  row:SetScript("OnClick", function(self)
    if not self.data then return end
    local mode = (AltUpDB.uiState and AltUpDB.uiState.mode) or "BAGS"
    if mode == "VAULT" then
      print("|cff00ff00[AltUp]|r", self.data.link or "?", "→",
        ("%s (+%d)"):format(self.data.owner or "?", self.data.delta or 0))
    else
      local parts = {}
      for i = 1, math.min(#(self.data.upgrades or {}), 6) do
        local u = self.data.upgrades[i]
        parts[#parts + 1] = ("%s(+%d)"):format(u.key, u.delta)
      end
      print("|cff00ff00[AltUp]|r", self.data.link or "?", "→",
        table.concat(parts, ", "),
        (#(self.data.upgrades or {} ) > 6) and ("…+" .. (#self.data.upgrades - 6)) or "")
    end
  end)

  return row
end

local function EnsureRows(n)
  local cur = #rows
  if cur >= n then return end
  for i = cur + 1, n do
    rows[i] = CreateRow(Content, i)
  end
end

local function HideAllRows()
  for _, row in ipairs(rows) do
    row:Hide()
    row.data = nil
  end
end

-- Layouts for each tab
local function LayoutBags(data)
  EnsureRows(#data)
  for i, row in ipairs(rows) do
    local item = data[i]
    if item then
      row:Show()
      row.data = item
      row.left:SetText(("%s |cffaaaaaa(ilvl %d)|r"):format(item.name or "Unknown", item.ilvl or 0))
      local top = item.upgrades and item.upgrades[1]
if top then
  local note = top.note and (" |cffffff00(⚠ "..top.note..")|r") or ""
  row.right:SetText(("%s  |cff00ff00+%d|rilvl%s"):format(top.key, top.delta, note))
else
  row.right:SetText("")
end

    else
      row:Hide(); row.data = nil
    end
  end
  Content:SetHeight(#data * ROW_HEIGHT)
  Status:SetText(("%d item%s in your bags upgrade others"):format(#data, #data == 1 and "" or "s"))
end

local function LayoutVault(data)
  EnsureRows(#data)
  for i, row in ipairs(rows) do
    local item = data[i]
    if item then
      row:Show()
      row.data = item
      row.left:SetText(("%s |cffaaaaaa(ilvl %d)|r"):format(item.name or "Unknown", item.ilvl or 0))
      row.right:SetText(("%s  |cff00ff00+%d|rilvl"):format(item.owner or "?", item.delta or 0))
    else
      row:Hide(); row.data = nil
    end
  end
  Content:SetHeight(#data * ROW_HEIGHT)
  Status:SetText(("%d upgrade%s found for you across all alts"):format(#data, #data == 1 and "" or "s"))
end

------------------------------------------------------------
-- Minimap Button (collector-friendly + edge placement + drag)
------------------------------------------------------------
AltUpDB = AltUpDB or {}
AltUpDB.minimap = AltUpDB.minimap or { angle = 90, hide = false } -- default 90°

-- Helper: compute x/y along the minimap rim for a given angle (degrees)
local function Minimap_CalcXY(angleDeg)
  local radius = (Minimap:GetWidth() / 2) + 4
  local r = math.rad(angleDeg or 90)
  local x = math.cos(r)
  local y = math.sin(r)

  -- Respect square/round minimap shapes
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    -- Clamp to a square region slightly larger so it stays visible
    local sx = math.max(-1, math.min(x * 1.05, 1))
    local sy = math.max(-1, math.min(y * 1.05, 1))
    return sx * radius, sy * radius
  else
    -- Default ROUND and hybrids
    return x * radius, y * radius
  end
end

-- Helper: place the button using saved angle (only if parent is Minimap)
local function Minimap_SetButtonPosition(btn)
  if not btn or btn:GetParent() ~= Minimap then return end
  local angle = AltUpDB.minimap.angle or 90
  local px, py = Minimap_CalcXY(angle)
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", px, py)
end

-- Create button
local mm = CreateFrame("Button", "AltUpgrades_MinimapButton", Minimap)
mm:SetSize(32, 32)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
mm.isMinimapButton = true
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetMovable(true)

-- Primary icon (collectors look for mm.icon)
mm.icon = mm.icon or mm:CreateTexture(nil, "ARTWORK")
mm.icon:SetAllPoints(mm)
mm.icon:SetTexture("Interface\\AddOns\\AltUpgrades\\media\\minimap")
mm.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

-- Also set NormalTexture (some collectors skin this)
mm:SetNormalTexture("Interface\\AddOns\\AltUpgrades\\media\\minimap")
local nt = mm:GetNormalTexture(); nt:SetAllPoints(mm); nt:SetTexCoord(0.1, 0.9, 0.1, 0.9)

mm:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
mm:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

-- Tooltip
mm:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("|cff00ff00AltUpgrades|r")
  GameTooltip:AddLine("Left-click: Open/close window", 1, 1, 1)
  GameTooltip:AddLine("Drag: Move button", 1, 1, 1)
  GameTooltip:AddLine("Right-click: Hide button (/altupmm to show)", 1, 1, 1)
  GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Clicks
mm:SetScript("OnClick", function(self, mouseButton)
  if mouseButton == "LeftButton" then
    if AltUpgradesUI:IsShown() then
      AltUpgradesUI:Hide()
    else
      AltUpgradesUI:Show()
    end
  elseif mouseButton == "RightButton" then
    AltUpDB.minimap.hide = true
    self:Hide()
    print("|cff00ff00AltUpgrades:|r minimap button hidden. Use |cffffff00/altupmm|r to show.")
  end
end)

-- Drag to reposition around the rim
mm:SetScript("OnDragStart", function(self)
  self.isDragging = true
  self:LockHighlight()
end)
mm:SetScript("OnDragStop", function(self)
  self.isDragging = false
  self:UnlockHighlight()
end)
mm:SetScript("OnUpdate", function(self)
  if not self.isDragging then return end
  -- compute angle from minimap center to cursor
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  cx, cy = cx / scale, cy / scale
  local angle = math.deg(math.atan2(cy - my, cx - mx))
  angle = (angle + 360) % 360
  AltUpDB.minimap.angle = angle
  Minimap_SetButtonPosition(self)
end)

-- Initial show/position (don’t fight collectors; only position if parent is Minimap)
local function Minimap_UpdateVisibility()
  if AltUpDB.minimap.hide then mm:Hide() else mm:Show() end
end
Minimap_UpdateVisibility()
Minimap_SetButtonPosition(mm)

-- If the minimap resizes or changes shape, re-place the button
mm:RegisterEvent("PLAYER_LOGIN")
mm:RegisterEvent("PLAYER_ENTERING_WORLD")
mm:RegisterEvent("DISPLAY_SIZE_CHANGED")
mm:RegisterEvent("UI_SCALE_CHANGED")
mm:SetScript("OnEvent", function()
  Minimap_SetButtonPosition(mm)
end)

-- Slash to re-show if hidden
SLASH_ALTUPMM1 = "/altupmm"
SlashCmdList.ALTUPMM = function()
  AltUpDB.minimap.hide = false
  Minimap_UpdateVisibility()
  Minimap_SetButtonPosition(mm)
  print("|cff00ff00AltUpgrades:|r minimap button shown.")
end


------------------------------------------------------------
-- Data collectors
------------------------------------------------------------
local function CollectUpgradesInBags()
  local out = {}
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local link = info and info.hyperlink
      if link and API.isTradableEquippable(link) then
        local upgrades = API.findAltUpgrades(link)
        if upgrades and #upgrades > 0 then
          local name = (C_Item.GetItemInfo(link)) or "Unknown"
          local ilvl = API.itemLevelFromLink(link)
          out[#out + 1] = { name = name, link = link, ilvl = ilvl, upgrades = upgrades }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    local ad = a.upgrades[1] and a.upgrades[1].delta or 0
    local bd = b.upgrades[1] and b.upgrades[1].delta or 0
    if ad ~= bd then return ad > bd end
    if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
    return (a.name or "") < (b.name or "")
  end)
  return out
end

------------------------------------------------------------
-- Refreshers (per tab)
------------------------------------------------------------
local function RefreshList()
  Status:SetText("Scanning your bags for items that help your other alts...")
  C_Timer.After(0, function()
    local data = CollectUpgradesInBags()
    LayoutBags(data)
  end)
end
AltUpgradesUI.RefreshList = RefreshList

local function RefreshMine()
  Status:SetText("Scanning account-wide upgrades for you...")
  C_Timer.After(0, function()
    local data, vault = {}, API.findVaultUpgradesForMe()
    for _, v in ipairs(vault or {}) do
      local name = C_Item.GetItemInfo(v.link) or "Unknown"
      data[#data + 1] = {
        name = name, link = v.link, ilvl = v.ilvl or 0,
        owner = v.owner, delta = v.delta or 0,
      }
    end
    LayoutVault(data)
  end)
end
AltUpgradesUI.RefreshMine = RefreshMine

-- Refresh button honors active tab
RefreshBtn:SetScript("OnClick", function()
  local mode = (AltUpDB.uiState and AltUpDB.uiState.mode) or "BAGS"
  if mode == "VAULT" then RefreshMine() else RefreshList() end
end)


------------------------------------------------------------
-- Tabs (Blizzard PanelTabButtonTemplate)
------------------------------------------------------------
-- SetMode(mode) is defined below in this block.

-- 1) Create two real tabs (with IDs!)
local Tab1 = CreateFrame("Button", "AltUpgradesTab1", UI, "PanelTabButtonTemplate")
Tab1:SetPoint("TOPLEFT", UI, "TOPLEFT", 12, -70)  -- under title+beta
Tab1:SetText("Upgrades for Others")
Tab1:SetID(1)
PanelTemplates_TabResize(Tab1, 0)

local Tab2 = CreateFrame("Button", "AltUpgradesTab2", UI, "PanelTabButtonTemplate")
Tab2:SetPoint("LEFT", Tab1, "RIGHT", -14, 0)
Tab2:SetText("Upgrades for Me")
Tab2:SetID(2)
PanelTemplates_TabResize(Tab2, 0)

-- 2) Register with panel helpers
PanelTemplates_SetNumTabs(UI, 2)
UI.tabs = { Tab1, Tab2 }

-- 3) Mode switch + render
local function SetMode(mode)
  AltUpDB.uiState = AltUpDB.uiState or { mode = "BAGS" }
  AltUpDB.uiState.mode = mode or AltUpDB.uiState.mode or "BAGS"
  HideAllRows()
  if AltUpDB.uiState.mode == "BAGS" then
    RefreshList()
    PanelTemplates_SetTab(UI, 1)
    PanelTemplates_SelectTab(Tab1); PanelTemplates_DeselectTab(Tab2)
    Tab1:Disable(); Tab2:Enable()
  else
    RefreshMine()
    PanelTemplates_SetTab(UI, 2)
    PanelTemplates_SelectTab(Tab2); PanelTemplates_DeselectTab(Tab1)
    Tab2:Disable(); Tab1:Enable()
  end
end

-- 4) Click handlers
Tab1:SetScript("OnClick", function() SetMode("BAGS") end)
Tab2:SetScript("OnClick", function() SetMode("VAULT") end)

-- 5) Init to last-used tab when opened
AltUpgradesUI:HookScript("OnShow", function()
  local m = (AltUpDB.uiState and AltUpDB.uiState.mode) or "BAGS"
  SetMode(m)
end)

-- 6) Push list down under tabs
Scroll:ClearAllPoints()
Scroll:SetPoint("TOPLEFT", 12, -50 - 60)
Scroll:SetPoint("BOTTOMRIGHT", -28, 12)

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
SLASH_ALTUPUI1 = "/altupui"
SlashCmdList.ALTUPUI = function()
  if UI:IsShown() then UI:Hide() else AltUpgradesUI:Show() end
end

SLASH_ALTUPFORME1 = "/altupforme"
SlashCmdList.ALTUPFORME = function()
  AltUpDB.uiState.mode = "VAULT"
  if not AltUpgradesUI:IsShown() then AltUpgradesUI:Show() else SetMode("VAULT") end
end

------------------------------------------------------------
-- Auto-refresh on bag changes / login (active tab only)
------------------------------------------------------------
local EvFrame = CreateFrame("Frame")
EvFrame:RegisterEvent("PLAYER_LOGIN")
EvFrame:RegisterEvent("BAG_UPDATE_DELAYED")
EvFrame:SetScript("OnEvent", function(_, evt)
  if not UI:IsShown() then return end
  local mode = (AltUpDB.uiState and AltUpDB.uiState.mode) or "BAGS"
  if mode == "VAULT" then RefreshMine() else RefreshList() end
end)
