----------------------------------------
-- Alt Upgrades (BoE) - core.lua
-- Responsibilities:
--  • Maintain SavedVariables (AltUpDB)
--  • Snapshot equipped gear per character
--  • Decide if an item is a tradable upgrade for any alt
--  • Tooltip augmentation via TooltipDataProcessor
--  • Expose minimal API for UI (AltUp_API)
----------------------------------------
local ADDON = ...
AltUpDB = AltUpDB or { chars = {}, minimap = AltUpDB and AltUpDB.minimap or { angle = 45, hide = false } }

-- =========================
-- Debug (toggle via /altupdebug, optional SHIFT gating)
-- =========================
local ALTUP_DEBUG = false
local ALTUP_DEBUG_SHIFT = false
local function dprint(...)
  if ALTUP_DEBUG and (not ALTUP_DEBUG_SHIFT or IsShiftKeyDown()) then
    print("|cff00ff00[AltUp]|r", ...)
  end
end

-- =========================
-- Constants / Lookups
-- =========================
-- Flexible slots: ignore armor/stat checks
local FLEX_EQUIP = {
  INVTYPE_FINGER=1, INVTYPE_TRINKET=1, INVTYPE_NECK=1, INVTYPE_CLOAK=1
}

-- Max armor tier per class (1=Cloth, 2=Leather, 3=Mail, 4=Plate)
local MAX_ARMOR_BY_CLASS = {
  WARRIOR=4, PALADIN=4, DEATHKNIGHT=4,
  EVOKER=3, HUNTER=3, SHAMAN=3,
  ROGUE=2, DRUID=2, MONK=2, DEMONHUNTER=2,
  PRIEST=1, MAGE=1, WARLOCK=1,
}

-- Allowed primary stats per class (multi-spec friendly)
local CLASS_ALLOWED_STATS = {
  WARRIOR = { STRENGTH=true },
  DEATHKNIGHT = { STRENGTH=true },
  PALADIN = { STRENGTH=true, INTELLECT=true },
  DEMONHUNTER = { AGILITY=true },
  HUNTER = { AGILITY=true },
  ROGUE = { AGILITY=true },
  DRUID = { AGILITY=true, INTELLECT=true },
  MONK = { AGILITY=true, INTELLECT=true },
  SHAMAN = { AGILITY=true, INTELLECT=true },
  EVOKER = { INTELLECT=true },
  PRIEST = { INTELLECT=true },
  MAGE = { INTELLECT=true },
  WARLOCK = { INTELLECT=true },
}

-- Optional: hide tiny upgrades (set to 0 to disable)
local MIN_UPGRADE_DELTA = 0

-- Slots to snapshot
local TRACK_SLOTS = {
  INVSLOT_HEAD, INVSLOT_NECK, INVSLOT_SHOULDER, INVSLOT_BACK, INVSLOT_CHEST,
  INVSLOT_WRIST, INVSLOT_HAND, INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET,
  INVSLOT_FINGER1, INVSLOT_FINGER2, INVSLOT_TRINKET1, INVSLOT_TRINKET2,
  INVSLOT_MAINHAND, INVSLOT_OFFHAND,
}

-- Primary stat detection
local PRIMARY_STAT_PATTERNS = {
  AGILITY   = { " Agility", " of Agility" },
  STRENGTH  = { " Strength", " of Strength" },
  INTELLECT = { " Intellect", " of Intellect" },
}

-- =========================
-- Small helpers
-- =========================
---@type GameTooltip
local scanTip = CreateFrame("GameTooltip", "AltUpgradesScanTip", UIParent, "GameTooltipTemplate")

local function getPlayerKey()
  return UnitName("player").."-"..GetRealmName()
end

local function ItemLevelFromLink(link)
  local _, _, _, ilvl = C_Item.GetItemInfo(link)
  if not ilvl then dprint("ItemLevelFromLink: cache miss for", link) end
  return ilvl or 0
end

local function ItemLevelFromEquipSlot(slot)
  local loc = ItemLocation:CreateFromEquipmentSlot(slot)
  if C_Item.DoesItemExist(loc) then
    return C_Item.GetCurrentItemLevel(loc) or 0
  end
  return 0
end

-- Snapshot equipped gear for this character (class/level/spec + slot ilvls)
local function scanEquipped()
  local key = getPlayerKey()
  local _, classFile = UnitClassBase("player")
  local c = AltUpDB.chars[key] or {}
  c.class = classFile
  c.level = UnitLevel("player")
  c.specID = GetSpecialization() and GetSpecializationInfo(GetSpecialization()) or nil
  c.slots = c.slots or {}
  for _, slot in ipairs(TRACK_SLOTS) do
    c.slots[slot] = ItemLevelFromEquipSlot(slot)
  end
  AltUpDB.chars[key] = c
  dprint("Scanned:", key)
end

-- Counts BoE (2) and BoU (3) as tradable; rejects Soulbound(1)/Quest(4) and items bound in your bags
local function isTradableEquippable(link)
  if not link then return false end

  -- If the *exact* hyperlink is in your bags and flagged bound, reject
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink == link and info.isBound then
        dprint("isTradableEquippable: found in bags and bound → NO")
        return false
      end
    end
  end

  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  local equippable = C_Item.IsEquippableItem(link)
  if equippable == nil then equippable = (equipLoc and equipLoc ~= "") end

  -- bindType is cached-only
  local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(link)
  if not bindType then
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetHyperlink(link)
    for i = 2, scanTip:NumLines() do
      local t = _G["AltUpgradesScanTipTextLeft"..i]:GetText() or ""
      if t == ITEM_BIND_ON_EQUIP then bindType = 2; break end
      if t == ITEM_BIND_ON_USE   then bindType = 3; break end
      if t == ITEM_SOULBOUND     then bindType = 1; break end
      if t == ITEM_BIND_QUEST    then bindType = 4; break end
    end
  end

  local tradable = (bindType == 2) or (bindType == 3)
  dprint("isTradableEquippable:", "equipLoc=", tostring(equipLoc), "bindType=", tostring(bindType), tradable and "OK" or "NO")
  return equippable and tradable and (equipLoc and equipLoc ~= "")
end

-- Map equipLoc → candidate slot(s) (multi-slot rings/trinkets)
local function equipLocToSlots(equipLoc)
  local map = {
    INVTYPE_HEAD={INVSLOT_HEAD}, INVTYPE_NECK={INVSLOT_NECK}, INVTYPE_SHOULDER={INVSLOT_SHOULDER},
    INVTYPE_CLOAK={INVSLOT_BACK}, INVTYPE_CHEST={INVSLOT_CHEST}, INVTYPE_ROBE={INVSLOT_CHEST},
    INVTYPE_WRIST={INVSLOT_WRIST}, INVTYPE_HAND={INVSLOT_HAND}, INVTYPE_WAIST={INVSLOT_WAIST},
    INVTYPE_LEGS={INVSLOT_LEGS}, INVTYPE_FEET={INVSLOT_FEET},
    INVTYPE_FINGER={INVSLOT_FINGER1,INVSLOT_FINGER2},
    INVTYPE_TRINKET={INVSLOT_TRINKET1,INVSLOT_TRINKET2},
    INVTYPE_WEAPON={INVSLOT_MAINHAND}, INVTYPE_2HWEAPON={INVSLOT_MAINHAND},
    INVTYPE_WEAPONMAINHAND={INVSLOT_MAINHAND}, INVTYPE_WEAPONOFFHAND={INVSLOT_OFFHAND},
    INVTYPE_SHIELD={INVSLOT_OFFHAND}, INVTYPE_HOLDABLE={INVSLOT_OFFHAND},
    INVTYPE_RANGED={INVSLOT_MAINHAND}, INVTYPE_RANGEDRIGHT={INVSLOT_MAINHAND},
  }
  return map[equipLoc]
end

-- Compare against the *worst* of multi-slot pairs (e.g., trinket1/trinket2)
local function worstAltIlvlForSlots(alt, slots)
  if not alt or not alt.slots or not slots then return 0 end
  local worst = math.huge
  for _, slot in ipairs(slots) do
    local have = alt.slots[slot] or 0
    if have < worst then worst = have end
  end
  return worst == math.huge and 0 or worst
end

-- Primary stat reader (tooltip scan) with weak cache
local statCache = setmetatable({}, { __mode="kv" })
local function primaryStatOf(link)
  if not link then return nil end
  local cached = statCache[link]; if cached ~= nil then return cached end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:SetHyperlink(link)
  for i = 2, scanTip:NumLines() do
    local text = _G["AltUpgradesScanTipTextLeft"..i]:GetText() or ""
    for stat, pats in pairs(PRIMARY_STAT_PATTERNS) do
      for _, p in ipairs(pats) do
        if text:find(p, 1, true) then
          statCache[link] = stat
          return stat
        end
      end
    end
  end
  statCache[link] = false
  return nil
end


-- Allowed weapon subclasses per class (Retail, conservative v1)
-- Enum.ItemWeaponSubclass.* values:
--  Axe1H, Axe2H, Sword1H, Sword2H, Mace1H, Mace2H, Polearm, Staff,
--  FistWeapon, Dagger, Warglaive, Bow, Crossbow, Gun, Wand
local WEAPON_OK = {
  WARRIOR = {
    [Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Axe2H]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Sword2H]=true,
    [Enum.ItemWeaponSubclass.Mace1H]=true,[Enum.ItemWeaponSubclass.Mace2H]=true,
    [Enum.ItemWeaponSubclass.Polearm]=true,[Enum.ItemWeaponSubclass.Staff]=true,
    [Enum.ItemWeaponSubclass.Unarmed]=true,[Enum.ItemWeaponSubclass.Dagger]=true,
    [Enum.ItemWeaponSubclass.Bows]=true,[Enum.ItemWeaponSubclass.Crossbow]=true,[Enum.ItemWeaponSubclass.Guns]=true,
    -- no wands, no warglaives
  },
  PALADIN = {
    [Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Axe2H]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Sword2H]=true,
    [Enum.ItemWeaponSubclass.Mace1H]=true,[Enum.ItemWeaponSubclass.Mace2H]=true,
    [Enum.ItemWeaponSubclass.Polearm]=true,
    -- no daggers/fist/staves/ranged/wands/warglaives
  },
  DEATHKNIGHT = {
    [Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Axe2H]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Sword2H]=true,
    [Enum.ItemWeaponSubclass.Mace1H]=true,[Enum.ItemWeaponSubclass.Mace2H]=true,
    [Enum.ItemWeaponSubclass.Polearm]=true,
  },
  HUNTER = {
    [Enum.ItemWeaponSubclass.Bows]=true,[Enum.ItemWeaponSubclass.Crossbow]=true,[Enum.ItemWeaponSubclass.Guns]=true,
    [Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Axe2H]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Sword2H]=true,
    [Enum.ItemWeaponSubclass.Polearm]=true,
    -- conservative: no staves in Retail for hunters
  },
  ROGUE = {
    [Enum.ItemWeaponSubclass.Dagger]=true,[Enum.ItemWeaponSubclass.Unarmed]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Mace1H]=true,[Enum.ItemWeaponSubclass.Axe1H]=true,
    [Enum.ItemWeaponSubclass.Bows]=true,[Enum.ItemWeaponSubclass.Crossbow]=true,[Enum.ItemWeaponSubclass.Guns]=true,
    -- no 2H, no polearm/staff/wand/warglaive
  },
  DEMONHUNTER = {
    [Enum.ItemWeaponSubclass.Warglaive]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Unarmed]=true,
    -- no 2H, no ranged, no maces/polearms/staves/wands
  },
  DRUID = {
    [Enum.ItemWeaponSubclass.Mace1H]=true,[Enum.ItemWeaponSubclass.Mace2H]=true,
    [Enum.ItemWeaponSubclass.Polearm]=true,[Enum.ItemWeaponSubclass.Staff]=true,
    -- (some realms allow daggers/fist historically; keeping conservative)
  },
  MONK = {
    [Enum.ItemWeaponSubclass.Unarmed]=true,[Enum.ItemWeaponSubclass.Polearm]=true,[Enum.ItemWeaponSubclass.Staff]=true,
    [Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Mace1H]=true,
    -- no 2H swords/axes/maces, no ranged, no wands
  },
  SHAMAN = {
    [Enum.ItemWeaponSubclass.Axe1H]=true,[Enum.ItemWeaponSubclass.Axe2H]=true,
    [Enum.ItemWeaponSubclass.Mace1H]=true,[Enum.ItemWeaponSubclass.Mace2H]=true,
    [Enum.ItemWeaponSubclass.Staff]=true,[Enum.ItemWeaponSubclass.Unarmed]=true,[Enum.ItemWeaponSubclass.Dagger]=true,
    -- no swords, no polearm (Retail), no ranged, no wands
  },
  EVOKER = {
    [Enum.ItemWeaponSubclass.Dagger]=true,[Enum.ItemWeaponSubclass.Sword1H]=true,[Enum.ItemWeaponSubclass.Mace1H]=true,
    [Enum.ItemWeaponSubclass.Staff]=true,
    -- no ranged/wands/2H swords/axes/maces, no polearm
  },
  PRIEST = {
    [Enum.ItemWeaponSubclass.Dagger]=true,[Enum.ItemWeaponSubclass.Mace1H]=true,
    [Enum.ItemWeaponSubclass.Staff]=true,[Enum.ItemWeaponSubclass.Wand]=true,
  },
  MAGE = {
    [Enum.ItemWeaponSubclass.Dagger]=true,[Enum.ItemWeaponSubclass.Sword1H]=true,
    [Enum.ItemWeaponSubclass.Staff]=true,[Enum.ItemWeaponSubclass.Wand]=true,
  },
  WARLOCK = {
    [Enum.ItemWeaponSubclass.Dagger]=true,[Enum.ItemWeaponSubclass.Sword1H]=true,
    [Enum.ItemWeaponSubclass.Staff]=true,[Enum.ItemWeaponSubclass.Wand]=true,
  },
}


-- === PUBLIC: can this alt use this item? (armor + stat + level gates) ===
local function canAltUse(link, alt)
  if not alt or not alt.class or not link then return false end

  -- Fast fields
  local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
  if not equipLoc or equipLoc == "" then return false end

  -- Level requirement (cached)
  local _, _, _, _, minLevel = C_Item.GetItemInfo(link)
  if (alt.level or 0) < (minLevel or 0) then return false end

  -- Armor: exact match to class’s max armor (skip flexible slots)
  if not FLEX_EQUIP[equipLoc] and classID == Enum.ItemClass.Armor then
    if subClassID
      and subClassID >= Enum.ItemArmorSubclass.Cloth
      and subClassID <= Enum.ItemArmorSubclass.Plate
    then
      local want = MAX_ARMOR_BY_CLASS[alt.class]
      if not want or subClassID ~= want then
        return false
      end
    end
  end

  -- Primary stat preference (skip flexible slots)
  if not FLEX_EQUIP[equipLoc] then
    local allowed = CLASS_ALLOWED_STATS[alt.class]
    if allowed then
      local stat = primaryStatOf(link)
      if stat and not allowed[stat] then
        return false
      end
    end
  end

    -- Weapon proficiency gating (skip flexible slots; only when item is a weapon)
  if not FLEX_EQUIP[equipLoc] and classID == Enum.ItemClass.Weapon then
    local okSubs = WEAPON_OK[alt.class]
    if not okSubs or not okSubs[subClassID] then
      return false
    end

    -- Optional: hand/slot sanity (block 2H where a class never uses them)
    -- Example: Demon Hunter never uses 2H
    if alt.class == "DEMONHUNTER" then
      if subClassID == Enum.ItemWeaponSubclass.Axe2H
        or subClassID == Enum.ItemWeaponSubclass.Mace2H
        or subClassID == Enum.ItemWeaponSubclass.Sword2H
        or subClassID == Enum.ItemWeaponSubclass.Polearm
        or subClassID == Enum.ItemWeaponSubclass.Staff
      then
        return false
      end
    end
  end

  return true
end

-- === PUBLIC: compute upgrade list for a link ===
local function findAltUpgrades(link)
  local upgrades = {}
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  local slots = equipLocToSlots(equipLoc or "")
  if not slots then return upgrades end

  local itemIlvl = ItemLevelFromLink(link)

  for key, alt in pairs(AltUpDB.chars) do
    if canAltUse(link, alt) then
      local have = worstAltIlvlForSlots(alt, slots)
      local delta = math.floor((itemIlvl or 0) - (have or 0))
      if delta > (MIN_UPGRADE_DELTA or 0) then
        table.insert(upgrades, { key = key, delta = delta })
      end
    end
  end

  table.sort(upgrades, function(a,b) return a.delta > b.delta end)
  return upgrades
end

-- =========================
-- Tooltip hookup (modern)
-- =========================
local function ensureOnHideReset(tt)
  if tt.__altup_hasHideHook then return end
  tt.__altup_hasHideHook = true
  tt:HookScript("OnHide", function(self) self.__altup_lastPrinted = nil end)
end

local function attachTooltip(tt, link)
  if not link or not isTradableEquippable(link) then return end
  local upgrades = findAltUpgrades(link)
  if #upgrades > 0 then
    tt:AddLine(" ")
    tt:AddLine("|cff00ff00Alt Upgrades:|r")
    for i = 1, math.min(#upgrades, 5) do
      local r = upgrades[i]
      tt:AddLine(string.format("• %s: +%d ilvl", r.key, r.delta))
    end
    if #upgrades > 5 then
      tt:AddLine(string.format("…and %d more", #upgrades - 5))
    end
    tt:Show()
  end
end

local function attachTooltipAsync(tt, link)
  local item = Item:CreateFromItemLink(link)
  if item:IsItemEmpty() then return end
  if item:IsItemDataCached() then
    attachTooltip(tt, link)
  else
    item:ContinueOnItemLoad(function() attachTooltip(tt, link) end)
  end
end

local function handleTooltip(tt, link)
  if tt == scanTip then return end -- prevent recursion
  ensureOnHideReset(tt)
  attachTooltipAsync(tt, link)     -- always re-augment (tooltips rebuild a lot)

  -- Optional: debug print once per link
  if ALTUP_DEBUG and (not ALTUP_DEBUG_SHIFT or IsShiftKeyDown()) then
    if tt.__altup_lastPrinted ~= link then
      tt.__altup_lastPrinted = link
      local ok, ups = pcall(findAltUpgrades, link)
      if not ok then
        print("|cffff3333[AltUp error]|r", ups)
      elseif #ups > 0 then
        local buf = {}
        for i = 1, math.min(#ups, 5) do
          local u = ups[i]; buf[#buf+1] = string.format("%s (+%d)", u.key, u.delta)
        end
        print("|cff00ff00[AltUp]|r", link, "→", table.concat(buf, ", "),
          (#ups>5) and ("…+"..(#ups-5)) or "")
      else
        print("|cff00ff00[AltUp]|r", link, "→ No upgrades")
      end
    end
  end
end

local function getLinkFromTooltip(tt, data)
  local _, link = tt.GetItem and tt:GetItem()
  if not link and data then
    link = data.hyperlink or (data.id and ("item:%d"):format(data.id)) or nil
  end
  return link
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
  local link = getLinkFromTooltip(tt, data)
  if link then handleTooltip(tt, link) end
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Hyperlink, function(tt, data)
  if data and data.linkType == "item" and data.hyperlink then
    handleTooltip(tt, data.hyperlink)
  end
end)

-- =========================
-- Events / Slash commands
-- =========================
-- Always rescan on login + safe moments
local function scanEquippedSafe()
  C_Timer.After(0.5, scanEquipped)
  C_Timer.After(2.0, scanEquipped)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    scanEquippedSafe()
  else
    -- debounce quick bursts
    if ev.__pending then return end
    ev.__pending = true
    C_Timer.After(0.25, function() ev.__pending = false; scanEquipped() end)
  end
end)

-- /altup → manual rescan
SLASH_ALTUP1 = "/altup"
SlashCmdList.ALTUP = function()
  scanEquipped()
  print("|cff00ff00AltUpgrades:|r snapshot refreshed for", getPlayerKey())
end

-- /altupdebug (or /altupdebug shift)
SLASH_ALTUPDEBUG1 = "/altupdebug"
SlashCmdList.ALTUPDEBUG = function(msg)
  if msg and msg:lower():find("shift") then
    ALTUP_DEBUG_SHIFT = not ALTUP_DEBUG_SHIFT
    print("|cff00ff00AltUpgrades:|r SHIFT gating", ALTUP_DEBUG_SHIFT and "ON" or "OFF")
  else
    ALTUP_DEBUG = not ALTUP_DEBUG
    print("|cff00ff00AltUpgrades:|r debug", ALTUP_DEBUG and "ON" or "OFF", ALTUP_DEBUG_SHIFT and "(Shift-gated)" or "")
  end
end

-- /altupreset → reset DB (keep minimap defaults)
SLASH_ALTUPRESET1 = "/altupreset"
SlashCmdList.ALTUPRESET = function()
  AltUpDB = { chars = {}, minimap = { angle = 45, hide = false } }
  print("|cff00ff00AltUpgrades:|r DB reset. Re-run /altup on each alt.")
end

-- Banner
local g = CreateFrame("Frame")
g:RegisterEvent("PLAYER_LOGIN")
g:SetScript("OnEvent", function()
  print("|cff00ff00AltUpgrades loaded.|r")
end)

-- =========================
-- Export minimal API for UI.lua
-- =========================
_G.AltUp_API = {
  findAltUpgrades       = findAltUpgrades,      -- function(link) -> { {key, delta}, ... }
  isTradableEquippable  = isTradableEquippable, -- function(link) -> boolean
  itemLevelFromLink     = ItemLevelFromLink,    -- function(link) -> number
}
