/// navServerTick()
/// Drives the nav graph from the server's own tick: installs the graph for the map
/// being played whenever that is no longer the map the current graph belongs to.
///
/// The trigger is a comparison against navCacheKey() rather than a hook in each of
/// the places a map can change. Map rotation, a mid-game CHANGE_MAP, the first load
/// after the server comes up, and advancing to the next area of a multi-stage map all
/// change that key, and all need exactly the same response - so keying off the value
/// picks them all up and cannot be defeated by a code path nobody remembered to hook.
/// It costs one short string build per tick.
///
/// The key alone is not enough, because it is the map's IDENTITY and re-loading the same
/// map does not change it. That is the case that matters while iterating on the graphs
/// themselves: regenerate with gg2navgen, send the server back to the map it is already
/// on, and without the second half of this test the server would go on pathing against
/// the copy it read the first time. It did exactly that during the 2026-08-23 pass -
/// a scenario blacklisted an edge that no longer existed in the file on disk, twice in a
/// row, and only a server restart made it read 0. So a map LOAD is a second trigger, and
/// global.navMapGen is bumped by the one line in CustomMapProcessLevelData that brings a
/// map's collision geometry into being.
///
/// Loading is a single file read, so unlike the chunked build this replaced there is
/// no work to spread across ticks and no window in which bots path against a half
/// finished graph: after navGraphLoad the graph is either complete or absent.

var key;

if(!variable_global_exists("navBuildState"))
{
    navGraphFree();
    global.navKey = "";
}

// Separately from the block above: navGraphFree can be called from elsewhere, which
// creates navBuildState without ever coming through here.
if(!variable_global_exists("navRetryAt"))
    global.navRetryAt = 0;

// Both halves of the load trigger, defaulted so a server that has not loaded a map yet
// compares against something rather than against an undefined global. navGen is the
// generation the CURRENT graph was read at; navMapGen is the generation the game is on.
// They start different on purpose, so the first map load always reads.
if(!variable_global_exists("navMapGen"))
    global.navMapGen = 0;
if(!variable_global_exists("navGen"))
    global.navGen = -1;

// Nothing to load a graph for until a map's collision geometry actually exists.
if(room != CustomMapRoom)
    exit;
if(!variable_global_exists("CustomMapCollisionSprite"))
    exit;
if(!sprite_exists(global.CustomMapCollisionSprite))
    exit;

key = navCacheKey();
if(global.navKey != key or global.navGen != global.navMapGen)
{
    global.navKey = key;
    global.navGen = global.navMapGen;
    global.navRetryAt = 0;
    navGraphLoad();
    exit;
}

// A map with no cache file leaves the state IDLE, and so does navGraphFree called
// directly. Retry either way rather than treating idle as "nothing to do", so a graph
// dropped into botnav/ by gg2-nav-gen while the server is up is picked up without a
// restart - but on a timer, since the common case is a map nobody has generated yet
// and stat()ing that same missing file thirty times a second buys nothing.
if(global.navBuildState == NAV_BUILD_IDLE)
{
    if(current_time >= global.navRetryAt)
    {
        global.navRetryAt = current_time + 5000;
        navGraphLoad();
    }
}
