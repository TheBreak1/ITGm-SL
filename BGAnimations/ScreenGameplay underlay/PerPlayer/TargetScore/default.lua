local player = ...
local pn = ToEnumShortString(player)

local FailOnMissedTarget = PREFSMAN:GetPreference("EventMode") and SL[pn].ActiveModifiers.ActionOnMissedTarget == "Fail"
local RestartOnMissedTarget = PREFSMAN:GetPreference("EventMode") and SL[pn].ActiveModifiers.ActionOnMissedTarget == "Restart"

-- if nobody wants us, we won't appear
if (SL[pn].ActiveModifiers.DataVisualizations == "Disabled"
or SL[pn].ActiveModifiers.DataVisualizations == "Step Statistics"
or SL.Global.GameMode == "Casual"
or GAMESTATE:GetCurrentStyle():GetName():gsub("8","") == "double")
and (not SL[pn].ActiveModifiers.TargetScore)
then
	return
end


-- Pacemaker contributed by JackG
-- minor cleanup by dguzek and djpohly

local function get43size(size4_3)
	return 640*(size4_3/854)
end

 -- Finds the top score for the current song (or course) given a player.
local function GetTopScore(pn, kind)
	local SongOrCourse, StepsOrTrail

	local scorelist, text

	if GAMESTATE:IsCourseMode() then
		SongOrCourse = GAMESTATE:GetCurrentCourse()
		StepsOrTrail = GAMESTATE:GetCurrentTrail(pn)
	else
		SongOrCourse = GAMESTATE:GetCurrentSong()
		StepsOrTrail = GAMESTATE:GetCurrentSteps(pn)
	end

	if SongOrCourse and StepsOrTrail and kind then
		if kind == "Machine" then
			scorelist = PROFILEMAN:GetMachineProfile():GetHighScoreList(SongOrCourse,StepsOrTrail)
		elseif kind == "Personal" then
			scorelist = PROFILEMAN:GetProfile(pn):GetHighScoreList(SongOrCourse,StepsOrTrail)
		end

		if scorelist then
			local topscore = scorelist:GetHighScores()[1]
			if topscore then
				return topscore:GetPercentDP()
			end
		end
	end

	return 0
end

local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)

-- Ported from PSS.cpp, can be removed if that gets exported to Lua
local function GetCurMaxPercentDancePoints()
	local possible = pss:GetPossibleDancePoints()
	if possible == 0 then
		return 0
	end
	local currentMax = pss:GetCurrentPossibleDancePoints()
	if currentMax == possible then
		return 1
	end
	return currentMax / possible
end

local isTwoPlayers = (GAMESTATE:IsPlayerEnabled(PLAYER_1) and GAMESTATE:IsPlayerEnabled(PLAYER_2))
local bothWantBars = isTwoPlayers and (SL.P1.ActiveModifiers.DataVisualizations == "Target Score Graph") and (SL.P2.ActiveModifiers.DataVisualizations == "Target Score Graph")
local notefield_is_centered = (GetNotefieldX(player) == _screen.cx)
local use_smaller_graph = isTwoPlayers or notefield_is_centered

local targetBarBorderWidth = 2

local graph = { h=350, x=0 }

if use_smaller_graph then
	-- this graph is horizontally condensed compared to the full-width alternative
	graph.w = WideScale(25, 70)
	graph.y = 425

	-- smaller border for the target bar
	targetBarBorderWidth = 1

	-- if widescreen, nudge each graph over 5px, potentially creating a 10px gap if bothWantBars
	local separator = IsUsingWideScreen() and 5 or 0

	-- put the graph directly beside the note field
	if player == PLAYER_1 then
		graph.x = _screen.cx - graph.w - separator
	else
		graph.x = _screen.cx + separator
	end

	-- if Center1Player pref, or dance-solo, or techno single8, or kb7 single
	if notefield_is_centered then
		-- if 4:3 force the smaller graph to be 60px from the right edge of the screen
		-- if widescreen, adapt to the width of the notefield
		graph.x = WideScale( _screen.w-60, GetNotefieldX(player) + GetNotefieldWidth(player)/2 + 20)
	end
else

	-- full-width graph
	graph.w = WideScale(250, 300)
	graph.y = 430

	-- put the graph on the other side of the screen
	if (player == PLAYER_1) then
		graph.x = WideScale( get43size(500), 500)
	else
		graph.x = WideScale( get43size(40), 40)
	end
end

local barWidth = graph.w * 0.25
local barSpacing = barWidth / 4
local barOffset = barSpacing / 3

-- two player mode only shows current and target bar, so this needs to be adjusted
if use_smaller_graph then
	barWidth = graph.w * 0.3
	barSpacing = barWidth / 3

	if IsUsingWideScreen() then
		barOffset = barSpacing
	else
		barOffset = barSpacing * 1.5
	end
end

-- used to determine when we change grade
local currentGrade = nil
local previousGrade = nil

-- possible targets
-- { 'C-', 'C', 'C+', 'B-', 'B', 'B+', 'A-', 'A', 'A+', 'S-', 'S', 'S+', '*', '**', '***', '****', 'Machine best', 'Personal best' }

-- get personal best score
local pbGradeScore = GetTopScore(player, "Personal")

local target_grade = {
	-- the index of the target score chosen in the PlayerOptions menu
	index = tonumber(SL[pn].ActiveModifiers.TargetBar),
	-- the score the player is trying to achieve
	score = 0
}

if (target_grade.index == 17) then
	-- player set TargetGrade as Machine best
	target_grade.score = GetTopScore(player, "Machine")

elseif (target_grade.index == 18) then
	-- player set TargetGrade as Personal best
	target_grade.score = pbGradeScore
else
	-- player set TargetGrade as a particular letter grade
	-- anything from C- to ☆☆☆☆
	target_grade.score = THEME:GetMetric("PlayerStageStats", "GradePercentTier" .. string.format("%02d", 17 - target_grade.index))
end

-- if there is no personal/machine score, default to S as target
if target_grade.score == 0 then
	target_grade.score = THEME:GetMetric("PlayerStageStats", "GradePercentTier06")
end

-- Converts a percentage to an exponential scale, returning the corresponding Y point in the graph
local percentToYCoordinate = function(scorePercent)
	return -(graph.h*math.pow(100,scorePercent)/100)
end

-- Converts a grade enum to an exponential scale, returning the corresponding Y point in the graph
local getYFromGradeEnum = function(gradeEnum)
	return percentToYCoordinate(THEME:GetMetric("PlayerStageStats", "GradePercent" .. ToEnumShortString(gradeEnum)))
end

-- Checks to see if the target score is achievable

-- ActorFrame for the background of the graph
local barsBgActor = Def.ActorFrame{

	InitCommand=function(self)
		self:valign(0):halign(0)
	end,

	-- black background
	Def.Quad{
		InitCommand=function(self)
			self:valign(1):halign(0)
				:zoomto(graph.w, graph.h)
				:xy( 0, 0 )
		end,
		OnCommand=function(self)
			self:diffuse(Color.Black)
		end,
	}
}

-- adds alternating grey-black bars to represent each grade and sub-grade
-- (A-, A, A+, etc)
for i=1,16 do
	local tierStart = THEME:GetMetric("PlayerStageStats", "GradePercentTier" .. string.format("%02d", i))
	local tierEnd = THEME:GetMetric("PlayerStageStats", "GradePercentTier" .. string.format("%02d", i+1))
	local yStart = percentToYCoordinate(tierStart)
	local yEnd = percentToYCoordinate(tierEnd)

	barsBgActor[#barsBgActor+1] = Def.Quad{
		InitCommand=function(self)
			self:valign(0):halign(0)
				:zoomto(graph.w, -yStart+yEnd)
				:xy( 0, yStart )
		end,
		OnCommand=function(self)
			if (i % 2 == 1) then
				self:diffuse(color("#FFFFFF10"))
			else
				self:diffuse(color("#00000007"))
			end
		end,
	}
end

-- grades for which we should draw a border/label
local gradeBorders = { 2, 3, 4, 7, 10, 13, 16 }
local gradeNames = {"☆☆☆", "☆☆", "☆", "S", "A", "B", "C"}

-- draws a horizontal line and a label at every major grade border
for i = 1,#gradeBorders do
	local tierStart = THEME:GetMetric("PlayerStageStats", "GradePercentTier" .. string.format("%02d", gradeBorders[i]))
	local yStart = percentToYCoordinate(tierStart)

	barsBgActor[#barsBgActor+1] = Def.Quad{
		InitCommand=function(self)
			self:valign(0):halign(0)
				:zoomto(graph.w, 0.9)
				:xy( 0, yStart )
		end,
		OnCommand=function(self)
			self:diffuse(color("#FFFFFF4F"))
		end,
	}

	-- in 4:3 the graphs touch each other, so the labels for P2 are redundant
	if not (isTwoPlayers and bothWantBars and player == PLAYER_2 and not IsUsingWideScreen()) then
		barsBgActor[#barsBgActor+1] = Def.BitmapText{
			Font="_miso",
			Text=gradeNames[i],
			InitCommand=function(self)
				self:valign(1):halign(0)
					:xy( 2, yStart-2 )
				-- make stars a little smaller
				if i<4 then
					self:zoom(0.75)
				end
			end,
			-- zoom the label once we reach a grade, but only in 16:9
			GradeChangedCommand=function(self)
				if (bothWantBars and not IsUsingWideScreen()) then
					return
				end
				if (currentGrade == ("Grade_Tier" .. string.format("%02d", gradeBorders[i])) ) then
					self:decelerate(0.5):zoom(1.5)
				end
			end,
		}
	end
end

-- this is the final ActorFrame where everything will be shoved
local finalFrame = Def.ActorFrame{

	InitCommand=function(self)
		-- this makes for a more convenient coordinate system
		self:valign(0):halign(0)
	end,
	OnCommand=function(self)
		self:xy(graph.x, graph.y)

		currentGrade = pss:GetGrade()
		previousGrade = currentGrade
	end,
	-- any time we receive a judgment
	JudgmentMessageCommand=function(self,params)
		currentGrade = pss:GetGrade()

		-- this broadcasts a message to tell other actors that we have changed grade
		if (currentGrade ~= previousGrade) then
			if currentGrade ~= "Grade_Failed" then
				self:queuecommand("GradeChanged")
			end
			previousGrade = currentGrade
		end
		self:queuecommand("Update")
	end,

}

-- if the player wants the bar graph
if (SL[pn].ActiveModifiers.DataVisualizations == "Target Score Graph") then
	if use_smaller_graph then
		-- only two bars in 2 players mode
		finalFrame[#finalFrame+1] = Def.ActorFrame {
			-- insert the background actor frame
			barsBgActor,

			-- BAR 1
			-- Current Score
			Def.Quad{
				InitCommand=function(self)
					self:valign(1):halign(0)
						:zoomto(barWidth, 1)
						:xy( barSpacing + barOffset, 0 )
				end,
				OnCommand=function(self)
					self:diffuse(Color.Blue)
				end,
				-- follow the player's score
				UpdateCommand=function(self)
					local dp = pss:GetPercentDancePoints()
					self:zoomy(-percentToYCoordinate(dp))
				end
			},

			-- BAR 2
			-- Target Score
			Def.Quad{
				InitCommand=function(self)
					self:valign(1):halign(0)
						:zoomto(barWidth, 1)
						:xy( barOffset + barSpacing * 2 + barWidth, 0 )
				end,
				OnCommand=function(self)
					self:diffuse(Color.Red)
				end,
				UpdateCommand=function(self)
					local targetDP = target_grade.score * GetCurMaxPercentDancePoints()
					self:zoomy(-percentToYCoordinate(targetDP))
				end
			},

			-- TARGET BORDER
			Border(barWidth+targetBarBorderWidth*2, -percentToYCoordinate(target_grade.score)+3, targetBarBorderWidth)..{
				InitCommand=function(self)
					self:xy(barOffset + barSpacing * 2 + barWidth + barWidth/2, percentToYCoordinate(target_grade.score)/2)
				end,
			},
		}
	else
		finalFrame[#finalFrame+1] = Def.ActorFrame {

			-- insert the background actor frame
			barsBgActor,

			-- BAR 1
			-- Current Score
			Def.Quad{
				InitCommand=function(self)
					self:valign(1):halign(0)
						:zoomto(barWidth, 1)
						:xy( barSpacing + barOffset, 0 )
				end,
				OnCommand=function(self)
					self:diffuse(Color.Blue)
				end,
				-- follow the player's score
				UpdateCommand=function(self)
					local dp = pss:GetPercentDancePoints()
					self:zoomy(-percentToYCoordinate(dp))
				end
			},

			-- BAR 2
			-- Personal Best Score
			Def.Quad{
				InitCommand=function(self)
					self:valign(1):halign(0)
						:zoomto(barWidth, 1)
						:xy( barOffset + (barSpacing * 2) + barWidth, 0 )
				end,
				OnCommand=function(self)
					self:diffuse(Color.Green)
				end,
				UpdateCommand = function(self)
					local currentDP = pbGradeScore * GetCurMaxPercentDancePoints()
					self:zoomy(-percentToYCoordinate(currentDP))
				end,
			},

			-- BAR 3
			-- Target Score
			Def.Quad{
				InitCommand=function(self)
					self:valign(1):halign(0)
						:zoomto(barWidth, 1)
						:xy( barOffset + barSpacing * 3 + barWidth * 2, 0 )
				end,
				OnCommand=function(self)
					self:diffuse(Color.Red)
				end,
				UpdateCommand=function(self)
					local targetDP = target_grade.score * GetCurMaxPercentDancePoints()
					self:zoomy(-percentToYCoordinate(targetDP))
				end
			},

			-- PERSONAL BEST BORDER
			Border(barWidth+4, -percentToYCoordinate(pbGradeScore)+3, targetBarBorderWidth)..{
				InitCommand=function(self)
					self:xy(barOffset + (barSpacing * 2) + (barWidth/2) + barWidth * 1, percentToYCoordinate(pbGradeScore)/2)
				end,
			},

			-- TARGET BORDER
			Border(barWidth+4, -percentToYCoordinate(target_grade.score)+3, targetBarBorderWidth)..{
				InitCommand=function(self)
					self:xy(barOffset + (barSpacing * 3) + (barWidth/2) + barWidth * 2, percentToYCoordinate(target_grade.score)/2)
				end,
			},

			-- pretty explody thingies for grade changes

			LoadActor(THEME:GetPathB("ScreenGameplay","in/"..ThemePrefs.Get("VisualTheme").."_splode"))..{
				InitCommand=cmd(diffusealpha,0),
				GradeChangedCommand=cmd(y, getYFromGradeEnum(currentGrade); diffuse, GetCurrentColor(); rotationz,10; diffusealpha,0; zoom,0; diffusealpha,0.9; linear,0.6; rotationz,0; zoom,0.5; diffusealpha,0),
			},
			LoadActor(THEME:GetPathB("ScreenGameplay","in/"..ThemePrefs.Get("VisualTheme").."_splode"))..{
				InitCommand=cmd(diffusealpha,0),
				GradeChangedCommand=cmd(y, getYFromGradeEnum(currentGrade); diffuse, GetCurrentColor(); rotationy,180; rotationz,-10; diffusealpha,0; zoom,0.2; diffusealpha,0.8; decelerate,0.6; rotationz,0; zoom,0.7; diffusealpha,0),
			},
			LoadActor(THEME:GetPathB("ScreenGameplay","in/"..ThemePrefs.Get("VisualTheme").."_minisplode"))..{
				InitCommand=cmd(diffusealpha,0),
				GradeChangedCommand=cmd(y, getYFromGradeEnum(currentGrade); diffuse, GetCurrentColor(); rotationz,10; diffusealpha,0; zoom,0; diffusealpha,1; decelerate,0.8; rotationz,0; zoom,0.4; diffusealpha,0),
			},

			-- white graph border
			Border(graph.w+4, graph.h+4, 2)..{
				InitCommand=function(self)
					self:valign(1):halign(0)
					self:xy(graph.w/2,-graph.h/2)
				end,
			},
		}

		-- text labels for the bars
		finalFrame[#finalFrame+1] = Def.ActorFrame {
			InitCommand=function(self)
				if PREFSMAN:GetPreference("Center1Player") then
					self:visible(false)
				end
			end,

			Def.BitmapText{
				Font="_miso",
				Text=THEME:GetString("TargetScoreGraph", "You"),
				InitCommand=function(self)
					self:xy( barOffset + barSpacing + (barWidth/2), 20 )
				end,
			},

			Def.BitmapText{
				Font="_miso",
				Text=THEME:GetString("TargetScoreGraph", "Personal"),
				InitCommand=function(self)
					self:xy( barOffset + (barSpacing * 2) + (barWidth/2) + barWidth, 20 )
				end,
			},

			Def.BitmapText{
				Font="_miso",
				Text=THEME:GetString("TargetScoreGraph", "Target"),
				InitCommand=function(self)
					self:xy( barOffset + (barSpacing * 3) + (barWidth/2) + barWidth * 2, 20 )
				end,
			},
		}
	end
end


-- pacemaker text
if SL[pn].ActiveModifiers.TargetScore then
	finalFrame[#finalFrame+1] = Def.BitmapText{
		Font="_wendy small",
		InitCommand=function(self)

			local noteX
			local noteY
			local zoomF = 0.4
			local origX = GetNotefieldX(player)

			-- special casing: StomperZ with its receptor positions would appear over the normal pacemaker position
			if SL.Global.GameMode == "StomperZ" and SL[pn].ActiveModifiers.ReceptorArrowsPosition == "StomperZ" then
				-- put ourself just over the combo
				noteY = _screen.cy - 60
				zoomF = 0.35

				-- copied from MeasureCounter.lua
				local width = GetNotefieldWidth(player)
				local NumColumns = GAMESTATE:GetCurrentStyle():ColumnsPerPlayer()

				noteX = (width/NumColumns)

				self:shadowlength(1) -- match other playfield counters
			else
				noteY = 56
				noteX = GetNotefieldWidth(player) / 4
				-- this serendipitiously works for doubles, somehow

				-- antisymmetry kludge; nudge PLAYER_2's pacemaker text to the left so that it
				-- doesn't possibly overlap with the percent score text.  this is necessary because
				-- P1 and P2 percent scores are not strictly symmetrical around the horizontal middle
				if (player ~= PLAYER_1 and isTwoPlayers) then
					noteX = noteX + 25
				end
			end

			-- flip x-coordinate based on player
			if (player ~= PLAYER_1) then
				noteX = -1 * noteX
			end
			noteX = noteX + origX

			-- compensate so that we can use "normal" coordinate systems
			self:horizalign(center):xy( noteX - graph.x, noteY - graph.y ):zoom(zoomF)

		end,
		UpdateCommand=function(self)
			local DPCurr = pss:GetActualDancePoints()
			local DPCurrMax = pss:GetCurrentPossibleDancePoints()
			local DPMax = pss:GetPossibleDancePoints()

			local percentDifference = (DPCurr - (target_grade.score * DPCurrMax)) / DPMax

			-- cap negative score displays
			percentDifference = math.max(percentDifference, -target_grade.score)

			local places = 2
			-- if there's enough dance points so that our current precision is ambiguous,
			-- i.e. each dance point is less than half of a digit in the last place,
			-- and we don't already display 2.5 digits,
			-- i.e. 2 significant figures and (possibly) a leading 1,
			-- add a decimal point.
			-- .1995 prevents flickering between .01995, which is rounded and displayed as ".0200", and
			-- and an actual .0200, which is displayed as ".020"
			while (math.abs(percentDifference) < 0.1995 / math.pow(10, places))
				and (DPMax >= 2 * math.pow(10, places + 2)) and (places < 4) do
				places = places + 1
			end

			self:settext(string.format("%+."..places.."f", percentDifference * 100))

			-- have we already missed so many dance points
			-- that the current goal is not possible anymore?
			if ((DPCurrMax - DPCurr) > (DPMax * (1 - target_grade.score))) then
				self:diffusealpha(0.65)

				-- check to see if the user wants to do something when they don't achieve their score.
				if FailOnMissedTarget then
					-- use SM_BeginFailed instead of SM_NotesEnded to *immediately* leave the screen instead of a nice fadeout.
					-- we want to get back into the next round because we want that score boi.
					SCREENMAN:GetTopScreen():PostScreenMessage("SM_BeginFailed", 0)
				elseif RestartOnMissedTarget then
					-- this setting assumes event mode, so no need for changing stage number.
					SCREENMAN:GetTopScreen():SetPrevScreenName("ScreenGameplay"):SetNextScreenName("ScreenGameplay"):begin_backing_out()
				end
			end
		end,
	}
end

return finalFrame
