/// navCacheKey()
/// Returns a filename-safe identity for the nav graph of the map currently in play.
///
/// Deliberately NOT the map MD5 on its own, which is the obvious choice and is wrong:
/// serverGotoMap.gml sets global.currentMapMD5 = "" for every internal map, and
/// CustomMapGetMapMD5 also returns "" when the PNG is missing. Keying on the MD5
/// alone would give all 22 shipped maps the same cache entry, and the first graph
/// built would then be silently served for every other built-in map - bots pathing
/// ctf_truefort against gg_debug's geometry.
///
/// The map name is the real identity. The MD5 is appended only when non-empty, so a
/// custom map republished under an existing name still invalidates its own cache.
/// currentMapArea is part of the key because basicRoomSetup destroys everything
/// outside the active stage's y-band, making each stage of a multi-area map a
/// genuinely different graph.

var name, safe, i, c, code, key;

name = global.currentMap;
safe = "";
for(i = 1; i <= string_length(name); i += 1)
{
    c = string_char_at(name, i);
    code = ord(c);
    if((code >= ord("a") and code <= ord("z")) or (code >= ord("A") and code <= ord("Z"))
        or (code >= ord("0") and code <= ord("9")) or c == "_" or c == "-")
    {
        safe += c;
    }
    else
    {
        safe += "_";
    }
}

key = safe + "_a" + string(global.currentMapArea);
if(global.currentMapMD5 != "")
    key += "_" + global.currentMapMD5;

return key;
