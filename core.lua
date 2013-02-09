local addon, ns = ...

-- Global vars/functions that we don't upvalue since they might get hooked, or upgraded
-- List them here for Mikk's FindGlobals script
--
-- General functions
-- GLOBALS: pairs, ipairs, GetItemInfo, UnitGUID, GetNumGossipOptions, GetGossipText, GetQuestResetTime, GetAddOnMetadata
--
-- Channel roster functions
-- GLOBALS: GetNumDisplayChannels, GetChannelDisplayInfo, GetChannelRosterInfo, SetSelectedDisplayChannel
--
-- Other channel functions
-- GLOBALS: SecondsToTime, GetGameTime, CalendarGetDate, GetChannelName, JoinChannelByName, SendChatMessage, SendAddonMessage

-- Standard Lua library functions
local select, print, tonumber, tostring = select, print, tonumber, tostring
local unpack, wipe = unpack, wipe
local strjoin, strsplit = strjoin, strsplit
local cocreate, coresume, coyield, costatus = coroutine.create, coroutine.resume, coroutine.yield, coroutine.status
local time = time

local VERSION = GetAddOnMetadata(addon, "X-Curse-Packaged-Version") or GetAddOnMetadata(addon, "Version")

-- The player's name
local PLAYER_NAME = UnitName("player")

-- Jogu the Drunk's NPC ID
local JOGU_ID = 58710

-- The current locale
local LOCALE = GetLocale()

-- Date string encoding/decoding patterns
-- "YYYY-MM-DDThh:mm"
-- year - month - day T hour : minute
-- Based on the W3C standard ISO 8601, the International Standard for the representation of dates and times.
-- This is the "Complete date plus hours and minutes" format without the timezone designator (because we don't need it)

local DATE_FORMAT = "%04d-%02d-%02dT%02d:%02d"
local DATE_MATCH = "(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)"
local DATE_LENGTH = #"0000-00-00"

-- Number of seconds in a minute/hour/day
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 60 * SECONDS_PER_MINUTE
local SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR

-- Communication constants
-- Because we're using chat channels, the delimiter needs to be a printable character.
local PREFIX = "JoguP"
local DELIM = "`"
local COMM_CHANNEL = "CommGlobal"

-- The number of seconds to wait after sending a query message before assuming the target isn't running JP.
-- It seems to take a long time during the first sync, but after that it speeds up.
local QUERY_TIMEOUT = 15

local MSGTYPE_UPDATE   = "update"
local MSGTYPE_QUERY    = "query"
local MSGTYPE_NOTREADY = "notready"

local STATUS_SUCCESS   = "success"
local STATUS_FAILURE   = "failure"

local ERR_CHAT_PLAYER_NOT_FOUND_S_MATCH = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("%%s", "(.+)")

-- Jogu's phrases and vegetable item link/icon cache.
local itemIDToPhrase, phraseToItemID, vegetableLinks, vegetableIcons;
do
	itemIDToPhrase = ns.locale.phrases
	phraseToItemID = {}
	vegetableLinks = {}
	vegetableIcons = {}
	-- JPI=vegetableIcons
	-- JPV=vegetableLinks
	local _;
	
	for itemID, phrase in pairs(itemIDToPhrase) do
		itemID = tonumber(itemID)
		phraseToItemID[phrase] = itemID
		_, vegetableLinks[itemID], _, _, _, _, _, _, _, vegetableIcons[itemID] = GetItemInfo(itemID) -- GetItemInfo doesn't always have data at this stage, but calling it here should make it available later
	end
end

-- General locale strings
local L;
do
	L = ns.locale.general
	
	for key, phrase in pairs(L) do
		if phrase == true then -- Support for AceLocale style `L[key] = true` declarations
			L[key] = key
		end
	end
end

-- Main frame
local JP = CreateFrame("Frame")
JP:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

-- itemID and time of the current prediction
local CURRENT_ITEMID = 0
local LAST_UPDATE = ""

-- The comm channel number
local CHANNEL_NUMBER = 0

-- Used to display how long ago we received an update
-- This is "%s (%s ago)" for enUS clients
local TIME_FORMAT = "%s " .. BNET_BROADCAST_SENT_TIME
local LT_ONE_MIN = "<" .. D_MINUTES:format(1)

-- Used for printing stuff to chat
local CHAT_PREFIX = "|cff33ff99" .. L["Jogu Predictions"] .. ":|r"
local ICON_FORMAT = "|T%s:0|t %s"

--[[----------------
-- Util Functions --
--]]----------------

local populateVegetableCaches;
if not vegetableLinks[74840] or not vegetableIcons[74840] then -- Only create the function if we don't have the data.

	function populateVegetableCaches()
		-- GetItemInfo didn't return data with the initial call, but it should be available now.
		-- This doesn't always happen, most of the time the initial call returns the correct data.
		local _;
		for itemID, phrase in pairs(itemIDToPhrase) do
			itemID = tonumber(itemID)
			_, vegetableLinks[itemID], _, _, _, _, _, _, _, vegetableIcons[itemID] = GetItemInfo(itemID) -- GetItemInfo doesn't always have data at this stage, but calling it here should make it available later
		end
		
		if vegetableLinks[74840] and vegetableIcons[74840] then
			-- We've got the data now, we can delete this function
			populateVegetableCaches = nil
		end
	end

end

local tonumberall;
do
	-- Based on some quick tests, the cache table version (loading the arguments into a table and unpacking the table) of the tonumberall function
	-- seems to be more efficient than the recursive version (returning the first argument followed by the result of calling itself with the remaining arguments)
	--
	-- The main disadvantage is that the cache table version can't handle nil arguments due to unpack's use of the length operator
	-- (though we could use table.maxn(tonumcache) as the second argument to unpack if we really needed to fix this).
	--
	-- Since the cache table one was taking about 0.33 seconds to convert 7,999 number string arguments between 1 and 1,000 and the recursive version was taking 1.2 seconds
	-- to do the same, the difference probably won't be noticable with the five arguments we're using this with.
	--
	-- I only wrote this because I wasn't sure which of the two versions of this function would be faster and decided to test it.
	-- I'd be surprised if anyone is actually interested in this relatively minor function.

	local tonumcache = {}
	function tonumberall(...)
		wipe(tonumcache)
		for i = 1, select("#", ...) do
			local argI = select(i, ...)
			tonumcache[i] = tonumber(argI) or argI
		end
		return unpack(tonumcache)
	end
end

local function joinArgs(...)
	return strjoin(DELIM, ...)
end

local function splitArgs(str)
	return strsplit(DELIM, str)
end

--@do-not-package@
local function debug(...)
	print("JP_Debug:", debugprofilestop(), ...)
end
--@end-do-not-package@

-- Extracts the NPC ID of a unit from its GUID
local function UnitNPCID(unit)
	local guid = UnitGUID(unit)
	return guid and guid:sub(5, 5) == "3" and tonumber(guid:sub(6, 10), 16) -- The 5th character is always 3 for NPCs, characters 6-10 are the NPC ID (in hexadecimal)
end

-- Date/time utils
local function EncodeDateString(year, month, day, hour, minute)
	local _, gMonth, gDay, gYear;
	if not year or not month or not day then -- Don't call the date/time functions if we received all the corresponding arguments.
		_, gMonth, gDay, gYear = CalendarGetDate() -- Note: CalendarGetDate returns the current date in the server's time zone, not the player's (which is a good thing in this case)
	end

	local gHour, gMinute;
	if not (hour and minute) then
		gHour, gMinute = GetGameTime()
	end

	return DATE_FORMAT:format(year or gYear, month or gMonth, day or gDay, hour or gHour, minute or gMinute)
end

local function DecodeDateString(dateString)
	return tonumberall(dateString:match(DATE_MATCH))
end

-- We can't actually get the seconds portion of the realm time,
-- so this function only converts the current hour/minute to a single seconds value
local function SecsFromMidnight(hour, minute)
	local gHour, gMinute;
	if not hour or not minute then
		gHour, gMinute = GetGameTime()
	end
	
	return ((hour or gHour) * SECONDS_PER_HOUR) + ((minute or gMinute) * SECONDS_PER_MINUTE)
end

-- Returns the number of seconds after midnight that dailies reset
local function GetDailyReset()
	local seconds = SecsFromMidnight() + GetQuestResetTime()
	if seconds > SECONDS_PER_DAY then
		seconds = seconds - SECONDS_PER_DAY
	end
	return seconds
end

-- Is our current prediction still accurate?
local function IsPredictionAccurate()
	local luYear, luMonth, luDay, luHour, luMinute = DecodeDateString(LAST_UPDATE)
	local luSecsFromMidnight = SecsFromMidnight(luHour, luMinute)
	
	local secsFromMidnight = SecsFromMidnight()
	local dailyReset = GetDailyReset()
	local beforeReset = secsFromMidnight < dailyReset
	
	local predictionDate = LAST_UPDATE:sub(1, DATE_LENGTH)
	local currentDate = EncodeDateString():sub(1, DATE_LENGTH)
	local predictionMadeToday = predictionDate == currentDate
	
	-- If it's after midnight but before the reset (secsFromMidnight < dailyReset), predictions made yesterday after the reset and today will be valid.
	-- If it's after the reset (secsFromMidnight > dailyReset), only predictions made today after the reset will be valid.
	
	local valid;
	if beforeReset == predictionMadeToday then
		-- When it's before the reset (beforeReset = true) and the prediction was made today (predictionMadeToday = true), it's always valid (return true).
		-- When it's after the reset (beforeReset = false) and the prediction wasn't made today (predictionMadeToday = false), it's always invalid (return false).
		-- This is a neat coincidence in logic that lets us avoid using nested if statements.
		valid = beforeReset
	else
		-- Otherwise it's only valid if it was made after the reset
		valid = luSecsFromMidnight > dailyReset
	end
	
	return valid, (not valid) and  L["Prediction was made before the reset."] -- Only do the table lookup if we need to
end
	
--[[
-- Explicit version of the above if statement
	if secsFromMidnight < dailyReset then
		if predictionMadeToday then -- Prediction was made today, it must be valid
			return true
		else						-- Predictions made yesterday after the reset will be valid
			local valid = luSecsFromMidnight > dailyReset
			return valid, (not valid) and  L["Prediction was made before the reset."] -- Only do the table lookup if we need to
		end
	else
		if predictionMadeToday then
			local valid = luSecsFromMidnight > dailyReset
			return valid, (not valid) and  L["Prediction was made before the reset."] -- Only do the table lookup if we need to
		else
			return false
		end
	end
--]]

local DateDiff, StringToTime;
do
	local t = {} -- temporary storage for the fields to pass to time()
	
	function StringToTime(dateString)
		t.year, t.month, t.day, t.hour, t.min = DecodeDateString(dateString) -- We don't need to worry about DST since we're only dealing with time differences and not absolute times
		return time(t)
	end
	
	-- Returns the number of seconds between date1 and date2 (i.e. date1 - date2)
	-- Both arguments must be dateStrings (from EncodeDateString)
	function DateDiff(date1, date2)
		local time1 = StringToTime(date1)
		local time2 = StringToTime(date2)
		
		return time1 - time2
	end
end

local function GetLastUpdateString()
	local lastUpdateSeconds = DateDiff(EncodeDateString(), LAST_UPDATE)
	local lastUpdateTime = lastUpdateSeconds <= 0 and LT_ONE_MIN or SecondsToTime(lastUpdateSeconds, false, true, 2)
	-- SecondsToTime can't handle a seconds value <= 0. In theory it should never be negative, but clients don't always have the correct realm time.
	return TIME_FORMAT:format(LAST_UPDATE:gsub("T", " ", 1), lastUpdateTime)
end

--[[-----------------------
-- LibDataBroker support --
--]]-----------------------
local DataObject = LibStub("LibDataBroker-1.1"):NewDataObject(L["Jogu Predictions"], {type = "data source", tocname = addon, text = L["No Prediction"], icon = "Interface\\Icons\\INV_Misc_MonsterHead_03"})

function DataObject:OnTooltipShow()
	self:AddDoubleLine(L["Jogu Predictions"])
	self:AddLine(" ")
	if CURRENT_ITEMID == 0 and LAST_UPDATE == "" then
		self:AddDoubleLine(L["Current Prediction:"], L["No Prediction"], nil,nil,nil, 1,1,1) -- Triple nils for the RGB values makes it use the default gold colour
		self:AddLine(L["Use |cffff0000/jogupredictions sync|r to update the prediction with a whisper sync."], 1,1,1)
	else
		self:AddDoubleLine(L["Current Prediction:"], vegetableLinks[CURRENT_ITEMID], nil,nil,nil, 1,1,1)
		self:AddDoubleLine(L["Last Updated:"], GetLastUpdateString(), nil,nil,nil, 1,1,1)
		
		local valid, reason = IsPredictionAccurate()
		if not valid then
			self:AddLine("\n")
			self:AddDoubleLine(L["WARNING!"], L["Prediction is no longer accurate!"], 1,0,0, 1,1,1)
			self:AddDoubleLine(L["Reason:"], reason, nil,nil,nil, 1, 1, 1)
		end
	end
end

--[[-------------------------
-- Communication Functions --
--]]-------------------------

RegisterAddonMessagePrefix(PREFIX)

-- Channel functions
local CommChannelIndex;
local AwaitingResponse;
local CurrentCo, QueryPlayer;
local QueryTimer = 0

local function CoBody(self) -- This function is the main body of the whisper sync coroutine
	self.SyncStarted = true
	
	AwaitingResponse = false
	CommChannelIndex = nil
	
	local channelIndex, channelCount;
	for i = 1, GetNumDisplayChannels() do -- Loop through the channels and headers until we find the comm channel
		local name, header, collapsed, channelNumber, count, active, category = GetChannelDisplayInfo(i)
		if name == COMM_CHANNEL then
			CommChannelIndex = i
			channelIndex = i
			if count then -- If the client already has the count for the comm channel, use it
				channelCount = count
			else
				SetSelectedDisplayChannel(i) -- Otherwise we select this channel, yield and wait for CHANNEL_COUNT_UPDATE to fire before resuming
				AwaitingResponse = true
				channelCount = coyield()
				AwaitingResponse = false
			end
			break -- We've found the comm channel, break the loop
		end
	end
	
	CommChannelIndex = nil
	
	if not channelIndex or not channelCount then
		--@do-not-package@
		-- debug("co:",
			-- ("Unable to find CommGlobal index or count! index = %s (type %s) count = %s (type %s)"):format(
				-- tostring(channelIndex), type(channelIndex), tostring(channelCount), type(channelCount)
			-- )
		-- )
		--@end-do-not-package@
		print(CHAT_PREFIX, L["Whisper sync failed. Try again soon."])
		return
	end
	
	local success = false
	for i = 1, channelCount do -- Loop through the players in the channel and send each one a QUERY message
		local name, owner, moderator, muted, active, enabled = GetChannelRosterInfo(channelIndex, i)
		if name and name ~= PLAYER_NAME then
			QueryPlayer = name
			QueryTimer = QUERY_TIMEOUT
			self:SendAddOnComm("WHISPER", name, MSGTYPE_QUERY)
			self:Show() -- Start the timeout OnUpdate script
			
			AwaitingResponse = true
			local status = coyield() -- status is passed to us from the timeout or reply/offline message event triggered by the comm we sent above
			AwaitingResponse = false
			
			if status == STATUS_SUCCESS then
				success = true
				break
			end
		end
	end
	
	if success then
		print(CHAT_PREFIX, L["Whisper sync successfully updated prediction."])
	else
		print(CHAT_PREFIX, L["Whisper sync did not receive a prediction reply. The current prediction will be updated when you or someone else using Jogu Predictions talks to Jogu."])
	end
end

function JP:StartSync()
	if not CurrentCo or costatus(CurrentCo) == "dead" then
		SetSelectedDisplayChannel(0)
		print(CHAT_PREFIX, L["Starting whisper sync."])
		
		CurrentCo = cocreate(CoBody)
		coresume(CurrentCo, self)
	end
end

function JP:JoinCommChannel()
	if GetChannelName(COMM_CHANNEL) == 0 then
		JoinChannelByName(COMM_CHANNEL)
	end
end

JP:RegisterEvent("PLAYER_ENTERING_WORLD")
JP:RegisterEvent("CHANNEL_UI_UPDATE")
JP:RegisterEvent("CHANNEL_COUNT_UPDATE")
JP:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")

function JP:PLAYER_ENTERING_WORLD() -- Channel info isn't available directly on P_E_W, so we wait for 10 seconds before starting the intial sync.
	if not self.SyncStarted then -- We haven't synced yet, this must have been a UI reload
		local timer = self:CreateAnimationGroup()
		local anim = timer:CreateAnimation()
		anim:SetDuration(5)
		timer:SetScript("OnFinished", function()
			self:StartSync()
		end)
		timer:Play()
	end
	
	if populateVegetableCaches then populateVegetableCaches() end
	
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function JP:CHANNEL_COUNT_UPDATE(channel, count)
	if channel == CommChannelIndex and AwaitingResponse and costatus(CurrentCo) == "suspended" then
		coresume(CurrentCo, count)
	end
end

local function Post_CHANNEL_UI_UPDATE(self)
	for i = 1, GetNumDisplayChannels() do
		local channel, header, collapsed, channelNumber, count, active, category = GetChannelDisplayInfo(i)
		if channel == COMM_CHANNEL then
			CHANNEL_NUMBER = GetChannelName(COMM_CHANNEL)
			self:StartSync()
			self:UnregisterEvent("CHANNEL_UI_UPDATE") -- We're done with this event now
			break
		end
	end
end

function JP:CHANNEL_UI_UPDATE()
	for i = 1, GetNumDisplayChannels() do
		local channel, header, collapsed, channelNumber, count, active, category = GetChannelDisplayInfo(i)
		if channel and not header then -- At least one channel has been joined, it should be safe to join the comm channel without messing up the channel numbers
			self:JoinCommChannel()
			self.CHANNEL_UI_UPDATE = Post_CHANNEL_UI_UPDATE -- Replace this function with one that starts the sync after the comm channel is joined
			break
		end
	end
end
	
function JP:CHAT_MSG_CHANNEL_NOTICE(noticeType, _, _, fullChannelName, _, _, channelID, channelNumber, channelName)
	if noticeType == "YOU_JOINED" and channelName == COMM_CHANNEL then
		CHANNEL_NUMBER = channelNumber
	elseif noticeType == "YOU_LEFT" and channelName == COMM_CHANNEL then
		CHANNEL_NUMBER = 0
	end
end

-- Sending functions
function JP:SendChannelComm(...)
	if CHANNEL_NUMBER == 0 then
		self:JoinCommChannel()
		CHANNEL_NUMBER = GetChannelName(COMM_CHANNEL)
	end

	SendChatMessage(joinArgs(PREFIX, ...), "CHANNEL", nil, CHANNEL_NUMBER)
end

function JP:SendAddOnComm(chatType, chatTarget, ...)
	SendAddonMessage(PREFIX, joinArgs(...), chatType, chatTarget)
end

-- Receiving functions
JP:RegisterEvent("CHAT_MSG_CHANNEL")
JP:RegisterEvent("CHAT_MSG_ADDON")
JP:RegisterEvent("CHAT_MSG_SYSTEM")

function JP:CHAT_MSG_CHANNEL(msg, author, language, fullChannelName, target, authorFlags, channelID, channelNumber, channelName, _, lineID, authorGUID)
	if CHANNEL_NUMBER == 0 then
		CHANNEL_NUMBER = GetChannelName(COMM_CHANNEL)
	end
	
	if channelName ~= COMM_CHANNEL then return end
	if author == PLAYER_NAME then return end

	local prefix, msgType, itemID, dateString = splitArgs(msg)
	if not prefix or prefix ~= PREFIX then return end

	if msgType == MSGTYPE_UPDATE and dateString and itemID then
		self:OnPredictionUpdate(tonumber(itemID), dateString)
	end
end

function JP:CHAT_MSG_ADDON(prefix, msg, chatType, author)
	if prefix ~= PREFIX then return end

	local msgType, itemID, dateString = splitArgs(msg)
	if msgType == MSGTYPE_UPDATE and itemID and dateString then
		self:OnPredictionUpdate(tonumber(itemID), dateString)
		self:OnQuerySuccess()
	elseif msgType == MSGTYPE_NOTREADY then
		self:OnQueryFailure()
	elseif msgType == MSGTYPE_QUERY then
		if CURRENT_ITEMID ~= 0 and LAST_UPDATE ~= "" then -- If we have a prediction, send it; else send a NOTREADY message.
			self:SendAddOnComm("WHISPER", author, MSGTYPE_UPDATE, CURRENT_ITEMID, LAST_UPDATE)
		else
			self:SendAddOnComm("WHISPER", author, MSGTYPE_NOTREADY)
		end
	end
end

function JP:CHAT_MSG_SYSTEM(msg)
	if QueryPlayer and msg:match(ERR_CHAT_PLAYER_NOT_FOUND_S_MATCH) == QueryPlayer then
		self:OnQueryFailure()
	end
end

function JP:OnUpdate(elapsed)
	QueryTimer = QueryTimer - elapsed
	
	if QueryTimer <= 0 and QueryPlayer then
		self:Hide() -- Stop the OnUpdate
		self:OnQueryFailure()
	end
end

JP:SetScript("OnUpdate", JP.OnUpdate)

-- Callback functions
function JP:OnPredictionUpdate(itemID, dateString)
	if dateString > LAST_UPDATE then -- Strings that represent later dates will always be "greater than" strings that represent earlier dates.
		CURRENT_ITEMID = itemID
		LAST_UPDATE = dateString
		DataObject.text = vegetableLinks[itemID]
		DataObject.icon = vegetableIcons[itemID]
	end
end

function JP:OnQuerySuccess()
	self:Hide()
	if AwaitingResponse then
		coresume(CurrentCo, STATUS_SUCCESS)
	end
end

function JP:OnQueryFailure()
	self:Hide()
	if AwaitingResponse then
		coresume(CurrentCo, STATUS_FAILURE)
	end
end

--[[----------------
-- Main functions --
--]]----------------
local LocalisedPhraseKeys = {}

JP:RegisterEvent("ADDON_LOADED")
JP:RegisterEvent("GOSSIP_SHOW")
JP:RegisterEvent("PLAYER_LOGOUT")

function JP:ADDON_LOADED(name)
	if name ~= addon then return end
	
	-- Load the predictions
	CURRENT_ITEMID = JOGUP_SAVED_ITEMID or 0
	LAST_UPDATE = JOGUP_SAVED_UPDATE or ""
	
	-- Load the phrases
	JOGU_PHRASES = JOGU_PHRASES or {}
	local joguPhrases = JOGU_PHRASES
	
	joguPhrases[LOCALE] = joguPhrases[LOCALE] or {}
	local phrases = joguPhrases[LOCALE]

	for i, phrase in ipairs(phrases) do -- Build up the localised [phrase] = true pairs from any saved phrases
		LocalisedPhraseKeys[phrase] = true
	end
	
	wipe(phrases)
	
	self:UnregisterEvent("ADDON_LOADED")
end

function JP:GOSSIP_SHOW()
	if UnitNPCID("npc") == JOGU_ID and GetNumGossipOptions() == 0 then
		-- Jogu is telling us what to plant
		local gossipText = GetGossipText()
		LocalisedPhraseKeys[gossipText] = true -- Add this phrase to the table
		
		local itemID = phraseToItemID[gossipText]
		if itemID then
			local dateString = EncodeDateString()
			self:OnPredictionUpdate(itemID, dateString)
			self:SendChannelComm(MSGTYPE_UPDATE, itemID, dateString)
		end
	end
end

function JP:PLAYER_LOGOUT()
	-- Save the prediction and update time
	JOGUP_SAVED_ITEMID = CURRENT_ITEMID
	JOGUP_SAVED_UPDATE = LAST_UPDATE
	
	-- The JOGU_PHRASES array saves a list of Jogu's phrases from each locale
	-- This allows users to submit the phrases (with English item name annotations), making it easy to modify the AddOn to work in their locale.
	local phrases = JOGU_PHRASES[LOCALE]
	
	for phrase, _ in pairs(LocalisedPhraseKeys) do -- Convert the phrase-keyed table to the JOGU_PHRASES array for saving
		phrases[#phrases + 1] = phrase
	end
end

--[[---------------
-- Slash Command --
--]]---------------
SLASH_JOGU_PREDICTIONS1, SLASH_JOGU_PREDICTIONS2, SLASH_JOGU_PREDICTIONS3 = L["/jogupredictions"], L["/jogup"], L["/jp"]

SlashCmdList.JOGU_PREDICTIONS = function(input)
	if input == "sync" then
		JP:StartSync()
	else
		if LAST_UPDATE == "" then
			print(CHAT_PREFIX, L["No Prediction"])
			print(L["Use |cffff0000/jogupredictions sync|r to update the prediction with a whisper sync."])
		else
			print(CHAT_PREFIX, L["Current Prediction:"], ICON_FORMAT:format(vegetableIcons[CURRENT_ITEMID], vegetableLinks[CURRENT_ITEMID]))
			print(L["Last Updated:"], GetLastUpdateString())
			
			local valid, reason = IsPredictionAccurate()
			if not valid then
				print("|cffff0000" .. L["WARNING!"] .. "|r",  L["Prediction is no longer accurate!"])
				print(L["Reason:"], reason)
			end
		end
	end	
end

--[[------------
-- Public API --
--]]------------

--- The global table that all API functions are stored in.
-- @name JPAPI
-- @class table
-- @description The global table that all API functions are stored in.
-- @field VERSION The current version of Jogu Predictions
JPAPI = {}

JPAPI.VERSION = VERSION

--- Returns the current prediction's itemID and the dateString of its last update time. Returns nil, nil when there hasn't been an update yet.
-- @return itemID (number) The itemID of the current prediction.
-- @return lastUpdate (string) The dateString representing the time of the last update.
function JPAPI:GetCurrentPrediction()
	local itemID = CURRENT_ITEMID ~= 0 and CURRENT_ITEMID or nil
	local lastUpdate = LAST_UPDATE ~= "" and LAST_UPDATE or nil
	
	return itemID, lastUpdate
end

--- Splits a dateString into its year, month, day, hour and minute components.
-- @param dateString (string) The dateString to decode.
-- @return year (number) The year component of the dateString.
-- @return month (number) The month component of the dateString.
-- @return day (number) The day component of the dateString.
-- @return hour (number) The hour component of the dateString.
-- @return minute (number) The minute component of the dateString.
function JPAPI:DecodeDateString(dateString)
	return DecodeDateString(dateString)
end

--- Returns the time represented by a dateString as a single integer (compatible with the standard date/time functions).
-- @param dateString (string) The dateString to decode.
-- @return time (number) The time represented by the dateString.
function JPAPI:StringToTime(dateString)
	return StringToTime(dateString)
end

--- Returns a dateString representing the specified date/time.
-- Any argument not passed to the function will use the corresponding return value of CalendarGetDate/GetGameTime instead.
-- Calling this with no arguments will return a dateString representing the current realm time.
-- @param year (number) The year component of the dateString.
-- @param month (number) The month component of the dateString.
-- @param day (number) The day component of the dateString.
-- @param hour (number) The hour component of the dateString.
-- @param minute (number) The minute component of the dateString.
-- @return dateString (string) The encoded dateString.
function JPAPI:EncodeDateString(year, month, day, hour, minute)
	return EncodeDateString(year, month, day, hour, minute)
end

--- Returns the time of the last update and how long ago that was as a human-readable string.
-- Suitable for displaying to the user.
-- @return lastUpdate (string) The time of the last update.
function JPAPI:GetLastUpdateString()
	return GetLastUpdateString()
end