# Items for rps_prompt_exstras

| Item | Module | Used for |
|---|---|---|
| `mri_scan` | MRI | Given to the MRI operator after a scan. **Using it reopens the MRI report sheet.** |
| `mugshot_photo` | Mugshot | Given to the officer who took the mugshot. **Using it shows the photo.** |
| `bodycam` | Tech | Given by MRPD Body Cam Shelf 1 |
| `dash_cam` | Tech | Given by MRPD Body Cam Shelf 2 |
| `drone` | Tech | Given by the MRPD Drone Wall |

`mri_scan` and `mugshot_photo` store their data in the item's metadata: the report id, or the photo URL. Use is registered through `rps_lib` (`CreateUseableItem`, reading `GetInventory`), so it works with every inventory rps_lib supports. If a player has several films or photos, a list opens to pick one.

## Install for your inventory

| Inventory | File | Paste into | Images go to |
|---|---|---|---|
| tgiann-inventory | `tgiann-inventory.lua` | `items/items.lua` → inside `itemsData = { }` | tgiann's item image folder |
| ox_inventory (ESX / Qbox) | `ox_inventory.lua` | `data/items.lua` → inside the returned table | `ox_inventory/web/images/` |
| qb / ps / lj-inventory | `qb-core_shared_items.lua` | `qb-core/shared/items.lua` → inside `QBShared.Items` | the inventory's `html/images/` |
| ESX with a DB item list | `esx_items.sql` | run it on your database | — |

Icons for the two new items are in `images/` (`mri_scan.png`, `mugshot_photo.png`).
`bodycam`, `dash_cam` and `drone` already exist in tgiann's default item list, so only add them if yours doesn't have them.

Restart the inventory resource after adding the items, then restart `rps_prompt_exstras`.
