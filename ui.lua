local API = _G.AltUp_API
if not API then
  -- Safety: if core didn't load, bail
  return
end

------------------------------------------------------------
-- Basic frame
------------------------------------------------------------
local UI = CreateFrame("Frame", "AltUpgradesUI", UIParent, "BackdropTemplate")
UI:SetSize(480, 360)
UI:SetPoint("CENTER")
UI:SetMovable(true)
UI:EnableMouse(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", UI.StartMoving)
UI:SetScript("OnDragStop", UI.StopMovingOrSizing)
UI:Hide()

-- Backdrop / style (simple)
UI:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
UI:SetBackdropColor(0, 0, 0, 0.85)

-- Title
local Title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
Title:SetPoint("TOPLEFT", 12, -10)
Title:SetText("Alt Upgrades in Bags")

-- Close button
local Close = CreateFrame("Button", nil, UI, "UIPanelCloseButton")
Close:SetPoint("TOPRIGHT", 0, 0)

-- Refresh button
local RefreshBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
RefreshBtn:SetSize(80, 22)
RefreshBtn:SetPoint("TOPRIGHT", Close, "BOTTOMRIGHT", -6, -6)
RefreshBtn:SetText("Refresh")

-- Status line
local Status = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Status:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -6)
Status:SetText("Scanning...")

------------------------------------------------------------
-- Scroll list
------------------------------------------------------------
local Scroll = CreateFrame("ScrollFrame", "AltUpgradesUIScroll", UI, "UIPanelScrollFrameTemplate")
Scroll:SetPoint("TOPLEFT", 12, -50)
Scroll:SetPoint("BOTTOMRIGHT", -28, 12)

local Content = CreateFrame("Frame", nil, Scroll)
Content:SetSize(1,1)  -- width will expand with lines
Scroll:SetScrollChild(Content)

-- Row factory
local ROW_HEIGHT = 22
local rows = {}
local function CreateRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(Scroll:GetWidth()-8, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, - (index-1) * ROW_HEIGHT)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1,1,1, index % 2 == 0 and 0.04 or 0.08)

  row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.left:SetPoint("LEFT", 6, 0)
  row.left:SetJustifyH("LEFT")

  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.right:SetPoint("RIGHT", -6, 0)
  row.right:SetJustifyH("RIGHT")

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
