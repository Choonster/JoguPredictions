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



-- General AddOn locale strings
local general = ns.locale.general

--@localization(locale="enUS", format="lua_additive_table", handle-unlocalized="english", escape-non-ascii=false, table-name="general", same-key-is-true=true, namespace="General")@4