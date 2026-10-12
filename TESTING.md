# How to test Quest Planner

This is a WoW Forever addon. It cannot be verified in a browser. Load it in the Forever client.

## Install

1. Fully quit World of Warcraft Forever (not only `/reload` the first time you add the folder).
2. Copy the **`quest_planner`** folder into the Forever AddOns directory:

   `World of Warcraft\_classic_beta_\Interface\AddOns\quest_planner\`

   The folder name must match the TOC file name: `quest_planner.toc` sits directly inside `quest_planner`, not in another nested folder.

   Find that path from the Battle.net app: select **World of Warcraft Forever** → gear next to Play → **Show in Explorer**.
3. Start the client.
4. On the character-select screen, click **AddOns**, enable **Quest Planner**, and confirm **Load out of date AddOns** is on if the list marks it out of date.
5. Log in.

If the addon does not appear, the folder is nested (AddOns/quest_planner/quest_planner/...) or the TOC name does not match the folder.

## Open it

In chat, type:

```
/qp
```

If another addon already owns `/qp`, the login message will tell you to use:

```
/questplanner
```

You can also open it from the minimap addon compartment (the small addon menu).

Useful extra commands:

```
/qp debug
/qp help
```

## What you should see

- A movable window titled **Quest Planner**
- Level filters: **All**, **My level**, **+/- 1**, **+/- 2**, **Custom**
- Two groups when you have data:
  - **Pinned plan** (checked quests, in the order you checked them)
  - **Closest useful** (unchecked, nearest first among quests whose XP still fills the current level)
- Each row: checkbox, name, level, distance (yards + N/NE/E/...), XP
- Centered XP meter under the filters: selected XP / XP remaining to next level
- Bottom status: pin count, nearby count

## Checklist

Do these in order on a character that can still level (not 60).

1. **Load**  
   After login you should see a gold `[Quest Planner]` chat line with the slash command that bound. Type `/qp`. The window opens. Type it again. The window closes. Esc also closes it.

2. **Empty / thin log**  
   If you have no quests and the map shows no nearby quest starts, the status line says nothing matches. That is expected.

3. **Pick up quests**  
   Accept 3+ quests in a starter zone. `/qp` should list them. Distances should be numbers when the client exposes a map pin or waypoint. Walk toward one: its yard count should drop within about a second.

4. **Pin / unpin**  
   Check a quest that is not the closest. It jumps to **Pinned plan**. Check a second. It sits under the first (check order). Uncheck the first. It leaves the plan, and **Closest useful** re-ranks so the next nearest useful quest occupies the top of that group.

5. **Level filter**  
   Click **My level**. Only that quest level remains. Click **+/- 2**, then **All**. Checked quests stay checked when they reappear. Click **Custom**, type a min and max, press Enter on either box.

6. **XP meter**  
   Check quests and watch the bar under the filters fill. The label is `selected / needed XP`. If pinned XP is more than remaining, the bar is full and the label adds `(N XP OverQuest)`. `/qp debug` prints whether `GetQuestLogRewardXP` exists; if it does not, XP may read as unknown until you accept the quest.

7. **Reload persistence**  
   Pin two quests, `/reload`, open `/qp`. Those two should still be pinned for this character.

8. **Turn-in**  
   Turn in a pinned quest. It should disappear from the list.

## Debug

```
/qp debug
```

You want:

- toc around **16001**
- `C_QuestLog: true`
- `GetQuestsOnMap: true` (needed for distance and available quests on the map)
- `GetNextWaypoint: true` (needed for the next objective point)
- `Remaining XP` a number, not nil (nil means the client hid XP as a secret value; distance ranking still works)

Lua errors: Esc → Options → Search **lua error**, or install a bug-grabber if you use one. `/console scriptErrors 1` then `/reload` also surfaces errors.

## Known limits on this version

- It plans from your **quest log** plus **quest POIs on the current zone map** (including available `!` starts the map already knows). It does not ship a full world quest database, so it will not list every quest in Azeroth from nowhere.
- Distance is `?? yd` when Forever has not given a map pin or waypoint for that quest.
- Available (not yet accepted) quests often show **XP once accepted** until they are in the log.
- Forever’s API can move between beta builds. If the window never opens, run `/qp debug` and check `scriptErrors`.
