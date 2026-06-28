# Design — "Restart" (abandon ship) option at Hong Kong

**Date:** 2026-06-28
**Status:** Approved (brainstorming) — pending implementation plan
**Interface:** Apple II terminal only

## Problem

The original Apple II Taipan! had no in-game reset; players power-cycled the
machine to start over. In Roblox there is no power cycle, so the only current
path back to a fresh game is: travel to a port → choose **Quit trading** →
game-over → answer the restart prompt. That is several steps and routes through
the plain game-over screen. We want a faithful, low-friction "start over" that a
player (and the developer, when testing the firm-name screen) can reach directly.

The reset *destination* already exists: the score screen (`sceneFinalStatus`)
ends with **"Play again? Y/N"**, where **Y** calls `restartGame()` and returns to
the firm-name lobby. This feature only adds a new way to *reach* that loop.

## Feature summary

Add a **Restart** ("abandon ship") option to the Hong Kong port menu. It occupies
the same slot that **Retire** later uses and shares the **R** key. Choosing it
asks for confirmation, then ends the game with a custom "failure" message and
shows the normal score screen, which already loops back to the firm-name screen.

## Behaviour

### 1. Port menu placement (client — `sceneAtPort`)

At Hong Kong (`currentPort == HONG_KONG`):

- **Net worth < $1,000,000** (not retire-eligible): the menu's final option reads
  `cargo, Quit trading, or Restart?`. Key **R** = Restart.
- **Net worth ≥ $1,000,000** (retire-eligible): unchanged from today —
  `cargo, Quit trading, or Retire?`. Key **R** = Retire.

Retire and Restart are **mutually exclusive** (gated by retire-eligibility) and
share the **R** key and the same screen slot. They are never displayed together.

Non-Hong-Kong ports are unchanged: `Shall I Buy, Sell, or Quit trading?` — no
Restart. (To restart from elsewhere, the player travels to Hong Kong, or uses the
existing Quit. A new game always starts at Hong Kong, so firm-name testing is
unaffected.)

### 2. Confirmation (client — new scene)

Pressing **R** when *Restart* is shown opens a confirmation:

> `Do you wish to abandon your ship, Taipan? (Y/N)`

- **N** → return to the Hong Kong port menu (no state change).
- **Y** → fire the new `AbandonShip` remote to the server.

### 3. Abandon → score (server + client)

- **Server** — new `AbandonShip` handler:
  - Guard: state is a table, `not state.gameOver`, and `currentPort == HONG_KONG`
    (mirrors the Retire handler's guards). No wealth check is required, because
    the client only offers Restart when not retire-eligible.
  - Calls `setGameOver(state, "abandoned")` — the existing helper that sets
    `gameOver`, `gameOverReason`, and computes `finalScore`/`finalRating` exactly
    as quit/retire/sunk do.
  - `pushState(player)`.
- **Client** — `processState` routes `gameOverReason == "abandoned"`:
  - First show a brief message scene: `Ashamed of your failure, you disappear
    into the night, never to be seen again.`
  - Then advance to the existing **score screen** (`sceneFinalStatus`).
  - This mirrors the existing "retired" routing (`localScene == "final_status"`
    → `sceneFinalStatus`, else the intro scene). The message scene advances to
    `final_status` on any key press (an `anyKey` prompt, like `sceneGameOver`).

### 4. Reset loop (reuse — no new code)

`sceneFinalStatus` already ends with **"Play again? Y/N"**:
- **Y** → `restartGame()` → firm-name lobby (the `RestartGame` remote pushes the
  lobby state and clears the player slot).
- **N** → `quitGame()`.

The abandon flow plugs into this unchanged, closing the loop back to the
firm-name screen.

## Components touched

| Layer | File | Change |
|---|---|---|
| Remotes | `sync/ReplicatedStorage/Remotes.luau` | Add `AbandonShip` RemoteEvent |
| Server | `sync/ServerScriptService/GameService.server.luau` | Add `AbandonShip.OnServerEvent` handler → `setGameOver(state, "abandoned")` |
| Client actions | `.../GameController/GameActions.luau` | Add `abandonShip = function() Remotes.AbandonShip:FireServer() end` |
| Client prompt | `.../Apple2/PromptEngine.luau` | (a) `sceneAtPort`: add Restart to HK non-retire branch (text, `validKeys`, `onKey`); (b) new `sceneRestartConfirm`; (c) new abandon message scene; (d) `processState` route for `"abandoned"` |

`sourcemap.json` must register the new `AbandonShip` RemoteEvent instance (all
remotes are declared there, per the Remotes convention).

## Data flow

```
HK port menu (R, not retire-eligible)
  → sceneRestartConfirm  (Y/N)
      N → back to port menu
      Y → actions.abandonShip() → Remotes.AbandonShip:FireServer()
              → server setGameOver(state,"abandoned") → pushState
              → client processState("abandoned")
                  → abandon message scene ("Ashamed of your failure…")
                  → sceneFinalStatus (score + "Play again?")
                      Y → restartGame() → firm-name lobby
                      N → quitGame()
```

## Edge cases & decisions

- **Key reuse (R):** Accepted. Restart and Retire never coexist, so one key and
  one slot serve both; the visible label always tells the player which action R
  performs.
- **HK-only:** Accepted as a deliberate, minor divergence from "available
  everywhere." Quit remains available at all ports.
- **Cargo/overload:** No overload guard for Restart (unlike Quit's departure
  guard). The player is abandoning, not departing, so hold state is irrelevant.
- **Persistence:** Identical to existing endgame flows. `setGameOver` does not
  itself save; the player slot is cleared on `restartGame` and the next new game
  overwrites the save on its first departure. No new persistence logic.
- **Message-before-score mechanism:** Use an intermediate scene that advances
  into `sceneFinalStatus`, not a floating notification — consistent with the
  terminal aesthetic and the existing `sceneGameOver`/`final_status` pattern.

## Testing

- **Pure logic:** `setGameOver(state, "abandoned")` reuses an existing, already
  tested helper; a small assertion can confirm `gameOverReason == "abandoned"`
  and that score/rating are populated. (Server handler wiring itself is not
  unit-testable — TestEZ covers `shared/` only.)
- **On-device / MCP playtest:** Verify at Hong Kong with net worth < $1M the menu
  shows "or Restart?"; with ≥ $1M it shows "or Retire?"; confirm Y/N branches;
  confirm the abandon message → score screen → "Play again?" → firm-name loop.
- Touch-UI specifics (keypad) are not involved; Restart is a single-char prompt.

## Out of scope

- Restart at non-Hong-Kong ports.
- Any change to Quit, Retire, or the score screen's existing content.
- A separate developer-only/hidden reset (this is a player-facing feature).
