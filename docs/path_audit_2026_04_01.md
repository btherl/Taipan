# Taipan Path Audit — 2026-04-01

## Summary

The audit compares every `.lua` file under `D:\Dev\Taipan\src\` and `D:\Dev\Taipan\tests\` against
the live Roblox Studio game tree, using the Rojo mapping in `default.project.json`.

**Overall health**: The vast majority of scripts match correctly. There are three categories of
discrepancy:

1. **Naming mismatch (cosmetic, not functional)** — `init.client.lua` becomes a LocalScript named
   `GameController` in Studio instead of the expected name. All child modules are therefore nested
   under `GameController` in Studio, which is correct Rojo behaviour but differs from the local path.
2. **Orphaned Studio objects** — two objects exist in Studio with no local counterpart and were
   presumably injected manually or left over from an earlier session.
3. **Local file with no Studio counterpart** — one local font folder (`November`) is absent from
   Studio.

---

## Rojo `init.lua` / `init.client.lua` Naming Convention

When Rojo sees a folder containing an `init.client.lua`, it creates a **LocalScript** whose name
is the **folder name**, and all sibling files in that folder become children of that script.

Local folder: `src/StarterGui/TaipanGui/`
Contains: `init.client.lua`
Rojo output: `StarterGui.TaipanGui` (ScreenGui) → child LocalScript named `TaipanGui`.

However, Studio shows the LocalScript as **`GameController`**, not `TaipanGui`. This means Studio
was last synced when the folder or script had a different name, or the script was renamed inside
Studio without a corresponding rename on disk. The LocalScript and all its children are functionally
correct — the name discrepancy is cosmetic but could cause confusion when navigating the tree.

---

## Full Script Comparison Table

### A. ServerScriptService

| Local Path | Expected Studio Path | Actual Studio Path | Match? |
|---|---|---|---|
| `src/ServerScriptService/GameService.server.lua` | `ServerScriptService.GameService` | `ServerScriptService.GameService` (Script) | YES |

### B. ServerScriptService.Tests (from `tests/`)

| Local Path | Expected Studio Path | Actual Studio Path | Match? |
|---|---|---|---|
| `tests/TestRunner.server.lua` | `ServerScriptService.Tests.TestRunner` | `ServerScriptService.Tests.TestRunner` (Script) | YES |
| `tests/Constants.spec.lua` | `ServerScriptService.Tests.Constants.spec` | `ServerScriptService.Tests.Constants.spec` | YES |
| `tests/GameState.spec.lua` | `ServerScriptService.Tests.GameState.spec` | `ServerScriptService.Tests.GameState.spec` | YES |
| `tests/PriceEngine.spec.lua` | `ServerScriptService.Tests.PriceEngine.spec` | `ServerScriptService.Tests.PriceEngine.spec` | YES |
| `tests/Validators.spec.lua` | `ServerScriptService.Tests.Validators.spec` | `ServerScriptService.Tests.Validators.spec` | YES |
| `tests/TravelEngine.spec.lua` | `ServerScriptService.Tests.TravelEngine.spec` | `ServerScriptService.Tests.TravelEngine.spec` | YES |
| `tests/FinanceEngine.spec.lua` | `ServerScriptService.Tests.FinanceEngine.spec` | `ServerScriptService.Tests.FinanceEngine.spec` | YES |
| `tests/EventEngine.spec.lua` | `ServerScriptService.Tests.EventEngine.spec` | `ServerScriptService.Tests.EventEngine.spec` | YES |
| `tests/CombatEngine.spec.lua` | `ServerScriptService.Tests.CombatEngine.spec` | `ServerScriptService.Tests.CombatEngine.spec` | YES |
| `tests/ProgressionEngine.spec.lua` | `ServerScriptService.Tests.ProgressionEngine.spec` | `ServerScriptService.Tests.ProgressionEngine.spec` | YES |
| `tests/PersistenceEngine.spec.lua` | `ServerScriptService.Tests.PersistenceEngine.spec` | `ServerScriptService.Tests.PersistenceEngine.spec` | YES |
| `tests/BoxDrawing.spec.lua` | `ServerScriptService.Tests.BoxDrawing.spec` | `ServerScriptService.Tests.BoxDrawing.spec` | YES |

### C. ReplicatedStorage

| Local Path | Expected Studio Path | Actual Studio Path | Match? |
|---|---|---|---|
| `src/ReplicatedStorage/Remotes.lua` | `ReplicatedStorage.Remotes` | `ReplicatedStorage.Remotes` | YES |
| `src/ReplicatedStorage/TestEZ.lua` | `ReplicatedStorage.TestEZ` | `ReplicatedStorage.TestEZ` | YES |
| `src/ReplicatedStorage/Text/init.lua` | `ReplicatedStorage.Text` (ModuleScript) | `ReplicatedStorage.Text` (ModuleScript) | YES |
| `src/ReplicatedStorage/Text/BoxDrawing.lua` | `ReplicatedStorage.Text.BoxDrawing` | `ReplicatedStorage.Text.BoxDrawing` | YES |
| `src/ReplicatedStorage/Text/lib/Signal.lua` | `ReplicatedStorage.Text.lib.Signal` | `ReplicatedStorage.Text.lib.Signal` | YES |
| `src/ReplicatedStorage/Text/lib/TextSprite.lua` | `ReplicatedStorage.Text.lib.TextSprite` | `ReplicatedStorage.Text.lib.TextSprite` | YES |
| `src/ReplicatedStorage/Text/lib/Unicode.lua` | `ReplicatedStorage.Text.lib.Unicode` | `ReplicatedStorage.Text.lib.Unicode` | YES |
| `src/ReplicatedStorage/Text/lib/Util.lua` | `ReplicatedStorage.Text.lib.Util` | `ReplicatedStorage.Text.lib.Util` | YES |
| `src/ReplicatedStorage/Text/lib/XMLParser.lua` | `ReplicatedStorage.Text.lib.XMLParser` | `ReplicatedStorage.Text.lib.XMLParser` | YES |
| `src/ReplicatedStorage/Text/Fonts/TaipanStandardFont/FontData.lua` | `ReplicatedStorage.Text.Fonts.TaipanStandardFont.FontData` | `ReplicatedStorage.Text.Fonts.TaipanStandardFont.FontData` | YES |
| `src/ReplicatedStorage/Text/Fonts/TaipanThickFont/FontData.lua` | `ReplicatedStorage.Text.Fonts.TaipanThickFont.FontData` | `ReplicatedStorage.Text.Fonts.TaipanThickFont.FontData` | YES |
| `src/ReplicatedStorage/Text/Fonts/November/FontData.lua` | `ReplicatedStorage.Text.Fonts.November.FontData` | **NOT FOUND** | **NO** |
| `src/ReplicatedStorage/shared/Constants.lua` | `ReplicatedStorage.shared.Constants` | `ReplicatedStorage.shared.Constants` | YES |
| `src/ReplicatedStorage/shared/GameState.lua` | `ReplicatedStorage.shared.GameState` | `ReplicatedStorage.shared.GameState` | YES |
| `src/ReplicatedStorage/shared/PriceEngine.lua` | `ReplicatedStorage.shared.PriceEngine` | `ReplicatedStorage.shared.PriceEngine` | YES |
| `src/ReplicatedStorage/shared/Validators.lua` | `ReplicatedStorage.shared.Validators` | `ReplicatedStorage.shared.Validators` | YES |
| `src/ReplicatedStorage/shared/TravelEngine.lua` | `ReplicatedStorage.shared.TravelEngine` | `ReplicatedStorage.shared.TravelEngine` | YES |
| `src/ReplicatedStorage/shared/FinanceEngine.lua` | `ReplicatedStorage.shared.FinanceEngine` | `ReplicatedStorage.shared.FinanceEngine` | YES |
| `src/ReplicatedStorage/shared/EventEngine.lua` | `ReplicatedStorage.shared.EventEngine` | `ReplicatedStorage.shared.EventEngine` | YES |
| `src/ReplicatedStorage/shared/CombatEngine.lua` | `ReplicatedStorage.shared.CombatEngine` | `ReplicatedStorage.shared.CombatEngine` | YES |
| `src/ReplicatedStorage/shared/ProgressionEngine.lua` | `ReplicatedStorage.shared.ProgressionEngine` | `ReplicatedStorage.shared.ProgressionEngine` | YES |
| `src/ReplicatedStorage/shared/PersistenceEngine.lua` | `ReplicatedStorage.shared.PersistenceEngine` | `ReplicatedStorage.shared.PersistenceEngine` | YES |

### D. StarterGui.TaipanGui (from `src/StarterGui/TaipanGui/`)

The folder contains `init.client.lua`, so Rojo maps the **folder** to a LocalScript.
Studio shows this LocalScript as `GameController` (see discrepancy D1 below).
All sibling modules are children of that LocalScript in Studio.

| Local Path | Expected Studio Path | Actual Studio Path | Match? |
|---|---|---|---|
| `src/StarterGui/TaipanGui/init.client.lua` | `StarterGui.TaipanGui` (LocalScript, folder-named) | `StarterGui.TaipanGui.GameController` (LocalScript) | **NAME MISMATCH** (D1) |
| `src/StarterGui/TaipanGui/GameActions.lua` | `StarterGui.TaipanGui.GameController.GameActions` | `StarterGui.TaipanGui.GameController.GameActions` | YES (under GameController) |
| `src/StarterGui/TaipanGui/ModernInterface.lua` | `StarterGui.TaipanGui.GameController.ModernInterface` | `StarterGui.TaipanGui.GameController.ModernInterface` | YES |
| `src/StarterGui/TaipanGui/InterfacePicker.lua` | `StarterGui.TaipanGui.GameController.InterfacePicker` | `StarterGui.TaipanGui.GameController.InterfacePicker` | YES |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | `StarterGui.TaipanGui.GameController.Apple2Interface` | `StarterGui.TaipanGui.GameController.Apple2Interface` | YES |
| `src/StarterGui/TaipanGui/Panels/StartPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.StartPanel` | `StarterGui.TaipanGui.GameController.Panels.StartPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/PortPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.PortPanel` | `StarterGui.TaipanGui.GameController.Panels.PortPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/StatusStrip.lua` | `StarterGui.TaipanGui.GameController.Panels.StatusStrip` | `StarterGui.TaipanGui.GameController.Panels.StatusStrip` | YES |
| `src/StarterGui/TaipanGui/Panels/InventoryPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.InventoryPanel` | `StarterGui.TaipanGui.GameController.Panels.InventoryPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/PricesPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.PricesPanel` | `StarterGui.TaipanGui.GameController.Panels.PricesPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/BuySellPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.BuySellPanel` | `StarterGui.TaipanGui.GameController.Panels.BuySellPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/WarehousePanel.lua` | `StarterGui.TaipanGui.GameController.Panels.WarehousePanel` | `StarterGui.TaipanGui.GameController.Panels.WarehousePanel` | YES |
| `src/StarterGui/TaipanGui/Panels/WuPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.WuPanel` | `StarterGui.TaipanGui.GameController.Panels.WuPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/BankPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.BankPanel` | `StarterGui.TaipanGui.GameController.Panels.BankPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/MessagePanel.lua` | `StarterGui.TaipanGui.GameController.Panels.MessagePanel` | `StarterGui.TaipanGui.GameController.Panels.MessagePanel` | YES |
| `src/StarterGui/TaipanGui/Panels/ShipPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.ShipPanel` | `StarterGui.TaipanGui.GameController.Panels.ShipPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/CombatPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.CombatPanel` | `StarterGui.TaipanGui.GameController.Panels.CombatPanel` | YES |
| `src/StarterGui/TaipanGui/Panels/GameOverPanel.lua` | `StarterGui.TaipanGui.GameController.Panels.GameOverPanel` | `StarterGui.TaipanGui.GameController.Panels.GameOverPanel` | YES |
| `src/StarterGui/TaipanGui/Apple2/Terminal.lua` | `StarterGui.TaipanGui.GameController.Apple2.Terminal` | `StarterGui.TaipanGui.GameController.Apple2.Terminal` | YES |
| `src/StarterGui/TaipanGui/Apple2/KeyInput.lua` | `StarterGui.TaipanGui.GameController.Apple2.KeyInput` | `StarterGui.TaipanGui.GameController.Apple2.KeyInput` | YES |
| `src/StarterGui/TaipanGui/Apple2/GlitchLayer.lua` | `StarterGui.TaipanGui.GameController.Apple2.GlitchLayer` | `StarterGui.TaipanGui.GameController.Apple2.GlitchLayer` | YES |
| `src/StarterGui/TaipanGui/Apple2/PromptEngine.lua` | `StarterGui.TaipanGui.GameController.Apple2.PromptEngine` | `StarterGui.TaipanGui.GameController.Apple2.PromptEngine` | YES |

---

## Discrepancy Detail

### D1 — LocalScript name: `GameController` vs expected folder name

- **Local path**: `src/StarterGui/TaipanGui/init.client.lua`
- **Expected Studio path** (per Rojo convention): The LocalScript should be named after the
  ScreenGui's folder, which is `TaipanGui`. Because `TaipanGui` itself is the ScreenGui, Rojo
  actually creates the LocalScript as a **child** of the ScreenGui named after nothing — it uses
  the `$path` folder name. The folder is `TaipanGui`, so under Rojo the `init.client.lua` becomes
  the ScreenGui itself (class LocalScript would be wrong here). In practice Rojo maps a folder with
  `init.client.lua` to a LocalScript whose instance name equals the folder name.
- **Actual Studio path**: `StarterGui.TaipanGui.GameController` (LocalScript)
- **Severity**: Cosmetic only. The script body and all children are correct. The name `GameController`
  inside the ScreenGui does not affect any `require()` calls because modules are referenced by
  `script.Parent` chains, not by hardcoded names.
- **Cause**: The LocalScript was manually renamed inside Studio (or was named differently when the
  place file was originally created), and the rename was never reflected on disk. Rojo would re-sync
  this as whatever the folder is named — but since the folder itself IS the ScreenGui mapping root,
  the child LocalScript's name comes from Studio state, not disk.

### D2 — Orphaned Studio object: `StarterGui.TaipanGui.Apple2` (Folder) at top level

- **Studio path**: `StarterGui.TaipanGui.Apple2` (Folder) — direct child of TaipanGui ScreenGui
  - Contains: `StarterGui.TaipanGui.Apple2.PromptEngine` (Folder, empty or stale)
- **Local counterpart**: None. The real Apple2 modules live under `GameController.Apple2` (which
  is correctly synced from `src/StarterGui/TaipanGui/Apple2/`).
- **Severity**: Medium. This orphaned Folder/object does not affect gameplay (it's not required by
  any script) but is clutter that could confuse future audits.
- **Cause**: A previous manual injection or old Rojo sync left this artifact. It was not cleaned up.

### D3 — Orphaned Studio object: `StarterGui.TaipanGui.GameActions` (duplicate)

- **Studio path**: `StarterGui.TaipanGui.GameActions` (ModuleScript) — direct child of TaipanGui ScreenGui
- **Also exists at**: `StarterGui.TaipanGui.GameController.GameActions` (the correct location)
- **Local path**: `src/StarterGui/TaipanGui/GameActions.lua` (maps to the `GameController` child)
- **Severity**: Low-medium. The duplicate at the top level is unreferenced by the game (all
  `require()` calls from `init.client.lua` use `script.GameActions`, which resolves to the child
  under `GameController`). But it may cause confusion or hold stale code.
- **Cause**: Likely a manual MCP injection at the wrong path at some earlier point.

### D4 — Local file missing from Studio: `November` font

- **Local path**: `src/ReplicatedStorage/Text/Fonts/November/FontData.lua`
- **Expected Studio path**: `ReplicatedStorage.Text.Fonts.November.FontData`
- **Actual Studio path**: Not present. Studio only has `TaipanStandardFont` and `TaipanThickFont`.
- **Severity**: Low (if November font is unused) to High (if any script requires it).
- **Cause**: The `November` folder exists locally but was never injected into Studio. It may be
  legacy/unused data left from an earlier phase, or it may be needed once the custom-font phase
  (Phase 8) is complete.

### D5 — Studio object with no local counterpart: `ReplicatedStorage.FontDemo`

- **Studio path**: `ReplicatedStorage.FontDemo` (ModuleScript)
- **Local path**: None found under `src/ReplicatedStorage/`
- **Severity**: Low. Likely a development scratch module injected during Phase 8 font work.
- **Cause**: Manual MCP injection that was never persisted to disk.

---

## Scripts in Studio But Missing Locally (Summary)

| Studio Path | Class | Notes |
|---|---|---|
| `StarterGui.TaipanGui.Apple2` | Folder | Orphaned — see D2 |
| `StarterGui.TaipanGui.Apple2.PromptEngine` | Folder | Orphaned child of D2 |
| `StarterGui.TaipanGui.GameActions` | ModuleScript | Duplicate — see D3 |
| `ReplicatedStorage.FontDemo` | ModuleScript | Dev scratch — see D5 |
| `ReplicatedStorage.Text.Fonts.TaipanStandardFont.ImageID` | StringValue | Non-script value, expected (image asset ID for the font atlas); no `.lua` needed |
| `ReplicatedStorage.Text.Fonts.TaipanThickFont.ImageID` | StringValue | Same as above |

## Scripts Local But Missing from Studio (Summary)

| Local Path | Expected Studio Path | Notes |
|---|---|---|
| `src/ReplicatedStorage/Text/Fonts/November/FontData.lua` | `ReplicatedStorage.Text.Fonts.November.FontData` | Not injected — see D4 |

---

## Resolution Plan

| Discrepancy | Action Required |
|---|---|
| **D1** — `GameController` name mismatch | No action needed for functionality. Optionally rename the LocalScript in Studio to match expectations, or accept the cosmetic difference. No `default.project.json` change needed. |
| **D2** — Orphaned `TaipanGui.Apple2` folder | Delete `StarterGui.TaipanGui.Apple2` (and its `PromptEngine` child) from Studio via MCP or Studio UI. No disk change needed. |
| **D3** — Duplicate `TaipanGui.GameActions` | Delete `StarterGui.TaipanGui.GameActions` (the top-level duplicate) from Studio. The correct copy at `GameController.GameActions` stays. No disk change needed. |
| **D4** — `November` font missing from Studio | Either: (a) inject `November/FontData.lua` into Studio if Phase 8 needs it, or (b) delete `src/ReplicatedStorage/Text/Fonts/November/` locally if it is legacy/unused. Determine first whether any script references `Text.Fonts.November`. |
| **D5** — `FontDemo` in Studio only | Either: (a) save the content to `src/ReplicatedStorage/FontDemo.lua` on disk so git tracks it, or (b) delete it from Studio if it is a throwaway. |

---

## Notes on `default.project.json`

The current `default.project.json` is correct for the intended mapping. No changes to it are
required to resolve any of the discrepancies above. All issues are Studio-side artifacts or
missing MCP injections, not Rojo configuration errors.
