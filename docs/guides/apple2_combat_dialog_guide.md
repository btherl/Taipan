# Guide: Combat Dialog in the Apple II Interface

This guide describes how combat narration and dialog are implemented in the Apple II interface. Combat in Taipan! uses a sequential narration system to mimic the pacing of the original 1982 game.

## 1. The Narration Pipeline (`pendingMessages`)
Unlike static menus, combat dialog is dynamic and multi-step. It uses the `pendingMessages` system to queue "beats" of narration on the server and play them back on the client.

1.  **Server (Logic)**: When a player takes an action (Fight, Run, Throw), the server calculates the results and builds an array of notification entries.
2.  **Server (Remote)**: These entries are attached to `state.pendingMessages` in the `StateUpdate` sent to the client.
3.  **Client (Playback)**: The `Apple2Interface.luau` detects these messages, puts them in a queue, and displays them one-by-one in the terminal's report area (Rows 17–24).

## 2. Server-Side: Building Narration
In `GameService.server.luau`, use the `makeCaptainNotif(lines, duration)` helper to create narration beats.

### Example: Fight Narration
```lua
-- Inside CombatFight handler
local pending = {}
table.insert(pending, makeCaptainNotif({ "Aye, we'll fight 'em, Taipan!" }, 1))
table.insert(pending, makeCaptainNotif({ "We're firing on 'em, Taipan!" }, 1))

if result.sunk > 0 then
    table.insert(pending, makeCaptainNotif({ "Sunk 1 of the buggers, Taipan!" }, 2))
end

state.pendingMessages = pending
pushState(player)
```

## 3. Client-Side: Playback Logic
The `Apple2Interface.luau` manages the notification queue. While notifications are playing:
-   The main scene rendering is **paused**.
-   Rows 17–24 are overwritten by the notification text.
-   The user can press **any key** to skip the current beat.
-   If no key is pressed, the beat auto-advances after its `duration` expires.

Once the queue is empty, the terminal renders the current combat state via `PromptEngine.sceneCombatLayout`.

## 4. The Combat Layout (`PromptEngine.luau`)
The "static" combat screen is defined in `sceneCombatLayout`. It populates:
-   **Rows 1–16**: Standard status screen (via `buildPortRows`).
-   **Rows 17–19**: Combat header (Ship counts and Gun counts).
-   **Row 20**: Seaworthiness (Prime, Fair, etc.).
-   **Row 21**: The ship grid (e.g., `[###.......]`).

This layout is what the player sees while waiting to input their next command (Fight, Run, or Throw).

## 5. Action Chaining
Some combat actions automatically trigger follow-up logic on the server:
-   **Throw Cargo**: After cargo is removed, the server automatically executes a **Run** attempt. The narration will include both the "Cargo thrown!" message and the "We got away!" (or "Can't lose 'em!") message in a single sequence.
-   **Enemy Fire**: If enemies remain after the player's action, the `applyEnemyFire` helper is called to append "We've been hit!" messages to the current narration queue.

## 6. Key Files for Combat Dialog
-   `sync/ServerScriptService/GameService.server.luau`: Handles combat actions and builds the `pendingMessages` array.
-   `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau`: Manages the playback and timing of notifications.
-   `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`: Defines the visual layout of the combat screen and the command menu.
