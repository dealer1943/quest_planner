# Quest Planner (WoW Forever)

Addon for **WoW Forever** that ranks nearby quests by how useful they are for the next level-up, then lets the player pin the ones they actually want to run.

## Goal

Open a planner window, see the closest quests whose XP still counts toward leveling, and keep a short, ordered list of the ones you have checked. Unchecked quests fall below the checked ones. When a checked quest is unchecked, the next closest eligible quest slides into that slot.

## Slash command

- Command: `/qp`
- Action: toggle the Quest Planner window
- If `/qp` is already taken on the client, fall back to `/questplanner` and print a one-line chat notice with the command that bound

## Window

The window is a scrollable list of quest rows. Each row shows:

- Checkbox (checked = pinned to the plan)
- Quest name
- Quest level
- Distance from the player (yards, and a short direction if available)
- XP the quest awards

Centered level filters sit above the list. Below the filters, a centered XP meter fills as pinned quests are checked. The number under the bar is selected XP over XP remaining to the next level. Excess selected XP is shown as `(# XP OverQuest)`.

## Ranking rules

1. **Eligible first.** Only quests whose XP still contributes to the current level-up are ranked as “useful.” Quest XP that would be wasted after ding can still appear, but it sorts below quests that fill the remaining XP bar.
2. **Closest useful next.** Among eligible quests, sort by distance, nearest first.
3. **Checked stay on top.** Checked quests are the plan. They are bumped to the top of the list, keeping their relative order.
4. **Unchecked sit below.** Unchecked quests stay in the list under the checked group, still sorted by the same closest-useful ranking.
5. **Uncheck fills the gap.** When the player unchecks a quest, it leaves the checked group. The next closest eligible unchecked quest slides up into that visual slot in the unchecked ranking. The player must check a quest for it to remain in the pinned plan.
6. **Level filter.** If a level filter is set, quests outside that range are hidden from both groups until the filter is cleared or changed.

## Check behavior

- A quest stays in the **plan** (top group) only while it is checked.
- Checking a quest immediately moves it into the checked group.
- Unchecking a quest immediately moves it into the unchecked group and lets the next closest eligible quest occupy the vacated rank.
- The plan is local to the character and is restored when the window is reopened.

## Distance

Distance is live player-to-quest (or player-to-quest-giver / objective point, whichever the server data supports). The list refreshes on movement and on quest log changes so the “next closest” row stays honest.

## Level filter

The player can:

- Show all eligible quests
- Filter to a level band (min and max quest level)
- Optionally snap the band to “my level” or “my level ± N”

Changing the filter re-ranks both groups without clearing existing checks. A checked quest that no longer matches the filter is hidden until the filter includes it again; it stays checked.

## Non-goals (for this version)

- Auto-accepting or auto-turning-in quests
- Quest path drawing on the world map
- Group or raid sharing of the plan
- Quest data for other realms or expansions

## Target platform

- Client: WoW Forever (addon API as exposed by that client)
- Language: Lua
- UI: XML frames + Lua
- Load: standard `.toc` addon in `quest_planner/`

## File layout

```
quest_planner/
  PROJECT.md
  TESTING.md
  quest_planner.toc     ← folder name must match this file
  QuestPlanner.lua
  QuestPlanner.xml
```

Install by copying `quest_planner` into `World of Warcraft\_classic_beta_\Interface\AddOns\`. See TESTING.md.

## Implementation notes

- Client: WoW Forever, TOC interface **16001**, Mainline-style `C_QuestLog` / `C_Map` APIs.
- Slash: `/qp` if free at `PLAYER_LOGIN`, otherwise `/questplanner`.
- Sources: quest log entries, plus `C_QuestLog.GetQuestsOnMap` POIs on the current zone (in-progress and available starts).
- Distance: `C_QuestLog.GetNextWaypoint` first, then map POI, converted with `C_Map.GetWorldPosFromMapPos`.
- XP: `UnitXP` / `UnitXPMax` for the remaining bar (skipped if secret); `GetQuestLogRewardXP` for log quests.
- Pins: `SavedVariablesPerCharacter` (`QuestPlannerCharDB.checked`), restored per character.
- The list refreshes on quest/xp/zone events and on a short ticker while the window is open.
