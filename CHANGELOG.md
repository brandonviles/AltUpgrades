## v0.4.0
- Please EXPECT BUGS! I am listening to the community! Hope to Keep Up
- New: Blizzard-style tabs to switch views:
  - Upgrades for Me
  - Upgrades for Alts
- Work in Progress: Minimap button now sits on the minimap edge and is draggable; position is saved. Works fine with/without collectors.
- New: Account “item vault” saves tradable items by character; the Upgrade for Me tab shows owner + ilvl gain.
- Fix: Tooltip hooks stabilized; chat and bag paths deduped to avoid duplicates/flicker.
- Fix: Safer DB initialization and bag scanning (includes reagent bag); no more nil errors on fresh installs.
- UI: Cleaned list layout per tab, clearer status texts, and small styling tweaks.



##  v0.2.1
Changelog:

Fixed: Updated interface version to correct version


## v0.2.0
Changelog:

New: Added full weapon proficiency checks per class so you’ll never see upgrades for weapons your alts can’t equip.
Improved: Prevents plate gear from showing as upgrades for cloth wearers (and vice-versa).
Improved: Includes proper Retail enum mapping for all weapon types, fixing “fist weapon” detection.
Fixed: Alts missing class data will now update correctly on login for accurate upgrade checks.
Fixed: Tooltip suggestions now respect both armor type and weapon proficiency for each alt.

Notes:

Weapon restrictions are conservative for Retail and can be loosened in future updates if needed.
If you see something show as an upgrade that shouldn’t be, please note the item and class and report it!

---------------------------------------------------------------------------------------------------------------------

