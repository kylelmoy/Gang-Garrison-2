/// navGraphFree()
/// Releases everything the nav graph owns and returns the state to NAV_BUILD_IDLE.
/// Call on map change and before installing a new graph. GM8 has no GC, so every
/// ds_grid_create needs a matching destroy or a map rotation leaks three grids per map.
///
/// Safe to call at any point, including before a graph has ever been loaded, so
/// callers do not have to track which grids exist yet.
///
/// Liveness is tracked with a -1 sentinel rather than ds_exists, which is a
/// GameMaker Studio function and does not exist in GM8. Every destroy here therefore
/// sets its global back to -1 immediately, and nothing else may hand these globals a
/// grid id without going through navCacheLoad.
///
/// This used to free a dozen more grids - the solidity, clearance, platform, lethal,
/// door and gate masks, the cell grid, the edge accumulator and a collision dummy
/// instance - which were the scaffolding the in-game graph builder allocated. The
/// builder now lives in gg2-nav-gen and the game only ever loads a finished graph, so
/// the three grids below are all there is to own.

if(!variable_global_exists("navBuildState"))
{
    global.navBuildState = NAV_BUILD_IDLE;
    global.navReady = false;
    global.navNodes = -1;
    global.navEdges = -1;
    global.navEdgeIdx = -1;
    global.navRowStart = -1;
    global.navRowFor = -1;
    global.navRowForCount = -1;
    global.navNodeCount = 0;
    global.navEdgeCount = 0;
    global.navMaskW = 0;
    global.navMaskH = 0;
    exit;
}

if(variable_global_exists("navRowStart") and global.navRowStart >= 0)
{
    ds_grid_destroy(global.navRowStart);
    global.navRowStart = -1;
}
// Unconditionally, and not inside the branch above: the stamp must never outlive the
// index it describes, and a graph freed twice takes the second pass down this path with
// navRowStart already -1.
global.navRowFor = -1;
global.navRowForCount = -1;

if(global.navNodes >= 0)
{
    ds_grid_destroy(global.navNodes);
    global.navNodes = -1;
}
if(global.navEdges >= 0)
{
    ds_grid_destroy(global.navEdges);
    global.navEdges = -1;
}
if(variable_global_exists("navEdgeIdx") and global.navEdgeIdx >= 0)
{
    ds_grid_destroy(global.navEdgeIdx);
    global.navEdgeIdx = -1;
}

global.navNodeCount = 0;
global.navEdgeCount = 0;
global.navBuildState = NAV_BUILD_IDLE;
global.navReady = false;
