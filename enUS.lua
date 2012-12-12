-- Jogu Predictions locale: enUS

-- Vegetable item IDs:
-- 74840 = Green Cabbage
-- 74841 = Juicycrunch Carrot
-- 74842 = Mogu Pumpkin
-- 74843 = Scallions
-- 74844 = Red Blossom Leek
-- 74846 = Witchberries
-- 74847 = Jade Squash
-- 74848 = Striped Melon
-- 74849 = Pink Turnip
-- 74850 = White Turnip

local locale = GetLocale()
if locale ~= "enUS" then return end

local _, ns = ...
ns.locale = { phrases = {}, general = {} }

-- Jogu's prediction phrases
local phrases = ns.locale.phrases

--@localization(locale="enUS", format="lua_additive_table", handle-unlocalized="english", escape-non-ascii=false, table-name="phrases", same-key-is-true=false, namespace="Phrases")@

--@do-not-package@
-- For testing only.
phrases[74846] = "Which berries should you plant? Witchberries, of course!"
phrases[74840] = "Oooh... ooooh! My shenses are tingling! I see... huge Green Cabbages in your future."
phrases[74850] = "Fields of white turnips. Raw and shpicy!"
phrases[74843] = "Have I ever told you that I hate Scallions? Hate 'em!\n\n<Jogu lets out a loud belch.>\n\nUnfortunately for me, they're going to be in high season tomorrow."
phrases[74848] = "Striped melons are quite juishy this time of year! Put some sheeds in the ground, and you will reap the harvest on the morrow."
phrases[74847] = "Jade Melonsh grow the color of milky jade. Conditionsh will be perfect tomorrow for growing thish vegetable... I think."
phrases[74849] = "I'm seeing Pink Turnipsh in your future."
phrases[74841] = "You ever heard of a juicycrunch carrot? They'll never be juicier than tomorrow."
phrases[74842] = "Pumpkins! It'sh gonna be huge, gigantic pumpkins!"
phrases[74844] = "Shpring for a leek, and you might get two."
--@end-do-not-package@


-- General AddOn locale strings
local general = ns.locale.general

--@localization(locale="enUS", format="lua_additive_table", handle-unlocalized="english", escape-non-ascii=false, table-name="general", same-key-is-true=true, namespace="General")@

--@do-not-package@
-- For testing only
general["Jogu Predictions"] = true
general["Current Prediction:"] = true
general["Last Updated:"] = true
general["WARNING!"] = true
general["Prediction is no longer accurate!"] = true
general["Reason:"] = true
general["No Prediction"] = true
general["Prediction was made before the reset."] = true
general["N/A"] = true
general["Use |cffff0000/jogupredictions sync|r to update the prediction with a whisper sync."] = true
general["/jogupredictions"] = true
general["/jogup"] = true
general["/jp"] = true
general["Starting whisper sync."] = true
general["Whisper sync failed. Try again soon."] = true
general["Whisper sync successfully updated prediction."] = true
general["Whisper sync did not receive a prediction reply. The current prediction will be updated when you or someone else using Jogu Predictions talks to Jogu."] = true
--@end-do-not-package@
