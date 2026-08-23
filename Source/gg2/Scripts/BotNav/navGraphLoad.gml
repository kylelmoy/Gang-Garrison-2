/// navGraphLoad()
/// Installs the nav graph for the map currently in play, by reading the cache file
/// gg2-nav-gen wrote for it. Returns true if a graph is now ready, false if there is
/// no usable cache - in which case bots on this map will not path.
///
/// The graph is NOT built here. It used to be: the generator lived in
/// Scripts/BotNav/ and ran a chunked build across server ticks, ~1.3s of work on the
/// largest shipped map spread thinly enough not to drop clients. That generator now
/// lives in the gg2-nav-gen tool, which produces byte-compatible cache files for every
/// map in well under a second and needs no game running, so the game keeps only the
/// half it cannot get anywhere else - reading the file and pathing on it.
///
/// A miss is therefore an operator problem, not a transient one: waiting will not
/// produce a graph. Run `gg2navgen build --all` and put the files in botnav/ beside
/// the executable. See Documentation/Bots.md.
///
/// Safe to call again at any time - it frees whatever the previous map left behind
/// first.

var key;

navGraphFree();

if(!variable_global_exists("CustomMapCollisionSprite"))
    return false;
if(!sprite_exists(global.CustomMapCollisionSprite))
    return false;

key = navCacheKey();
if(!navCacheLoad(key))
{
    // Left IDLE rather than DONE, so navServerTick keeps retrying: a cache file
    // dropped in while the server is up is picked up on the next tick that notices,
    // which is how an agent warms a running server without restarting it.
    global.navBuildState = NAV_BUILD_IDLE;
    global.navReady = false;
    return false;
}

global.navBuildState = NAV_BUILD_DONE;
global.navReady = true;
return true;
