-- functions.lua
local ADDON = ...
local FN = {}

-- simple test function
function FN.ping()
  return "pong"
end

-- expose globally so core/ui can see it
_G.AltUp_Fn = FN

print("|cff00ff00AltUpgrades:|r functions.lua loaded")
