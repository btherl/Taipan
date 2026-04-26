# Taipan! Gemini Mandates

This document defines the foundational engineering standards and workflows for the Taipan! Roblox project. Adherence to these rules is mandatory.

Also read CLAUDE.md too, in this folder and in every folder under `sync`

## 1. Core Principles

- **Server-Authoritative Logic:** ALL game state mutations MUST occur within `sync/ServerScriptService/GameService.server.luau`. The client (`StarterGui`) is a "dumb" view that only receives state snapshots and sends action requests.
- **Engine Purity:** Logic modules in `sync/ReplicatedStorage/shared/` (Engines) MUST remain pure. They should not call `game:GetService()`, create Instances, or yield. They take a state table and return a mutated table or a value.
- **BASIC Fidelity:** This is a port of the 1982 Apple II version. Formulas and logic should match the original BASIC source (annotated in `references/BASIC_ANNOTATED.md`). Always cite the BASIC line number in code comments when implementing/fixing logic.
- **Surgical Updates:** When modifying code, maintain the existing style (naming, formatting, typing). Ensure all changes are idiomatically complete and follow the established "Panel" and "Engine" patterns.

## 2. Technical Standards

- **Language:** Luau (Roblox's version of Lua). Use type annotations where appropriate for clarity.
- **Randomness:** Use the `fnR(x)` helper pattern in Engine modules to replicate BASIC's `INT(RND(1)*X)` behavior accurately.
- **State Management:**
    - Always use the `pushState(player)` pattern after any server-side mutation.
    - Respect the "Sentinel Pattern" for async DataStore loading to prevent race conditions.
- **UI/UX:**
    - **Palette:** Amber (`200,180,80`), Green (`140,200,80`), Red (`220,80,80`), Orange (`220,120,60`).
    - **Typography:** Always use `Enum.Font.RobotoMono` for the terminal aesthetic.
    - **Accessibility:** Interactive buttons must be at least 44px in height.

## 3. Critical Workflows

### Synchronization (Azul)
- This project uses **Azul** for syncing. `sourcemap.json` is the source of truth for mapping local files to Roblox instances.
- Never manually edit `sourcemap.json` unless adding new files that Azul doesn't auto-detect.

### Testing & Validation
- **Logic Tests:** Every change to a shared Engine MUST be accompanied by an update to its corresponding `.spec.luau` file in `sync/ServerScriptService/Tests/`.
- **Running Tests:** Run the project in **Run Mode** in Roblox Studio. `TestRunner.server.luau` will execute all tests via TestEZ.
- **Validation Mandate:** A task is not complete until behavioral correctness is verified via automated tests.

### Implementation Cycle
1. **Research:** Identify the relevant BASIC line numbers and existing Engine logic.
2. **Strategy:** Plan the mutation on the server and the corresponding UI update on the client.
3. **Execution:** Apply surgical changes to Engines, `GameService`, and/or Panels.
4. **Validation:** Run TestEZ suite and perform a manual "Play" test in Studio if UI was changed.

## 4. Key File Map

- `sync/ServerScriptService/GameService.server.luau`: The heart of the game.
- `sync/ReplicatedStorage/shared/`: Core logic (Combat, Finance, Price, etc.).
- `sync/StarterGui/TaipanGui/`: UI Panels and Client Controller.
- `sync/ReplicatedStorage/Remotes.luau`: Networking definitions.
- `references/BASIC_ANNOTATED.md`: The logic source of truth.

## 5. Prohibited Actions

- **NO 3D World:** Taipan is strictly 2D. Do not add Parts, Scripts, or logic that assumes a 3D environment.
- **NO Client-Side Mutation:** Never attempt to calculate "new" state on the client to "predict" the server.
- **NO Bypass:** Never bypass `Validators.luau` when performing purchases, sales, or transfers.
