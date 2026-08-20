/// navBuildStart()
/// Begins building the nav graph for the current map, or adopts a cached one.
/// Returns true if the graph is ready immediately (cache hit), false if a chunked
/// build has been started and navBuildStep must be driven until it finishes.
///
/// Safe to call again at any time - it frees whatever the previous map left behind
/// first, so a mid-build map change abandons the old build rather than corrupting it.

var key;

navGraphFree();

if(!variable_global_exists("CustomMapCollisionSprite"))
    return false;
if(!sprite_exists(global.CustomMapCollisionSprite))
    return false;

key = navCacheKey();
if(navCacheLoad(key))
{
    global.navBuildState = NAV_BUILD_DONE;
    global.navReady = true;
    global.navFromCache = true;
    return true;
}
global.navFromCache = false;
global.navBuildT0 = current_time;
global.navBuildMs = -1;

global.navMaskW = sprite_get_width(global.CustomMapCollisionSprite);
global.navMaskH = sprite_get_height(global.CustomMapCollisionSprite);

// One dummy for the whole scan, at scale 1 so queries are in mask cells (F23). It
// outlives this script and is destroyed when the scan stage completes.
global.navDummy = instance_create(0, 0, CollisionDummy);
global.navDummy.sprite_index = global.CustomMapCollisionSprite;
global.navDummy.image_xscale = 1;
global.navDummy.image_yscale = 1;
global.navDummy.visible = false;

global.navSolid = ds_grid_create(global.navMaskW, global.navMaskH);
ds_grid_clear(global.navSolid, 0);
global.navHfree = ds_grid_create(global.navMaskW, global.navMaskH);
ds_grid_clear(global.navHfree, 0);
global.navFree = ds_grid_create(global.navMaskW, global.navMaskH);
ds_grid_clear(global.navFree, 0);
global.navPlatform = ds_grid_create(global.navMaskW, global.navMaskH);
ds_grid_clear(global.navPlatform, 0);
global.navLethal = ds_grid_create(global.navMaskW, global.navMaskH);
ds_grid_clear(global.navLethal, 0);

// PlayerWalls, drop-through platforms and the lethal volumes are instances rather
// than walkmask, so they have to be stamped in separately. Doing it once here rather
// than per band keeps it out of the chunked scan, and it is only a few dozen native
// region writes.
navMarkInstances(global.navSolid, global.navPlatform, global.navLethal, global.navMaskW, global.navMaskH);

global.navCellGrid = -1;
global.navRowStart = -1;
global.navCursor = 0;
global.navBuildState = NAV_BUILD_SCAN;
global.navReady = false;
return false;
