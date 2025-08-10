local API = _G.AltUp_API
if not API then
  -- Safety: if core didn't load, bail
  return
end

------------------------------------------------------------
-- Styling: LibSharedMedia + ElvUI optional skin
------------------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- sensible defaults if LSM is missing, but prefer user’s LSM selections
local FONT_NAME = "Expressway"           -- common with ElvUI packs
local BAR_NAME  = "ElvUI Norm"           -- statusbar texture many users have
local BG_NAME   = "Solid"                 -- background fill

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

-- Try to borrow ElvUI’s skin method if present
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
Title:SetText("Alt Upgrades in Bags")

-- Titles / labels
local titleFont, titleSize, titleFlags = FetchFont(14, "OUTLINE")
Title:SetFont(titleFont, titleSize, titleFlags)

-- Subtle status/banner line under the title
local Beta = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Beta:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -2)
Beta:SetText("|cffffd100Beta:|r rapid updates, expect frequent changes")

-- Close button
local Close = CreateFrame("Button", nil, UI, "UIPanelCloseButton")
Close:SetPoint("TOPRIGHT", 0, 0)

-- Refresh button
local RefreshBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
RefreshBtn:SetSize(80, 22)
RefreshBtn:SetPoint("TOPRIGHT", Close, "BOTTOMRIGHT", 0, -2)
RefreshBtn:SetText("Refresh")

-- Status line
local Status = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Status:SetPoint("TOPLEFT", Beta, "BOTTOMLEFT", 0, -6)
Status:SetText("Scanning...")

if Status then
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
Content:SetSize(1,1)  -- width will expand with lines
Scroll:SetScrollChild(Content)

-- Row background texture via SharedMedia (nice subtle striping)
local function StyleRowBG(tex, isAlt)
  tex:SetTexture(FetchBar())
  tex:SetVertexColor(1, 1, 1, isAlt and 0.08 or 0.12)
end

-- Row factory
local ROW_HEIGHT = 22
local rows = {}
local function CreateRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(Scroll:GetWidth()-8, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, - (index-1) * ROW_HEIGHT)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  StyleRowBG(row.bg, index % 2 == 0)

  row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.left:SetPoint("LEFT", 6, 0)
  row.left:SetJustifyH("LEFT")

  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.right:SetPoint("RIGHT", -6, 0)
  row.right:SetJustifyH("RIGHT")

  local rowFont, rowSize, rowFlags = FetchFont(12, "")
row.left:SetFont(rowFont, rowSize, rowFlags)
row.right:SetFont(rowFont, rowSize, rowFlags)

  -- Tooltip on hover to show full alt list
  row:SetScript("OnEnter", function(self)
    if not self.data then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.data.name, 1,1,1)
    GameTooltip:AddLine(self.data.link, 0.6,0.8,1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Upgrades:", 0.8,1,0.8)
    for i, u in ipairs(self.data.upgrades) do
      GameTooltip:AddLine(("• %s: +%d ilvl"):format(u.key, u.delta), 0.9,0.9,0.9)
      if i >= 12 then
        GameTooltip:AddLine(("…and %d more"):format(#self.data.upgrades - i), 0.7,0.7,0.7)
        break
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Click to print to chat
  row:SetScript("OnClick", function(self)
    if not self.data then return end
    local parts = {}
    for i=1, math.min(#self.data.upgrades, 6) do
      local u = self.data.upgrades[i]
      parts[#parts+1] = ("%s(+%d)"):format(u.key, u.delta)
    end
    print("|cff00ff00[AltUp]|r", self.data.link, "→", table.concat(parts, ", "),
      (#self.data.upgrades>6) and ("…+"..(#self.data.upgrades-6)) or "")
  end)

  return row
end

-- Ensure we have N rows
local function EnsureRows(n)
  local cur = #rows
  if cur >= n then return end
  for i = cur+1, n do
    rows[i] = CreateRow(Content, i)
  end
end

-- Layout rows with data
local function Layout(data)
  EnsureRows(#data)
  for i, row in ipairs(rows) do
    local item = data[i]
    if item then
      row:Show()
      row.data = item
      row.left:SetText(("%s |cffaaaaaa(ilvl %d)|r"):format(item.name or "Unknown", item.ilvl or 0))
      local top = item.upgrades[1]
      row.right:SetText(top and (top.key .. "  |cff00ff00+"..top.delta.."|rilvl") or "")
    else
      row:Hide()
      row.data = nil
    end
  end
  Content:SetHeight(#data * ROW_HEIGHT)
  Status:SetText(("%d item%s with upgrades"):format(#data, #data==1 and "" or "s"))
end


-- Collector-friendly Minimap Button (ProjectAzilroka compatible)
local btn = CreateFrame("Button", "AltUpgrades_MinimapButton", Minimap)
btn:SetSize(32, 32)
btn:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)

btn.isMinimapButton = true

-- Primary icon (collectors look for btn.icon)
btn.icon = btn.icon or btn:CreateTexture(nil, "ARTWORK")
btn.icon:SetAllPoints(btn)
btn.icon:SetTexture("Interface\\AddOns\\AltUpgrades\\media\\minimap")
btn.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

-- Also set NormalTexture (some collectors use this instead)
btn:SetNormalTexture("Interface\\AddOns\\AltUpgrades\\media\\minimap")
local nt = btn:GetNormalTexture(); nt:SetAllPoints(btn); nt:SetTexCoord(0.1,0.9,0.1,0.9)

btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

btn:SetScript("OnClick", function(self, mouseButton)
  if mouseButton == "LeftButton" then
    if AltUpgradesUI and AltUpgradesUI:IsShown() then
      AltUpgradesUI:Hide()
    else
      if AltUpgradesUI and AltUpgradesUI.RefreshList then AltUpgradesUI.RefreshList() end
      if AltUpgradesUI then AltUpgradesUI:Show() end
    end
  elseif mouseButton == "RightButton" then
    print("|cff00ff00AltUpgrades|r minimap button (right-click)")
  end
end)

btn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("|cff00ff00AltUpgrades|r")
  GameTooltip:AddLine("Left-click: Open/close window", 1,1,1)
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)




------------------------------------------------------------
-- Bag scan → data model
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
          table.insert(out, {
            name = name,
            link = link,
            ilvl = ilvl,
            upgrades = upgrades,
          })
        end
      end
    end
  end
  table.sort(out, function(a,b)
    -- Sort by best delta descending, then ilvl, then name
    local ad = a.upgrades[1] and a.upgrades[1].delta or 0
    local bd = b.upgrades[1] and b.upgrades[1].delta or 0
    if ad ~= bd then return ad > bd end
    if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
    return (a.name or "") < (b.name or "")
  end)
  return out
end

local function RefreshList()
  Status:SetText("Scanning...")
  C_Timer.After(0, function()
    local data = CollectUpgradesInBags()
    Layout(data)
  end)
end

local function RefreshMine()
  Status:SetText("Scanning account-wide upgrades for you...")
  C_Timer.After(0, function()
    local data = {}
    local vault = API.findVaultUpgradesForMe()
    for _, v in ipairs(vault) do
      local name = C_Item.GetItemInfo(v.link) or "Unknown"
      data[#data+1] = {
        name = name,
        link = v.link,
        ilvl = v.ilvl,
        upgrades = { { key = "|cffaaaaaaOwner:|r "..v.owner, delta = v.delta } }, -- reuse field
        owner = v.owner,
        delta = v.delta,
      }
    end
    -- show owner + delta on the right
    EnsureRows(#data)
    for i, row in ipairs(rows) do
      local item = data[i]
      if item then
        row:Show()
        row.data = item
        row.left:SetText(("%s |cffaaaaaa(ilvl %d)|r"):format(item.name or "Unknown", item.ilvl or 0))
        row.right:SetText(("%s  |cff00ff00+%d|rilvl"):format(item.owner or "?", item.delta or 0))
      else
        row:Hide()
        row.data = nil
      end
    end
    Content:SetHeight(#data * ROW_HEIGHT)
    Status:SetText(("%d upgrade%s found for you across all alts"):format(#data, #data==1 and "" or "s"))
  end)
end
AltUpgradesUI.RefreshMine = RefreshMine


-- make the real refresh available to other callers (minimap toggle, slash, etc.)
AltUpgradesUI.RefreshList = RefreshList

RefreshBtn:SetScript("OnClick", RefreshList)

------------------------------------------------------------
-- Slash command
------------------------------------------------------------
SLASH_ALTUPUI1 = "/altupui"
SlashCmdList.ALTUPUI = function()
  if UI:IsShown() then UI:Hide() else RefreshList(); UI:Show() end
end

SLASH_ALTUPFORME1 = "/altupforme"
SlashCmdList.ALTUPFORME = function()
  if not AltUpgradesUI:IsShown() then AltUpgradesUI:Show() end
  if AltUpgradesUI.RefreshMine then AltUpgradesUI.RefreshMine() end
end


------------------------------------------------------------
-- Auto-refresh on bag changes / login
------------------------------------------------------------
local E = CreateFrame("Frame")
E:RegisterEvent("PLAYER_LOGIN")
E:RegisterEvent("BAG_UPDATE_DELAYED")
E:SetScript("OnEvent", function(_, evt)
  if UI:IsShown() then
    RefreshList()
  end
end)
