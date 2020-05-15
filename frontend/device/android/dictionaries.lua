local user_path = require("datastorage"):getDataDir() .. "/dictionaries.lua"
local ok, dicts = pcall(dofile, user_path)

if ok then
    return dicts
else
    return {
        -- tested dictionary applications
        { "Aard2", "Aard2", false, "itkach.aard2", "aard2" },
        { "Alpus", "Alpus", false, "com.ngcomputing.fora.android", "search" },
        { "ColorDict", "ColorDict", false, "com.socialnmobile.colordict", "colordict" },
        { "Eudic", "Eudic", false, "com.eusoft.eudic", "send" },
        { "Fora", "Fora Dict", false, "com.ngc.fora", "search" },
        { "GoldenFree", "GoldenDict Free", false, "mobi.goldendict.android.free", "send" },
        { "GoldenPro", "GoldenDict Pro", false, "mobi.goldendict.android", "send" },
        { "Kiwix", "Kiwix", false, "org.kiwix.kiwixmobile", "text" },
        { "Mdict", "Mdict", false, "cn.mdict", "send" },
        { "QuickDic", "QuickDic", false, "de.reimardoeffinger.quickdic", "quickdic" },
    }
end
