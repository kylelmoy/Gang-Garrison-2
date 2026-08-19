/// navServerTick()
/// Drives the nav graph from the server's own tick: starts a build when the map the
/// graph was built for is no longer the map being played, and otherwise advances an
/// in-progress build by one frame's budget.
///
/// The trigger is a comparison against navCacheKey() rather than a hook in each of
/// the places a map can change. Map rotation, a mid-game CHANGE_MAP, the first load
/// after the server comes up, and advancing to the next area of a multi-stage map all
/// change that key, and all need exactly the same response - so keying off the value
/// picks them all up and cannot be defeated by a code path nobody remembered to hook.
/// It costs one short string build per tick.

var key;

if(!variable_global_exists("navBuildState"))
{
    navGraphFree();
    global.navKey = "";
}

// Nothing to build against until a map's collision geometry actually exists.
if(room != CustomMapRoom)
    exit;
if(!variable_global_exists("CustomMapCollisionSprite"))
    exit;
if(!sprite_exists(global.CustomMapCollisionSprite))
    exit;

key = navCacheKey();
if(global.navKey != key)
{
    global.navKey = key;
    navBuildStart();
    exit;
}

// A graph freed without the map changing - navGraphFree called directly, or a build
// abandoned - leaves the key matching but nothing built. Treat idle as "start one"
// rather than as "nothing to do", or the server sits with no graph forever.
if(global.navBuildState == NAV_BUILD_IDLE)
{
    navBuildStart();
    exit;
}

if(global.navBuildState != NAV_BUILD_DONE)
    navBuildStep();
