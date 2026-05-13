# Plan: Add Sound Effects to All Game Events

## Current State

- `sync/ReplicatedStorage/SoundPlayer.luau` — plays a sound from `Sounds[name]`, creates a temporary `Sound` instance in `SoundService`, destroys after playback
- `sync/ReplicatedStorage/Sounds.luau` — lookup table with 3 entries:
  - `badjoss` → rbxassetid://104274433675831
  - `goodjoss` → rbxassetid://137526731122451
  - `underattack` → rbxassetid://114808924899061
- Only `underattack` is wired up (to combat encounter notifications in `GameService.server.luau:243,262`)
- Sound is triggered from `Apple2Interface.luau:208-209` when a notification entry has `.sound` set

## Sound Pipeline

```
GameService (server)
  └─ sets entry.sound = "soundName" on pendingMessages entries
      └─ pushState sends to client via StateUpdate
          └─ Apple2Interface.playNextNotif() checks entry.sound
              └─ SoundPlayer.play(entry.sound)
                  └─ Looks up rbxassetid in Sounds.luau
                      └─ Creates Sound, plays, destroys
```

## Mapping (README categories → code locations)

### badjoss (danger/loss events)

| README line | Game event | Code location | Already wired? |
|---|---|---|---|
| li yuen has sent a lieutenant | Li Yuen warning on arrival (non-HK) | `GameService:281-285` | No |
| li yuen's pirates! (attacking) | Li Yuen combat encounter | `GameService:259-265` | underattack |
| killed a bad guy (?) | Player was sunk (game over) | `GameService:672-674` | No |
| sunk X of 'em | Player fired and sunk enemies | `GameService:720-722, 731` | No |
| X ran away | Some enemies fled during fight | `GameService:729-731` | No |
| storm taipan! | Storm encounter begins | `GameService:342, 358, 365, 378, 385, 634, 646, 654` | No |
| we made it! (after a storm) | Survived storm | `GameService:365, 385, 654` | No |
| wu bailout (very well, good joss) | Wu emergency loan (bailout) | `GameService: (sceneWuBankruptcy in PromptEngine)` | No |
| trying to enter an empty firm name | Firm name screen (client-side) | `PromptEngine.luau:466-492` | No — local scene, no entry.sound |
| we got 'em all! | All enemies sunk (combat victory) | `GameService:736-739` | No |
| let's hope we lose 'em! | Threw cargo to escape | `GameService:844-845` | No |
| X ran away (duplicate) | (same as above) | | |
| sunk X of the buggers | (same as sunk X of 'em) | | |
| they let us be | Li Yuen fleet lets player pass | `GameService:249-253` | No |

### goodjoss (success/positive events)

| README line | Game event | Code location | Already wired? |
|---|---|---|---|
| captured some booty | Combat victory booty | `GameService:736-739` | No |
| we made it! (after combat) | Escaped combat | `GameService:780-782, 851-853` | No |
| got away in combat | (same as above) | | |
| you're already here! | Trying to travel to current port | `PromptEngine.luau:444` | No — local scene, no entry.sound |
| price has risen (dropped) | Crash/boom price event on arrival | `GameService:291-294` | No |
| there's nothing there (throwing cargo) | Throw cargo with no cargo | `GameService:835-836` | No |
| ship overloaded | Depart blocked overloaded | `GameService:214-215` | No (Notify text only) |
| you have only X in cash (Wu/bank) | Insufficient cash for repay/deposit | `PromptEngine.luau:1025, 1244, 1257` | No — local scenes |
| you have only X in the bank | Insufficient bank for withdraw | `PromptEngine.luau:1257` | No — local scene |
| warehouse will only hold an additional | Warehouse capacity limit | `PromptEngine.luau` (warehouse error scenes) | No — local scene |
| warehouse is full | Warehouse capacity limit | `PromptEngine.luau` | No — local scene |
| won't loan you so much | Exceeded borrow limit | `PromptEngine.luau:1010` | No — local scene |
| you have no cargo | No cargo to transfer | `PromptEngine.luau:1291` | No — local scene |

### underattack (combat/danger events)

| README line | Game event | Code location | Already wired? |
|---|---|---|---|
| X hostile ships approaching | Generic pirate encounter | `GameService:240-243` | Yes — underattack |
| hit in combat | Player ship hit | `GameService:668-669` | No |
| beaten & robbed | Cash robbery event | `GameService:391-396` | No |
| bodyguards killed | Wu enforcers take cash | `GameService:494-496` | No (Notify only) |
| very well, the game is over (wu bailout) | Game over from bankruptcy decline | `GameService:1016-1023` | No |
| buggers hit a gun | Enemy destroyed a gun | `GameService:665-666` | No |
| we've been hit | (same as hit in combat) | | |
| what shall we do? | Combat round prompt | `Apple2Interface.luau:292` | No — local scene text |
| we're going down (storm) | Storm sinking ship | `GameService:342, 634` | No |
| X ships of li yuen's pirate fleet | Li Yuen combat encounter | `GameService:259-265` | Yes — underattack (same as generic pirate) |
| X hostile ships approaching | (same as generic pirate) | | |

## Plan

### Phase 1: New sound ID assets
Get Roblox sound asset IDs for new categories. Current structure has one monolithic sound per category. Consider:

- Keep the 3 existing categories (badjoss, goodjoss, underattack) as general-purpose sounds
- OR split into more specific categories (e.g., combat_hit, storm, booty, wu_bailout, escape, overloaded, crash_boom)

Recommendation: **split into 2-3 more categories** for better differentiation, but keep it manageable.

Suggested new entries for `Sounds.luau`:
```lua
return {
    badjoss     = "rbxassetid://104274433675831",  -- existing
    goodjoss    = "rbxassetid://137526731122451",  -- existing
    underattack = "rbxassetid://114808924899061",  -- existing
    storm       = "rbxassetid://___",              -- NEW: storm events
    victory     = "rbxassetid://___",              -- NEW: combat victory/booty
    escape      = "rbxassetid://___",              -- NEW: escaped combat
    error       = "rbxassetid://___",              -- NEW: validation errors
    gameOver    = "rbxassetid://___",              -- NEW: game over
    hit         = "rbxassetid://___",              -- NEW: hit in combat
}
```

(Asset IDs need to be uploaded to Roblox and filled in.)

### Phase 2: Wire sounds to server notifications (GameService.server.luau)

For each notification entry created with `makeCaptainNotif`, `makeCompradorNotif`, `makeCombatNotif`, or `makeStatusScreenLowerNotif`, add `entry.sound = "<category>"`:

| Code location | Event | Sound category |
|---|---|---|
| `GameService:249-253` (Li Yuen lets pass) | `goodjoss` |
| `GameService:281-285` (Li Yuen warning) | `badjoss` |
| `GameService:291-294` (price event) | `goodjoss` |
| `GameService:342` (storm going down) | `storm` |
| `GameService:358` (storm blown off course) | `storm` |
| `GameService:365` (storm survived) | `storm` |
| `GameService:378` (storm blown off course) | `storm` |
| `GameService:385` (storm survived) | `storm` |
| `GameService:391-396` (robbery) | `badjoss` |
| `GameService:634` (post-combat storm going down) | `storm` |
| `GameService:646` (post-combat storm blown off course) | `storm` |
| `GameService:654` (post-combat storm survived) | `storm` |
| `GameService:665-666` (buggers hit a gun) | `hit` |
| `GameService:668-669` (we've been hit) | `hit` |
| `GameService:672-674` (sunk game over) | `gameOver` |
| `GameService:679` (Li Yuen intervened) | `goodjoss` |
| `GameService:698` (no guns) | `badjoss` |
| `GameService:718` (got 'em all) | `victory` |
| `GameService:720-722` (sunk X buggers) | `victory` |
| `GameService:725` (hit no sink) | `hit` |
| `GameService:729-731` (X ran away) | `escape` |
| `GameService:736-739` (captured booty) | `victory` |
| `GameService:780` (got away) | `escape` |
| `GameService:781-783` (we made it) | `escape` |
| `GameService:793` (can't lose 'em) | `underattack` |
| `GameService:798-799` (partial escape) | `escape` |
| `GameService:835-836` (nothing there) | `error` |
| `GameService:844-845` (let's hope we lose 'em) | `badjoss` |
| `GameService:851` (got away after throw) | `escape` |
| `GameService:852-854` (we made it after throw) | `escape` |
| `GameService:864` (can't lose 'em after throw) | `underattack` |
| `GameService:869-870` (partial escape after throw) | `escape` |

### Phase 3: Wire sounds to local scenes (PromptEngine.luau)

Local scenes don't go through `entry.sound`/`playNextNotif`. They play when the player interacts locally without server notifications. Options:
1. **Extend PromptEngine** to return a sound name alongside scene lines and promptDef
2. **Add a separate sound mechanism** in Apple2Interface that detects specific local scenes and plays sounds
3. **Minimal approach**: Only wire sounds for server-driven notifications; skip local scenes

Recommendation: **Option 3 (minimal)** for v1. The local scenes (validation errors, firm name, etc.) are fast UI transitions where a sound adds less value. File as a future enhancement.

| Local scene | Event | Suggested sound | Recommendation |
|---|---|---|---|
| `sceneFirmName` empty input | Empty firm name | badjoss | Skip for v1 |
| `sceneBuyOverloadErr` | Overloaded | error | Skip for v1 |
| `sceneWuBorrowErr` | Won't loan | error | Skip for v1 |
| `sceneWuRepayErr` | Only X cash | error | Skip for v1 |
| `"You're already here"` | Same port travel | error | Skip for v1 |
| Warehouse errors | Capacity/no cargo | error | Skip for v1 |

### Phase 4: Extend SoundPlayer (optional enhancement)

Current `SoundPlayer.luau` is simple and functional. Consider:
- Adding volume control via `entry.soundVolume` field on notifications
- Adding pitch variation for variety on repeated sounds
- Optional non-blocking async play (currently blocks via `while not done` loop — this is fine since it runs in `task.spawn`)

### Phase 5: Testing

1. **Manual playtesting via MCP**: Trigger each event type and verify the correct sound plays
2. **No unit test needed** for Sounds.luau (static data)
3. **Consider a SoundPlayer spec** that verifies `play("unknown")` calls `warn` without error

## Implementation Order

1. Upload sound assets to Roblox and update `Sounds.luau` with real asset IDs
2. Wire server notification sounds in `GameService.server.luau` (Phase 2 — highest impact, ~30 lines changed)
3. Manual playtesting of combat flow (entry, fight, hit, victory, escape, storm)
4. Manual playtesting of travel flow (Li Yuen, price events, robbery, storm)
5. Manual playtesting of Wu/bankruptcy/game-over events
6. File local scene sounds as future enhancement (PromptEngine.luau)
