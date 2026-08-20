/// navGraphFree()
/// Releases everything the nav graph owns and returns the build to NAV_BUILD_IDLE.
/// Call on map change and before starting a new build. GM8 has no GC, so every
/// ds_grid_create needs a matching destroy or a map rotation leaks several grids per
/// map - and the scaffolding grids are the big ones.
///
/// Safe to call at any point in a build, including before the first one has ever run,
/// so callers do not have to track which grids exist yet.
///
/// Liveness is tracked with a -1 sentinel rather than ds_exists, which is a
/// GameMaker Studio function and does not exist in GM8. Every destroy here therefore
/// sets its global back to -1 immediately, and nothing else may hand these globals a
/// grid id without going through navBuildStart.

if(!variable_global_exists("navBuildState"))
{
    global.navBuildState = NAV_BUILD_IDLE;
    global.navReady = false;
    global.navNodes = -1;
    global.navEdges = -1;
    global.navEdgeIdx = -1;
    global.navCellGrid = -1;
    global.navPlatform = -1;
    global.navLethal = -1;
    global.navDoor = -1;
    global.navRowStart = -1;
    global.navAccEdges = -1;
    global.navAccCount = 0;
    global.navSolid = -1;
    global.navHfree = -1;
    global.navFree = -1;
    global.navDummy = noone;
    global.navNodeCount = 0;
    global.navEdgeCount = 0;
    global.navCursor = 0;
    exit;
}

if(global.navDummy != noone)
{
    if(instance_exists(global.navDummy))
    {
        with(global.navDummy)
            instance_destroy();
    }
    global.navDummy = noone;
}

if(global.navSolid >= 0)
{
    ds_grid_destroy(global.navSolid);
    global.navSolid = -1;
}
if(global.navHfree >= 0)
{
    ds_grid_destroy(global.navHfree);
    global.navHfree = -1;
}
if(global.navFree >= 0)
{
    ds_grid_destroy(global.navFree);
    global.navFree = -1;
}
if(variable_global_exists("navPlatform") and global.navPlatform >= 0)
{
    ds_grid_destroy(global.navPlatform);
    global.navPlatform = -1;
}
if(variable_global_exists("navLethal") and global.navLethal >= 0)
{
    ds_grid_destroy(global.navLethal);
    global.navLethal = -1;
}
if(variable_global_exists("navDoor") and global.navDoor >= 0)
{
    ds_grid_destroy(global.navDoor);
    global.navDoor = -1;
}
if(variable_global_exists("navCellGrid") and global.navCellGrid >= 0)
{
    ds_grid_destroy(global.navCellGrid);
    global.navCellGrid = -1;
}
if(variable_global_exists("navRowStart") and global.navRowStart >= 0)
{
    ds_grid_destroy(global.navRowStart);
    global.navRowStart = -1;
}
// An abandoned build leaves the edge accumulator open; it is not part of the graph
// but it is just as much a leak.
if(variable_global_exists("navAccEdges") and global.navAccEdges >= 0)
{
    ds_grid_destroy(global.navAccEdges);
    global.navAccEdges = -1;
    global.navAccCount = 0;
}
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
global.navCursor = 0;
global.navBuildState = NAV_BUILD_IDLE;
global.navReady = false;
