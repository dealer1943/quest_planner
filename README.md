# Quest Planner

Addon for **WoW Forever** that ranks nearby quests by distance and by XP that still counts toward your next level. Pin the ones you want to run; unchecked quests stay below the pinned plan.

## Open it

```
/qp
```

If `/qp` is already taken, the addon binds `/questplanner` and tells you in chat.

## Install

1. Fully quit World of Warcraft Forever.
2. Copy this folder into:

   `World of Warcraft\_classic_beta_\Interface\AddOns\quest_planner\`

   The folder name must match `quest_planner.toc`. Do not nest an extra `quest_planner` folder inside it.
3. Start the client, enable **Quest Planner** on the AddOns screen, and log in.

See [TESTING.md](TESTING.md) for a full in-game checklist.

## What it does

- Lists quests from your log plus current-zone map POIs (including available starts)
- Sorts useful XP (fills the remaining bar to next level) nearest-first
- Check a quest to pin it to the top of the plan; uncheck to drop it and let the next closest slide up
- Level filters: All, my level, ±1, ±2, custom band
- XP meter: selected quest XP vs XP remaining to next level, with `(# XP OverQuest)` when you overshoot
- Character-saved pins (`QuestPlannerCharDB`)

## Slash commands

| Command | Action |
| --- | --- |
| `/qp` | Toggle the planner window |
| `/qp debug` | Print diagnostic info |
| `/qp help` | Show commands |

Also opens from the minimap addon compartment.

## Files

```
quest_planner/
  quest_planner.toc
  QuestPlanner.lua
  QuestPlanner.xml
  README.md
  PROJECT.md
  TESTING.md
```

Interface: `16001` (WoW Forever / Camelot).
