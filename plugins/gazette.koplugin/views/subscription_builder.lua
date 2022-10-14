local util = require("frontend/util")
local T = require("ffi/util").template

local EpubBuildDirector = require("libs/gazette/epubbuilddirector")
local WebPage = require("libs/gazette/resources/webpage")
local ResourceAdapter = require("libs/gazette/resources/webpageadapter")
local Epub = require("libs/gazette/epub/epub")
local ResultFactory = require("subscription/result/resultfactory")
local Template = require("libs/gazette/resources/htmldocument/template")
local Feed = require("subscription/type/feed")

local SubscriptionBuilder = {

}

function SubscriptionBuilder:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   return o
end

function SubscriptionBuilder:buildSingleEntry(subscription, entry)

   local builder = SubscriptionBuilder:new()
   local webpage, err = builder:createWebpage(subscription, entry)
   if not webpage
   then
      return ResultFactory:makeResult(entry):setError(err)
   end

   local epub = Epub:new{}
   epub:addFromList(ResourceAdapter:new(webpage))
   epub:setTitle(entry:getTitle())
   epub:setAuthor(subscription:getTitle())

   local output_dir = subscription:getDownloadDirectory()
   local epub_title = entry:getTitle()
   local epub_path = ("%s/%s.epub"):format(output_dir, util.getSafeFilename(epub_title))
   local build_director, err = builder:createBuildDirector(epub_path)
   if not build_director
   then
      return ResultFactory:makeResult(entry):setError(err)
   end

   local ok, err = build_director:construct(epub)
   if not ok
   then
      return ResultFactory:makeResult(entry):setError(err)
   end

   return ResultFactory:makeResult(entry):setSuccess()
end

function SubscriptionBuilder:createWebpage(subscription, entry)
   local html

   if subscription:getContentSource() == Feed.CONTENT_SOURCE.CONTENT
   then
      html = Template.HTML:format(entry:getTitle(), entry:getTitle(), entry:getContent())
   elseif subscription:getContentSource() == Feed.CONTENT_SOURCE.SUMMARY
   then
      html = Template.HTML:format(entry:getTitle(), entry:getTitle(), entry:getSummary())
   end

   local webpage, err = WebPage:new({
         url = entry:getPermalink(),
         html = html,
   })

   if err
   then
      return false, err
   end

   local success, err = webpage:build()

   if err
   then
      return false, err
   end

   return webpage
end

function SubscriptionBuilder:createBuildDirector(epub_path)
   local build_director, err = EpubBuildDirector:new()

   if not build_director
   then
      return false, err
   end

   local success, err = build_director:setDestination(epub_path)

   if not success
   then
      return false, err
   end

   return build_director
end

return SubscriptionBuilder
