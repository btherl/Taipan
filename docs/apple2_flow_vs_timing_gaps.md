# Apple II Flow vs Delay Timing — Discrepancies

Comparing `apple2_prompt_engine_flow.md` against `apple2-delay-timing.md`.
Items present in the timing doc but absent or incomplete in the flow doc.

---

## 1. Wu Braves Escort Scenes (GOSUB 92) — Completely missing

The two longest-delay events in the original game have no corresponding scenes in PromptEngine:

- "Wu sends braves to escort you to his mansion" (BASIC line 1230)
- "You arrive at the Wu mansion" (BASIC line 1240)

These are driven by the `wuWarningGiven` flag. The flow doc covers Wu only as a
financial dialog (question → repay → borrow). It is unclear whether the braves
confrontation is implemented as a dedicated PromptEngine scene or delivered as
a `pendingMessages` notification.

---

## 2. Notification Content — Acknowledged but never enumerated

The flow doc notes that events arrive via `pendingMessages` but does not catalog
the ~20 specific events named in the timing doc:

| Category | Events not documented |
|---|---|
| Combat | Hostile ships approaching; "Aye, we'll run!"; successfully escaped; booty captured; Li Yuen's fleet drove them off; "We made it!" (victory) |
| Sea events | Opium seized by authorities; Li Yuen territory random event; price rise announcement; beaten up and robbed (cash > 25k); cutthroat robbery (debt > 20k) |
| Storm | Storm encountered; "I think we're going down!!"; "We made it!!" (survived); blown off course |
| Pirate encounter | Li Yuen's pirates spotted; pirates let you go (allied); Li Yuen's fleet attacks |
| Wu / finance | "Good joss!!" (loan approved); port arrival with interest/debt tick |

---

## 3. Wu Repay — Insufficient Funds — Missing error scene

The timing doc lists "Insufficient funds to repay Wu" as a GOSUB 94 (medium
delay) event. `sceneWuRepay` in the flow doc has no validation — it calls
`actions.wuRepay(amt)` for any `amt > 0` without checking against `state.cash`.
There is no `wu_repay_err` scene documented.

---

## 4. Buy — Hold Space Overflow — Missing error path

The timing doc lists "Ship overburden / overloaded" as a GOSUB 94 event. The
flow doc's buy path only checks `qty * price > cash`. There is no client-side
guard for exceeding hold space and no error scene for that condition. The
original showed an error message with a pause before re-asking.

---

## 5. Bank Confirmations — Missing notifications

The timing doc lists "Bank deposit confirmation" and "Bank withdrawal
confirmation" as GOSUB 94 (medium delay) events. The flow doc shows both
silently advancing to the next scene (`bank_withdraw` or `nil`) with no
confirmation message or delay documented.
