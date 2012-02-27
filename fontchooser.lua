
FontChooser = {
	-- font name for menu contents
	cfont = "sans",
	-- font name for title
	tfont = "Helvetica-BoldOblique",
	-- font name for footer
	ffont = "sans",

	-- state buffer
	fonts = {"sans", "cjk", "mono", 
		"Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique",
		"Helvetica", "Helvetica-Oblique", "Helvetica-BoldOblique",
		"Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic",},
}

function FontChooser:init()
	clearglyphcache()
end

