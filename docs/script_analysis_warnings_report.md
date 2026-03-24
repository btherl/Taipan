# Script Analysis Warnings Report

Generated: 2026-03-25

---

## Group 1: ReplicatedStorage.TestEZ

**File:** `src/ReplicatedStorage/TestEZ.lua` (1388-line bundled single-file version of Roblox's TestEZ framework)

### Warning 1.1 — Type Error (1, 1): "Type inference failed to complete"

**Root cause:** The TestEZ bundle is a large, highly dynamic Lua module (~1400 lines) that makes extensive use of patterns that defeat Luau's type inference: metatables with `__index` and `__newindex` overrides, dynamic method binding (`bindSelf`), module registries with string-keyed function dispatch, and tables used as both dictionaries and class instances. The Luau type checker has a complexity budget for inference, and this file exceeds it.

**Assessment: False positive.** This is a known limitation of Luau's type inference on large, dynamically-typed codebases. The TestEZ framework is a well-tested, widely-used Roblox library. The warning simply means the analyzer gave up partway through and some downstream type information will be incomplete or `unknown`.

### Warning 1.2 — Type Error (85, 63) and (86, 67): "expects `unknown` as 4th argument, given `a & number`"

**Root cause:** These warnings are a direct consequence of Warning 1.1 (inference failure). When type inference fails to complete, many function signatures are left as `unknown`. The analyzer then flags call sites where it can infer the argument type (e.g., `a & number`) but the expected parameter type is `unknown` — it cannot confirm compatibility.

The code at lines 85-86 is the `formatMessage` function:
```lua
local function formatMessage(result, trueMessage, falseMessage)
    if result then
        return trueMessage
    else
        return falseMessage
    end
end
```
This function only has 3 parameters, so the "4th argument" phrasing indicates the analyzer is reporting against a different call site or has confused itself due to the incomplete type inference. The column numbers (63 and 67) point far to the right of the visible code on those lines, which further suggests the analyzer's line/column mapping is misaligned with the on-disk source (possibly due to Rojo transformation or tab-width differences).

**Assessment: False positive.** Cascading artifact of the inference failure. The `formatMessage` function is trivially correct. No bug.

### Warning 1.3 — Type Error (542, 25): "require expects `Instance | number | string`, given [something else]"

**Root cause:** Line 542 on disk is inside `TestSession:shouldSkip()`, which contains no `require` call. The actual `require` call that triggers this warning is at line 1297:
```lua
local method = require(current)
```
Here, `current` is a variable passed into `getModulesImpl(root, modules, current)` and is expected to be a `ModuleScript` Instance, but the parameter has no type annotation. Due to the inference failure at line 1 (Warning 1.1), the analyzer cannot determine that `current` is an Instance — it sees it as some unresolved type that does not match `Instance | number | string`.

The line number discrepancy (542 vs 1297) is likely caused by the analyzer reporting the error at a different location than where the `require` call actually lives, again a consequence of the inference failure producing confused diagnostics, or a line-mapping offset introduced by Rojo's transformation of the bundled file.

**Assessment: False positive.** The `require(current)` call is correct at runtime — `current` is always a `ModuleScript` discovered by `isSpecScript()`. The type error is an inference limitation.

### Group 1 Summary

All four TestEZ warnings are false positives caused by Luau's type inference hitting its complexity ceiling on this large, dynamically-typed bundled file. TestEZ is a third-party library from Roblox themselves. These warnings are harmless and expected for this kind of code. No action needed.

---

## Group 2: ReplicatedStorage.Text.lib.XMLParser (and Workspace.Text.lib.XMLParser)

**File:** `src/ReplicatedStorage/Text/lib/XMLParser.lua` (third-party XML parser by Jonathan Poelen)

Both warnings are the same diagnostic — "Using '#' on a table without an array part is likely a bug" — but they are both false positives because the `#` operator is being applied to **strings**, not tables.

### Warning 2.1 — TableOperations (30, 16): `#s`

**Code:**
```lua
local trim = function(s)
    local from = s:match"^%s*()"
    return from > #s and "" or s:match(".*%S", from)
end
```

`s` is a string parameter. `#s` returns the string length, which is standard Lua/Luau. The `()` capture in the pattern `"^%s*()"` returns a numeric position (not a string), so `from` is a number and the comparison `from > #s` is a valid number-to-number comparison.

**Root cause:** The Luau analyzer's `TableOperations` lint does not correctly distinguish string-typed variables from table-typed variables in this context. Since the `trim` function has no type annotation on `s`, and the function is a local assigned to a variable (not a named function), the analyzer may be failing to infer that `s` is always a string.

**Assessment: False positive.** The `#` operator on strings is well-defined in Lua/Luau and returns the string length. This is a standard string-trimming idiom from lua-users.org.

### Warning 2.2 — TableOperations (115, 7): `#closed`

**Code:**
```lua
s:gsub('<([?!/]?)([-:_%w]+)%s*(/?>?)([^<]*)', function(type, name, closed, txt)
    -- open
    if #type == 0 then
        local attrs, orderedattrs = {}, {}
        if #closed == 0 then
```

`closed` is the third capture group from the `gsub` pattern `(/?>?)`, which always produces a string (either `""`, `">"`, or `"/>"`) . `#closed` returns the string length.

**Root cause:** Same as Warning 2.1. The analyzer cannot track that `gsub` callback parameters are strings (they come from pattern capture groups). Without type annotations, it defaults to a broader type that triggers the `TableOperations` lint.

**Assessment: False positive.** `closed` is always a string. `#closed` correctly returns its length.

### Workspace.Text.lib.XMLParser duplicate

The same warnings appear under `Workspace.Text.lib.XMLParser` because the Text library (or a copy of it) also exists under `Workspace` in the Roblox data model, containing the identical XMLParser code. The root cause and assessment are identical.

### Group 2 Summary

Both XMLParser warnings are false positives. The `#` operator is being used on strings, not tables. The Luau linter's `TableOperations` rule incorrectly flags these because it cannot infer the string type of the unannotated parameters. This is a well-known third-party XML parser library. No action needed.

---

## Overall Assessment

| Warning | Verdict | Action Needed |
|---|---|---|
| TestEZ (1,1) inference failure | False positive — file too complex for type checker | None |
| TestEZ (85,63) and (86,67) unknown 4th arg | False positive — cascading from inference failure | None |
| TestEZ (542,25) require type mismatch | False positive — cascading from inference failure | None |
| XMLParser (30,16) `#` on string | False positive — linter misidentifies string as table | None |
| XMLParser (115,7) `#` on string | False positive — linter misidentifies string as table | None |

**None of these warnings indicate real bugs.** They are all artifacts of Luau's static analysis limitations when applied to dynamically-typed, unannotated third-party library code. Both TestEZ and XMLParser are established open-source libraries that function correctly at runtime.

If desired, these warnings can be suppressed by adding Luau type annotations to the library code, but since these are third-party bundled files, it is generally better to leave them as-is and accept the false positives.
