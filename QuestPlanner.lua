local addonName, ns = ...

ns.MAX_LEVEL = 60
ns.ROW_HEIGHT = 48
ns.REFRESH_INTERVAL = 0.7

local xpCache = {}
local locCache = {}
local rowPool = {}
local headerPool = {}
local filterButtons = {}
local ticker
local pendingRefresh
local uiReady

local FILTERS = {
	{ key = "all", label = "All" },
	{ key = "mylevel", label = "My level" },
	{ key = "plus1", label = "+/- 1" },
	{ key = "plus2", label = "+/- 2" },
	{ key = "custom", label = "Custom" },
}

local CARDINALS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function Print(msg)
	print("|cffd4a85a[Quest Planner]|r " .. tostring(msg))
end

local function SafeNumber(value)
	if value == nil then
		return nil
	end
	if type(issecretvalue) == "function" and issecretvalue(value) then
		return nil
	end
	if type(value) ~= "number" then
		return nil
	end
	return value
end

local function SafeString(value)
	if value == nil then
		return nil
	end
	if type(issecretvalue) == "function" and issecretvalue(value) then
		return nil
	end
	return tostring(value)
end

local function Defaults()
	if type(QuestPlannerCharDB) ~= "table" then
		QuestPlannerCharDB = {}
	end
	ns.db = QuestPlannerCharDB
	if type(ns.db.checked) ~= "table" then
		ns.db.checked = {}
	end
	if not ns.db.filterMode then
		ns.db.filterMode = "all"
	end
	if type(ns.db.filterMin) ~= "number" then
		ns.db.filterMin = 1
	end
	if type(ns.db.filterMax) ~= "number" then
		ns.db.filterMax = ns.MAX_LEVEL
	end
end

local function PlayerLevel()
	return SafeNumber(UnitLevel("player")) or 1
end

local function RemainingXP()
	local cur = SafeNumber(UnitXP("player"))
	local maxXP = SafeNumber(UnitXPMax("player"))
	if not cur or not maxXP then
		return nil
	end
	local left = maxXP - cur
	if left < 0 then
		left = 0
	end
	return left
end

local function PinIndex(questID)
	local checked = ns.db and ns.db.checked
	if not checked then
		return nil
	end
	for i = 1, #checked do
		if checked[i] == questID then
			return i
		end
	end
	return nil
end

function ns.Pin(questID)
	if not questID or PinIndex(questID) then
		return
	end
	ns.db.checked[#ns.db.checked + 1] = questID
end

function ns.Unpin(questID)
	local i = PinIndex(questID)
	if not i then
		return
	end
	table.remove(ns.db.checked, i)
end

local function FilterRange()
	local mode = ns.db.filterMode or "all"
	local level = PlayerLevel()
	if mode == "mylevel" then
		return level, level
	elseif mode == "plus1" then
		return level - 1, level + 1
	elseif mode == "plus2" then
		return level - 2, level + 2
	elseif mode == "custom" then
		local minL = tonumber(ns.db.filterMin) or 1
		local maxL = tonumber(ns.db.filterMax) or ns.MAX_LEVEL
		if minL > maxL then
			minL, maxL = maxL, minL
		end
		return minL, maxL
	end
	return nil, nil
end

local function MatchesFilter(questLevel)
	local minL, maxL = FilterRange()
	if not minL then
		return true
	end
	if not questLevel then
		return true
	end
	return questLevel >= minL and questLevel <= maxL
end

local function Vec2(x, y)
	if CreateVector2D then
		return CreateVector2D(x, y)
	end
	return { x = x, y = y }
end

local function WorldPos(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and mapID and x and y) then
		return nil
	end
	local continent, world = C_Map.GetWorldPosFromMapPos(mapID, Vec2(x, y))
	if not continent or not world then
		return nil
	end
	local wx, wy = world.x, world.y
	if world.GetXY then
		wx, wy = world:GetXY()
	end
	return continent, wx, wy
end

local function Cardinal(dx, dy)
	if dx == 0 and dy == 0 then
		return nil
	end
	local angle = math.atan2(dx, dy)
	if angle < 0 then
		angle = angle + (2 * math.pi)
	end
	local oct = math.floor((angle + (math.pi / 8)) / (math.pi / 4)) % 8
	return CARDINALS[oct + 1]
end

local function PlayerWorld()
	if not (C_Map and C_Map.GetBestMapForUnit) then
		return nil
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil
	end
	local x, y = pos.x, pos.y
	if pos.GetXY then
		x, y = pos:GetXY()
	end
	if not x or not y then
		return nil
	end
	local continent, wx, wy = WorldPos(mapID, x, y)
	if not continent then
		return { mapID = mapID, x = x, y = y }
	end
	return { mapID = mapID, x = x, y = y, continent = continent, wx = wx, wy = wy }
end

local function DistanceTo(loc, player)
	if not loc or not player then
		return nil, nil
	end
	if loc.wx and loc.wy and player.wx and player.wy and loc.continent == player.continent then
		local dx = loc.wx - player.wx
		local dy = loc.wy - player.wy
		local dist = math.sqrt(dx * dx + dy * dy)
		return dist, Cardinal(dx, dy)
	end
	if loc.mapID == player.mapID and loc.x and loc.y and player.x and player.y then
		local dx = loc.x - player.x
		local dy = player.y - loc.y
		local dist = math.sqrt(dx * dx + dy * dy) * 1000
		return dist, Cardinal(dx, dy)
	end
	return nil, nil
end

local function StoreLoc(questID, mapID, x, y)
	if not questID or not mapID or not x or not y then
		return
	end
	local continent, wx, wy = WorldPos(mapID, x, y)
	locCache[questID] = {
		mapID = mapID,
		x = x,
		y = y,
		continent = continent,
		wx = wx,
		wy = wy,
	}
end

local function AddMap(list, seen, mapID)
	if not mapID or mapID == 0 or seen[mapID] then
		return
	end
	seen[mapID] = true
	list[#list + 1] = mapID
end

local function MapsToScan()
	local list, seen = {}, {}
	if not (C_Map and C_Map.GetBestMapForUnit) then
		return list
	end
	local best = C_Map.GetBestMapForUnit("player")
	AddMap(list, seen, best)
	if best and C_Map.GetMapChildrenInfo then
		local children = C_Map.GetMapChildrenInfo(best, nil, true)
		if children then
			for i = 1, #children do
				AddMap(list, seen, children[i].mapID)
			end
		end
	end
	if best and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(best)
		local parentID = info and info.parentMapID
		if parentID and parentID > 0 then
			local parent = C_Map.GetMapInfo(parentID)
			local mapType = parent and parent.mapType
			local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
			local dungeonType = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or 4
			if mapType == zoneType or mapType == dungeonType then
				AddMap(list, seen, parentID)
			end
		end
	end
	return list
end

local function HarvestMapPOIs()
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
		return
	end
	local maps = MapsToScan()
	for i = 1, #maps do
		local quests = C_QuestLog.GetQuestsOnMap(maps[i])
		if quests then
			for j = 1, #quests do
				local q = quests[j]
				if q and q.questID then
					StoreLoc(q.questID, q.mapID or maps[i], q.x, q.y)
					if not ns.mapQuest[q.questID] then
						ns.mapQuest[q.questID] = {
							questID = q.questID,
							isQuestStart = q.isQuestStart,
							inProgress = q.inProgress,
							mapID = q.mapID or maps[i],
							x = q.x,
							y = q.y,
						}
					end
				end
			end
		end
	end
end

local function HarvestWaypoints(questID)
	if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then
		return
	end
	local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
	if mapID and x and y then
		StoreLoc(questID, mapID, x, y)
	end
end

local function QuestTitle(questID, fallback)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local title = SafeString(C_QuestLog.GetTitleForQuestID(questID))
		if title and title ~= "" then
			return title
		end
	end
	if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
		C_QuestLog.RequestLoadQuestByID(questID)
	end
	return fallback or ("Quest " .. tostring(questID))
end

local function QuestLevel(questID, fallback)
	if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
		local level = SafeNumber(C_QuestLog.GetQuestDifficultyLevel(questID))
		if level then
			return level
		end
	end
	return fallback
end

local function ReadSelectedXP(questID)
	if GetQuestLogRewardXP and C_QuestLog and C_QuestLog.SetSelectedQuest then
		local prev
		if C_QuestLog.GetSelectedQuest then
			prev = C_QuestLog.GetSelectedQuest()
		end
		C_QuestLog.SetSelectedQuest(questID)
		local xp = SafeNumber(GetQuestLogRewardXP())
		if prev and C_QuestLog.SetSelectedQuest then
			C_QuestLog.SetSelectedQuest(prev)
		end
		if xp and xp > 0 then
			return xp
		end
	end
	if GetRewardXP then
		local xp = SafeNumber(GetRewardXP())
		if xp and xp > 0 then
			return xp
		end
	end
	return nil
end

local function GetQuestXP(questID, inLog)
	if xpCache[questID] then
		return xpCache[questID]
	end
	if inLog then
		local xp = ReadSelectedXP(questID)
		if xp then
			xpCache[questID] = xp
			return xp
		end
	end
	return 0
end

local function UsefulXP(questXP, remaining)
	questXP = questXP or 0
	if PlayerLevel() >= ns.MAX_LEVEL then
		return 0, questXP
	end
	if not remaining then
		return questXP, questXP
	end
	if questXP <= remaining then
		return questXP, questXP
	end
	return remaining, questXP
end

local function CollectLogQuests()
	local byID = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return byID
	end
	local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and info.questID and not info.isHeader and not info.isHidden then
			HarvestWaypoints(info.questID)
			byID[info.questID] = {
				questID = info.questID,
				title = info.title or QuestTitle(info.questID),
				level = info.level or info.difficultyLevel or QuestLevel(info.questID),
				inLog = true,
				isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID),
			}
		end
	end
	return byID
end

local function IsFlaggedComplete(questID)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted(questID)
	end
	return false
end

function ns.BuildRows()
	ns.mapQuest = {}
	HarvestMapPOIs()
	local logQuests = CollectLogQuests()
	local player = PlayerWorld()
	local remaining = RemainingXP()
	local combined = {}

	local function Ensure(questID)
		if combined[questID] then
			return combined[questID]
		end
		combined[questID] = { questID = questID }
		return combined[questID]
	end

	for questID, info in pairs(logQuests) do
		local row = Ensure(questID)
		row.title = info.title
		row.level = info.level
		row.inLog = true
		row.isComplete = info.isComplete
	end

	for questID, poi in pairs(ns.mapQuest) do
		if not IsFlaggedComplete(questID) then
			local row = Ensure(questID)
			row.isQuestStart = poi.isQuestStart
			if not row.title then
				row.title = QuestTitle(questID)
			end
			if not row.level then
				row.level = QuestLevel(questID)
			end
		end
	end

	for i = 1, #(ns.db.checked) do
		local questID = ns.db.checked[i]
		if questID and not combined[questID] and not IsFlaggedComplete(questID) then
			local row = Ensure(questID)
			row.title = QuestTitle(questID)
			row.level = QuestLevel(questID)
		end
	end

	local valid = {}
	local rows = {}
	for questID, row in pairs(combined) do
		if not IsFlaggedComplete(questID) then
			row.title = row.title or QuestTitle(questID)
			row.level = row.level or QuestLevel(questID)
			row.xp = GetQuestXP(questID, row.inLog)
			row.usefulXP, row.totalXP = UsefulXP(row.xp, remaining)
			row.loc = locCache[questID]
			row.distance, row.dir = DistanceTo(row.loc, player)
			row.pin = PinIndex(questID)
			valid[questID] = true
			if MatchesFilter(row.level) then
				rows[#rows + 1] = row
			end
		end
	end

	local pruned = {}
	for i = 1, #(ns.db.checked) do
		local id = ns.db.checked[i]
		if valid[id] then
			pruned[#pruned + 1] = id
		end
	end
	ns.db.checked = pruned

	local pinned, rest = {}, {}
	for i = 1, #rows do
		if rows[i].pin then
			pinned[#pinned + 1] = rows[i]
		else
			rest[#rest + 1] = rows[i]
		end
	end

	table.sort(pinned, function(a, b)
		return a.pin < b.pin
	end)

	table.sort(rest, function(a, b)
		local au = (a.usefulXP and a.usefulXP > 0) and 1 or 0
		local bu = (b.usefulXP and b.usefulXP > 0) and 1 or 0
		if au ~= bu then
			return au > bu
		end
		local ad = a.distance or math.huge
		local bd = b.distance or math.huge
		if ad ~= bd then
			return ad < bd
		end
		local ax = a.usefulXP or 0
		local bx = b.usefulXP or 0
		if ax ~= bx then
			return ax > bx
		end
		return (a.title or "") < (b.title or "")
	end)

	return pinned, rest, remaining
end

local function FormatDistance(distance, dir)
	if not distance then
		return "?? yd"
	end
	local yards = math.floor(distance + 0.5)
	local text = tostring(yards) .. " yd"
	if dir then
		text = text .. " " .. dir
	end
	return text
end

local function FormatXP(row)
	local total = row.totalXP or row.xp or 0
	if total == 0 and not row.inLog then
		return "XP once accepted", "ffffd100"
	end
	if total <= 0 then
		return "0 XP", "ff888888"
	end
	return tostring(total) .. " XP", "ff5ce65c"
end

local function LevelColor(level)
	if GetQuestDifficultyColor and level then
		local c = GetQuestDifficultyColor(level)
		if c then
			return c.r or 1, c.g or 1, c.b or 1
		end
	end
	return 1, 0.82, 0
end

local function SuperTrack(questID)
	if questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end
end

local function AcquireHeader(i)
	local header = headerPool[i]
	if header then
		return header
	end
	header = CreateFrame("Frame", nil, QuestPlannerScrollChild)
	header:SetSize(470, 22)
	header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header.label:SetPoint("LEFT", 8, 0)
	header.label:SetTextColor(1, 0.82, 0)
	headerPool[i] = header
	return header
end

local function AcquireRow(i)
	local row = rowPool[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, QuestPlannerScrollChild, "BackdropTemplate")
	row:SetSize(470, ns.ROW_HEIGHT - 4)
	row:RegisterForClicks("LeftButtonUp")
	if row.SetBackdrop then
		row:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 8,
			edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		row:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
		row:SetBackdropBorderColor(0.35, 0.3, 0.2, 0.9)
	end

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetPoint("LEFT", 4, 0)
	row.check:SetSize(26, 26)

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.title:SetPoint("TOPLEFT", 34, -6)
	row.title:SetPoint("RIGHT", -70, 0)
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)

	row.level = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.level:SetPoint("TOPRIGHT", -10, -6)

	row.meta = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.meta:SetPoint("BOTTOMLEFT", 36, 6)
	row.meta:SetPoint("BOTTOMRIGHT", -10, 6)
	row.meta:SetJustifyH("LEFT")

	row.check:SetScript("OnClick", function(self)
		if not row.questID then
			return
		end
		if self:GetChecked() then
			ns.Pin(row.questID)
		else
			ns.Unpin(row.questID)
		end
		ns.Refresh()
	end)

	row:SetScript("OnClick", function()
		if row.questID then
			SuperTrack(row.questID)
		end
	end)

	row:SetScript("OnEnter", function(self)
		if not self.questID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.title:GetText() or "Quest", 1, 0.82, 0)
		if self.data and self.data.isQuestStart and not self.data.inLog then
			GameTooltip:AddLine("Available quest (not in your log yet)", 0.8, 0.8, 0.8)
		end
		if C_QuestLog and C_QuestLog.GetQuestObjectives then
			local objectives = C_QuestLog.GetQuestObjectives(self.questID)
			if objectives then
				for oi = 1, #objectives do
					local obj = objectives[oi]
					if obj and obj.text then
						local r, g, b = 1, 1, 1
						if obj.finished then
							r, g, b = 0.4, 1, 0.4
						end
						GameTooltip:AddLine(obj.text, r, g, b, true)
					end
				end
			end
		end
		GameTooltip:AddLine("Click to super-track. Check to pin.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)

	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	rowPool[i] = row
	return row
end

local function HideUnused(pool, used)
	for i = used + 1, #pool do
		pool[i]:Hide()
	end
end

function ns.Refresh()
	if not uiReady or not QuestPlannerFrame or not QuestPlannerFrame:IsShown() then
		return
	end
	if not ns.db then
		Defaults()
	end

	local scroll = QuestPlannerScroll:GetVerticalScroll()
	local pinned, rest, remaining = ns.BuildRows()

	local y = 0
	local headersUsed = 0
	local rowsUsed = 0

	local function PlaceHeader(text)
		headersUsed = headersUsed + 1
		local header = AcquireHeader(headersUsed)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 0, -y)
		header.label:SetText(text)
		header:Show()
		y = y + 22
	end

	local function PlaceRow(data)
		rowsUsed = rowsUsed + 1
		local row = AcquireRow(rowsUsed)
		row.questID = data.questID
		row.data = data
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row.check:SetChecked(data.pin ~= nil)
		row.title:SetText(data.title or ("Quest " .. tostring(data.questID)))
		local levelText = data.level and ("Lv " .. tostring(data.level)) or "Lv ?"
		row.level:SetText(levelText)
		row.level:SetTextColor(LevelColor(data.level))
		local xpText, xpColor = FormatXP(data)
		row.meta:SetText(FormatDistance(data.distance, data.dir) .. "   |c" .. xpColor .. xpText .. "|r")
		if row.SetBackdropColor then
			if data.pin then
				row:SetBackdropColor(0.16, 0.14, 0.06, 0.95)
			else
				row:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
			end
		end
		row:Show()
		y = y + ns.ROW_HEIGHT
	end

	if #pinned > 0 then
		PlaceHeader("Pinned plan")
		for i = 1, #pinned do
			PlaceRow(pinned[i])
		end
	end
	if #rest > 0 then
		PlaceHeader("Closest useful")
		for i = 1, #rest do
			PlaceRow(rest[i])
		end
	end

	HideUnused(headerPool, headersUsed)
	HideUnused(rowPool, rowsUsed)

	if y < 10 then
		y = 10
	end
	QuestPlannerScrollChild:SetHeight(y)
	QuestPlannerScroll:SetVerticalScroll(math.min(scroll, math.max(0, y - QuestPlannerScroll:GetHeight())))

	local selectedXP = 0
	for i = 1, #pinned do
		selectedXP = selectedXP + (pinned[i].xp or pinned[i].totalXP or 0)
	end
	ns.UpdateMeter(selectedXP, remaining)

	if #pinned + #rest == 0 then
		QuestPlannerStatus:SetText("No quests match this filter. Pick up quests or widen the level band.")
	else
		local left = remaining and (tostring(remaining) .. " XP to next level") or "XP to next level unavailable"
		QuestPlannerStatus:SetText(string.format("%d pinned  ·  %d nearby  ·  %s", #pinned, #rest, left))
	end
end

function ns.RequestRefresh()
	if pendingRefresh then
		return
	end
	if not (C_Timer and C_Timer.After) then
		ns.Refresh()
		return
	end
	pendingRefresh = true
	C_Timer.After(0.12, function()
		pendingRefresh = false
		ns.Refresh()
	end)
end

function ns.UpdateMeter(selectedXP, remaining)
	if not ns.meterBar or not ns.meterLabel then
		return
	end
	selectedXP = selectedXP or 0
	if PlayerLevel() >= ns.MAX_LEVEL then
		ns.meterBar:SetMinMaxValues(0, 1)
		ns.meterBar:SetValue(1)
		ns.meterBar:SetStatusBarColor(0.45, 0.45, 0.45)
		ns.meterLabel:SetText("Level cap")
		return
	end
	if not remaining or remaining <= 0 then
		ns.meterBar:SetMinMaxValues(0, 1)
		ns.meterBar:SetValue(0)
		ns.meterBar:SetStatusBarColor(0.25, 0.55, 0.95)
		if selectedXP > 0 then
			ns.meterLabel:SetText(string.format("%d XP selected", selectedXP))
		else
			ns.meterLabel:SetText("XP needed unavailable")
		end
		return
	end
	ns.meterBar:SetMinMaxValues(0, remaining)
	if selectedXP > remaining then
		ns.meterBar:SetValue(remaining)
		ns.meterBar:SetStatusBarColor(0.25, 0.85, 0.35)
		ns.meterLabel:SetText(string.format("%d / %d XP to next level (%d XP OverQuest)", selectedXP, remaining, selectedXP - remaining))
	else
		ns.meterBar:SetValue(selectedXP)
		if selectedXP >= remaining * 0.85 and selectedXP > 0 then
			ns.meterBar:SetStatusBarColor(0.95, 0.75, 0.2)
		else
			ns.meterBar:SetStatusBarColor(0.25, 0.55, 0.95)
		end
		ns.meterLabel:SetText(string.format("%d / %d XP to next level", selectedXP, remaining))
	end
end

local function UpdateFilterButtons()
	if not ns.db then
		return
	end
	local mode = ns.db.filterMode or "all"
	for i = 1, #filterButtons do
		local btn = filterButtons[i]
		if btn.key == mode then
			btn:LockHighlight()
		else
			btn:UnlockHighlight()
		end
	end
	if ns.customRow then
		ns.customRow:SetShown(mode == "custom")
	end
end

local function MakeFilterButton(parent, index, spec)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(78, 22)
	btn:SetText(spec.label)
	btn.key = spec.key
	if index == 1 then
		btn:SetPoint("LEFT", parent, "LEFT", 0, 0)
	else
		btn:SetPoint("LEFT", filterButtons[index - 1], "RIGHT", 4, 0)
	end
	btn:SetScript("OnClick", function()
		Defaults()
		ns.db.filterMode = spec.key
		UpdateFilterButtons()
		ns.Refresh()
	end)
	filterButtons[index] = btn
	return btn
end

local function MakeEditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(2)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	return box
end

function ns.InitFrame(frame)
	if uiReady then
		return
	end
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.9)
	end
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Defaults()
		local point, _, _, x, y = self:GetPoint()
		ns.db.pos = { point = point, x = x, y = y }
	end)
	tinsert(UISpecialFrames, "QuestPlannerFrame")
	QuestPlannerHint:SetText("Check a quest to pin it. Uncheck and the next closest useful quest slides up.")

	local host = QuestPlannerFilterHost
	local btnWidth, btnGap = 78, 4
	local filterBar = CreateFrame("Frame", nil, host)
	filterBar:SetSize(#FILTERS * btnWidth + (#FILTERS - 1) * btnGap, 22)
	filterBar:SetPoint("TOP", host, "TOP", 0, 0)
	for i = 1, #FILTERS do
		MakeFilterButton(filterBar, i, FILTERS[i])
	end

	ns.customRow = CreateFrame("Frame", nil, host)
	ns.customRow:SetSize(220, 20)
	ns.customRow:SetPoint("TOP", host, "TOP", 0, -28)
	ns.customRow:Hide()

	ns.customLabel = ns.customRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	ns.customLabel:SetPoint("LEFT", ns.customRow, "LEFT", 0, 0)
	ns.customLabel:SetText("Min / max")

	ns.customMin = MakeEditBox(ns.customRow, 40)
	ns.customMin:SetPoint("LEFT", ns.customLabel, "RIGHT", 10, 0)
	ns.customMax = MakeEditBox(ns.customRow, 40)
	ns.customMax:SetPoint("LEFT", ns.customMin, "RIGHT", 10, 0)

	local meterHost = QuestPlannerMeterHost
	local meterWrap = CreateFrame("Frame", nil, meterHost, "BackdropTemplate")
	meterWrap:SetSize(380, 18)
	meterWrap:SetPoint("TOP", meterHost, "TOP", 0, 0)
	if meterWrap.SetBackdrop then
		meterWrap:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 8,
			edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		meterWrap:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		meterWrap:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
	end

	ns.meterBar = CreateFrame("StatusBar", nil, meterWrap)
	ns.meterBar:SetPoint("TOPLEFT", 3, -3)
	ns.meterBar:SetPoint("BOTTOMRIGHT", -3, 3)
	ns.meterBar:SetMinMaxValues(0, 1)
	ns.meterBar:SetValue(0)
	ns.meterBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	ns.meterBar:SetStatusBarColor(0.25, 0.55, 0.95)
	local meterBg = ns.meterBar:CreateTexture(nil, "BACKGROUND")
	meterBg:SetAllPoints()
	meterBg:SetTexture("Interface\\Buttons\\WHITE8x8")
	meterBg:SetVertexColor(0.08, 0.08, 0.08, 0.9)

	ns.meterLabel = meterHost:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	ns.meterLabel:SetPoint("TOP", meterWrap, "BOTTOM", 0, -4)
	ns.meterLabel:SetJustifyH("CENTER")
	ns.meterLabel:SetText("0 / 0 XP")

	local function ApplyCustom()
		Defaults()
		ns.db.filterMin = tonumber(ns.customMin:GetText()) or 1
		ns.db.filterMax = tonumber(ns.customMax:GetText()) or ns.MAX_LEVEL
		ns.db.filterMode = "custom"
		UpdateFilterButtons()
		ns.Refresh()
	end
	ns.customMin:SetScript("OnEnterPressed", ApplyCustom)
	ns.customMax:SetScript("OnEnterPressed", ApplyCustom)

	uiReady = true
	UpdateFilterButtons()
end

function ns.RestorePosition()
	local pos = ns.db and ns.db.pos
	if not pos or not pos.point then
		return
	end
	QuestPlannerFrame:ClearAllPoints()
	QuestPlannerFrame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
end

function ns.Toggle()
	if not QuestPlannerFrame then
		return
	end
	if QuestPlannerFrame:IsShown() then
		QuestPlannerFrame:Hide()
	else
		QuestPlannerFrame:Show()
	end
end

function ns.StartTicker()
	if ticker or not (C_Timer and C_Timer.NewTicker) then
		return
	end
	ticker = C_Timer.NewTicker(ns.REFRESH_INTERVAL, function()
		if QuestPlannerFrame and QuestPlannerFrame:IsShown() then
			ns.Refresh()
		end
	end)
end

function ns.StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function QuestPlanner_OnLoad(self)
	ns.InitFrame(self)
end

function QuestPlanner_OnShow(self)
	Defaults()
	if ns.customMin then
		ns.customMin:SetText(tostring(ns.db.filterMin or 1))
		ns.customMax:SetText(tostring(ns.db.filterMax or ns.MAX_LEVEL))
	end
	UpdateFilterButtons()
	ns.RestorePosition()
	ns.Refresh()
	ns.StartTicker()
end

function QuestPlanner_OnHide(self)
	ns.StopTicker()
end

function QuestPlanner_OnCompartmentClick()
	ns.Toggle()
end

local function SlashTaken(cmd)
	cmd = strlower(cmd)
	for name in pairs(SlashCmdList) do
		local i = 1
		local key = "SLASH_" .. name .. i
		while _G[key] do
			if strlower(_G[key]) == cmd then
				return true
			end
			i = i + 1
			key = "SLASH_" .. name .. i
		end
	end
	return false
end

local function OnSlash(msg)
	msg = strtrim(strlower(msg or ""))
	if msg == "debug" then
		ns.Debug()
		return
	end
	if msg == "help" then
		Print("Commands: /qp  /qp debug  /qp help")
		return
	end
	ns.Toggle()
end

function ns.BindSlash()
	if ns.slashBound then
		return
	end
	ns.slashBound = true
	SLASH_QUESTPLANNER1 = "/questplanner"
	if not SlashTaken("/qp") then
		SLASH_QUESTPLANNER2 = "/qp"
		Print("Type /qp to open the planner.")
	else
		Print("/qp is taken. Type /questplanner to open the planner.")
	end
	SlashCmdList["QUESTPLANNER"] = OnSlash
end

function ns.Debug()
	local version, build, _, toc = GetBuildInfo()
	Print("Client " .. tostring(version) .. " build " .. tostring(build) .. " toc " .. tostring(toc))
	Print("C_QuestLog: " .. tostring(C_QuestLog ~= nil))
	Print("GetQuestsOnMap: " .. tostring(C_QuestLog and C_QuestLog.GetQuestsOnMap ~= nil))
	Print("GetNextWaypoint: " .. tostring(C_QuestLog and C_QuestLog.GetNextWaypoint ~= nil))
	Print("GetQuestLogRewardXP: " .. tostring(GetQuestLogRewardXP ~= nil))
	Print("Remaining XP: " .. tostring(RemainingXP()))
	Defaults()
	local pinned, rest = ns.BuildRows()
	local locCount = 0
	for _ in pairs(locCache) do
		locCount = locCount + 1
	end
	Print(string.format("Pinned %d  nearby %d  locations %d", #pinned, #rest, locCount))
end

local events = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= addonName then
		return
	end
	Defaults()
	UpdateFilterButtons()
	events:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
	ns.BindSlash()
end

function handlers.PLAYER_XP_UPDATE()
	ns.RequestRefresh()
end

function handlers.PLAYER_LEVEL_UP()
	xpCache = {}
	ns.RequestRefresh()
end

function handlers.QUEST_LOG_UPDATE()
	ns.RequestRefresh()
end

function handlers.QUEST_POI_UPDATE()
	ns.RequestRefresh()
end

function handlers.QUEST_ACCEPTED()
	ns.RequestRefresh()
end

function handlers.QUEST_REMOVED()
	ns.RequestRefresh()
end

function handlers.QUEST_TURNED_IN()
	xpCache = {}
	ns.RequestRefresh()
end

function handlers.QUEST_DATA_LOAD_RESULT()
	ns.RequestRefresh()
end

function handlers.PLAYER_ENTERING_WORLD()
	ns.RequestRefresh()
end

function handlers.ZONE_CHANGED_NEW_AREA()
	ns.RequestRefresh()
end

function handlers.ZONE_CHANGED()
	ns.RequestRefresh()
end

events:SetScript("OnEvent", function(_, event, ...)
	local fn = handlers[event]
	if fn then
		fn(...)
	end
end)

local watched = {
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_XP_UPDATE",
	"PLAYER_LEVEL_UP",
	"QUEST_LOG_UPDATE",
	"QUEST_POI_UPDATE",
	"QUEST_ACCEPTED",
	"QUEST_REMOVED",
	"QUEST_TURNED_IN",
	"QUEST_DATA_LOAD_RESULT",
	"PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED_NEW_AREA",
	"ZONE_CHANGED",
}

for i = 1, #watched do
	pcall(function()
		events:RegisterEvent(watched[i])
	end)
end
