# Guide: Adding New Scenes to the Apple II Interface

This guide explains how to add new dialog-driven scenes to the Taipan! Apple II terminal interface. All Apple II UI logic is centralized in `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`.

## 1. Scene Architecture
The `PromptEngine` is a pure logic module. It does not create Roblox instances or call services. Instead, it takes the current game `state` and a `localScene` identifier and returns:
1.  **Display Data**: A table of rows (1–24) to be rendered by the terminal.
2.  **Prompt Definition**: A configuration table describing how the terminal should handle user input.

## 2. Creating a Scene Function
Most scenes use `buildPortRows(state)` to generate the standard status display (Rows 1–16) and then define custom content for the "Comprador's Report" area (Rows 17–24).

### Basic Template
```lua
local function sceneMyNewDialog(state, actions, localSceneCb)
  local rows = buildPortRows(state) -- Standard top-half
  
  rows[17] = { text = "Comprador's Report",          color = AMBER }
  rows[18] = { text = "",                            color = AMBER }
  rows[19] = { text = "Taipan, a strange traveler",  color = GREEN }
  rows[20] = { text = "approaches you. Will you",    color = GREEN }
  local prompt_base = "speak with him? "
  rows[21] = { text = prompt_base,                   color = GREEN }
  
  local promptDef = {
    type           = "singlechar",
    keys           = {"Y", "N"},
    _inputRow      = 21,
    _buildInputRow = function(s) return { text = prompt_base .. s, color = GREEN } end,
    onKey = function(key, _state, _actions)
      if key == "Y" then
        -- Trigger a server action or a local transition
        if localSceneCb then localSceneCb("my_new_dialog_step2") end
      else
        -- Clear the local scene to return to the main menu
        if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
  
  return { rows = rows }, promptDef
end
```

## 3. Input Types (`promptDef.type`)
Choose the input type that matches your dialog's needs:

| Type | Interaction | Example Use |
| :--- | :--- | :--- |
| `key` | Immediate action on any key or specific key. | "Press any key to continue" |
| `singlechar` | Type one character, then Enter to confirm. | [Y/N] prompts, Menu selections |
| `numeric` | Digits only, left-arrow deletes. | Entering cash/cargo amounts |
| `type` | Free text entry, Enter to confirm. | Naming your Firm |

## 4. Registering the Scene
All scenes must be registered in `PromptEngine.processState`. This function is evaluated from top to bottom; the first matching condition determines which scene is rendered.

To add a scene that appears *before* the main port menu, place it above the final `return sceneAtPort(...)`.

### Example Routing
```lua
function PromptEngine.processState(state, localScene, actions, localSceneCb)
  -- ... (priority scenes like GameOver, Combat, etc.)

  -- 1. Server-driven trigger (e.g., a flag set by the server)
  if state.myCustomEventPending then
    return sceneMyNewDialog(state, actions, localSceneCb)
  end

  -- 2. Local-driven trigger (client-side state machine)
  if localScene == "my_new_dialog_step2" then
    return sceneMyNextStep(state, actions, localSceneCb)
  end

  -- ...
  return sceneAtPort(state, actions, localSceneCb)
end
```

## 5. Transitioning Between Scenes
There are two ways to move from your new scene:

### Local Transitions (Client-Only)
Use `localSceneCb("next_scene_name")`. This causes an immediate re-render with the new scene name. The server is not involved.
*   **Use for**: Multi-step menus or "Press any key" informational messages.

### Server Transitions (State-Driven)
Call a function in the `actions` table (e.g., `actions.buyGoods(...)`). This sends a RemoteEvent to the server. The server will update the game state and send a `StateUpdate` back, which triggers a full re-render.
*   **Use for**: Any action that modifies cash, cargo, time, or permanent flags.
