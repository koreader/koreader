-- List of acceptable extensions

ext = {
	djvuRead = ";djvu;",
	pdfRead  = ";pdf;xps;cbz;",
	creRead  = ";epub;txt;rtf;htm;html;mobi;prc;azw;fb2;chm;pdb;doc;tcr;zip;",
	picRead = ";jpg;jpeg;"
	-- seems to accept pdb-files for PalmDoc only
}


function ext:getReader(ftype, oldreader)
	local s = ";"
	if ftype == "" then
		return nil
	elseif string.find(self.pdfRead,s..ftype..s) then
		if oldreader and oldreader.use_koptreader then
			return KOPTReader
		else
			return PDFReader
		end
	elseif string.find(self.djvuRead,s..ftype..s) then
		if oldreader and oldreader.use_koptreader then
			return KOPTReader
		else
			return DJVUReader
		end
	elseif string.find(self.picRead,s..ftype..s) then
		return PICViewer
	elseif FileChooser.filemanager_expert_mode > FileChooser.BEGINNERS_MODE
	or string.find(self.creRead,s..ftype..s) then
		return CREReader
	else
		return nil
	end
end

