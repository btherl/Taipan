# Guide: Rendering Combat Ships in the Apple II Interface

This guide describes how to implement the 2-row ship grid for the combat screen, as seen in the original Apple II version of Taipan! (Reference: `references/Reference_Screenshots/Combat.png`).

## 1. Grid Specifications
-   **Rows**: 2 rows of ships.
-   **Columns**: Up to 5 ships per row.
-   **Ship Width**: 7 characters.
-   **Ship Height**: 5 characters.
-   **Horizontal Spacing**: 1 character between ships.
-   **Vertical Spacing**: 1 row between ship rows.
-   **Total Width**: 39 characters (5 ships * 7 wide + 4 spaces * 1 wide).
-   **Total Height**: 11 rows (2 rows * 5 high + 1 row space).
-   **Over 10 ships**: A "+" shows in column 40, row 10, if there are more than 10 ships in battle.

## 2. Option A: Authentic Font-Based Approach
In the original game, ships were composed of specialized characters found in the `TaipanThickFont`. This approach is the most faithful to the 1982 version.

### Implementation Logic
1.  **Character Map**: Identify the character IDs in `TaipanThickFont.png` for each part of the ship (masts, sails, hull).
2.  **Row Generation**: In `PromptEngine.sceneCombatLayout`, you would build the ship rows (Rows 5–15 of the lower section) by iterating through the `state.combat.grid`.
3.  **Example Row Builder**:
    ```lua
    local function getShipChar(part, frame)
       -- Returns the character ID for a specific ship part
    end

    local function buildShipLine(rowIdx, shipsState)
      local line = " " -- 1-char left margin
      for i = 1, 5 do
        if shipsState[i] then
          line = line .. "CHAR_CHAR_CHAR_CHAR_CHAR_CHAR_CHAR" -- 7 chars for ship part
        else
          line = line .. "       " -- 7 spaces
        end
        line = line .. " " -- 1 horizontal space
      end
      return line
    end
    ```

## 3. Option B: Large Sprite Approach
This approach treats each ship as a single graphical object while still utilizing the `ReplicatedStorage.Text` bitmap font library. This is easier to animate (e.g., for sinking or hits).

### Implementation Logic
1.  **Define Sprite**: Store the ship's character layout as a multi-line string.
    ```lua
    local SHIP_SPRITE = {
      "  | |  ",
      " ##### ",
      " ##### ",
      "#######",
      " ##### "
    }
    ```
2.  **Use TextSprite**: Utilize the `TextSprite` class from the `BoxDrawing` module (or a similar wrapper) to position each ship independently on the screen.
3.  **Coordinate Calculation**:
    -   **Base X**: 14 (pixel pitch) * Scale * ColumnOffset
    -   **Base Y**: 16 (pixel pitch) * Scale * RowOffset

## 4. Positioning in PromptEngine
The ships should typically occupy the center of the terminal. If using the standard 24-row layout:
-   **Status Screen**: Rows 1–4 (In-combat condensed version).
-   **Narration**: Rows 17–24. (Used when throwing cargo, not used for most messages)
-   **Ships**: Rows 5–15.

## 5. Performance Considerations
-   **Static Rendering**: If the ships don't move, pre-calculating the text rows in `PromptEngine` is the most token-efficient method.
-   **Animation**: If you want to add sinking animations (tilting/lowering), the Sprite-based approach is required as it allows per-instance `Position` and `Rotation` updates in the `GlitchLayer`.
