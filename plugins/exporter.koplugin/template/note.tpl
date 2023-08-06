#{
  -- helper function to convert decimal value to hex value(with trailing zeros)
  function rgb_to_hex(r, g, b)
    r = string.format("%x", r)
    g = string.format("%x", g)
    b = string.format("%x", b)
    -- add trailing zeros
    if #r == 1 then
      r = "0" .. r
    end
    if #g == 1 then
      g = "0" .. g
    end
    if #b == 1 then
      b = "0" .. b
    end
    return "#" .. r .. g .. b
  end
  -- helper function to map time to JET color
  function timecolor(time)
    local r,g,b
    local year = 3600*24*30*12
    local lapse = os.time() - time
    if lapse <= 1*year then
      r,g,b = 255, 255*(year-lapse)/year, 0
    elseif lapse > 1*year and lapse < 2*year then
      r,g,b = 255*(lapse-year)/year, 255, 255*(2*year-lapse)/year
    elseif lapse >= 2*year then
      r,g,b = 0, 255*(lapse-2*year)/year, 255
    end
    r = r > 255 and 255 or math.floor(r)
    r = r < 0 and 0 or math.floor(r)
    g = g > 255 and 255 or math.floor(g)
    g = g < 0 and 0 or math.floor(g)
    b = b > 255 and 255 or math.floor(b)
    b = b < 0 and 0 or math.floor(b)

    return rgb_to_hex(r, g, b)
  end

  function htmlescape(text)
    if text == nil then return "" end

    local esc, _ = text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
    return esc
  end
  function newline_to_br(text)
    return text:gsub("\n", "<br/>")
  end
}#
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8"/>
  <title>#{= htmlescape(document_title) }#</title>
</head>
<body>
  <div style="width:90%; max-width:600px; margin:0 auto; padding:5px; font-size:12pt; font-family:Georgia, serif">
    #{ for  _, booknotes in ipairs(clippings) do }#
    <h2 style="font-size:18pt; text-align:right;">#{= htmlescape(booknotes.title) }#</h2>
    <h5 style="font-size:12pt; text-align:right; color:gray;">#{= htmlescape(booknotes.author:gsub("\n", ", ")) }#</h5>
    #{ for  _, chapter in ipairs(booknotes.chapters) do }#
      #{ if chapter.title then }#
        <div style="font-size:14pt; font-weight:bold; text-align:center; margin:0.5em;"><span>#{= htmlescape(chapter.title) }#</span></div>
      #{ end }#
      #{ for index, clipping in ipairs(chapter.entries) do }#
        <div style="padding-top:0.5em; padding-bottom:0.5em;#{ if index > 1 then }# border-top:1px dotted lightgray;#{ end }#">
          <div style="font-size:10pt; margin-bottom:0.2em; color:darkgray">
            <div style="display:inline-block; width:0.2em; height:0.9em; margin-right:0.2em; background-color:#{= timecolor(clipping.time)}#;"></div>
            <span>#{= os.date("%x", clipping.time) }#</span><span style="float:right">#{ if clipping.chapter then }#<b>#{= clipping.chapter }#</b>: #{ end }# #{= clipping.page }#</span>
          </div>
          <div style="font-size:12pt">
            <span>#{= newline_to_br(htmlescape(clipping.text)) }#</span>
            #{ if clipping.image then }#
              <en-media type="image/png" hash="#{= clipping.image.hash }#"/>
            #{ end }#
          </div>
          #{ if clipping.note then }#
            <div style="font-size:11pt; margin-top:0.2em; margin-left:2em;">
              <span style="color:#888888">#{= newline_to_br(htmlescape(clipping.note)) }#</span>
            </div>
          #{ end }#
        </div>
      #{ end }#
    #{ end }#
    #{ end }#
  </div>
</body>
</html>
