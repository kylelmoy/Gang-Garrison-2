/// navBuildStep()
/// Advances the chunked nav graph build by roughly one frame's worth of work.
/// Call once per virtual tick from the server while global.navBuildState is not
/// NAV_BUILD_IDLE or NAV_BUILD_DONE. Returns true when the graph has just become
/// ready.
///
/// The whole point of the chunking is that a cold build is ~1.3s on the largest
/// shipped map (F36), and a blocking loop that long stops GameServerBeginStep
/// servicing sockets, so every connected client lags out or drops (F31). Bots simply
/// do not path until global.navReady, which costs a few seconds of degraded behaviour
/// on the first ever visit to a map instead of a few seconds of dropped clients.
///
/// Budgets are per stage because the stages are not the same price per cell: the
/// solidity scan is ~0.48us/cell and the clearance dilation ~1.82us/cell (F36), so
/// counting both in the same "rows per tick" unit would either starve the scan or
/// overrun the frame during clearance.

var rows, cols, endAt;

if(global.navBuildState == NAV_BUILD_IDLE or global.navBuildState == NAV_BUILD_DONE)
    return false;

if(global.navBuildState == NAV_BUILD_SCAN)
{
    rows = max(1, NAV_BUILD_SCAN_CELLS div max(1, global.navMaskW));
    endAt = min(global.navMaskH, global.navCursor + rows);
    navSolidityScan(global.navDummy, global.navSolid, global.navMaskW, global.navCursor, endAt);
    global.navCursor = endAt;

    if(global.navCursor >= global.navMaskH)
    {
        with(global.navDummy)
            instance_destroy();
        global.navDummy = noone;
        global.navCursor = 0;
        global.navBuildState = NAV_BUILD_HFREE;
    }
    return false;
}

if(global.navBuildState == NAV_BUILD_HFREE)
{
    rows = max(1, NAV_BUILD_CLEAR_CELLS div max(1, global.navMaskW));
    endAt = min(global.navMaskH, global.navCursor + rows);
    navClearanceRows(global.navSolid, global.navHfree, global.navMaskW, global.navMaskH, global.navCursor, endAt);
    global.navCursor = endAt;

    if(global.navCursor >= global.navMaskH)
    {
        global.navCursor = 0;
        global.navBuildState = NAV_BUILD_FREE;
    }
    return false;
}

if(global.navBuildState == NAV_BUILD_FREE)
{
    cols = max(1, NAV_BUILD_CLEAR_CELLS div max(1, global.navMaskH));
    endAt = min(global.navMaskW, global.navCursor + cols);
    navClearanceCols(global.navHfree, global.navFree, global.navMaskW, global.navMaskH, global.navCursor, endAt);
    global.navCursor = endAt;

    if(global.navCursor >= global.navMaskW)
    {
        global.navCursor = 0;
        global.navBuildState = NAV_BUILD_FINISH;
    }
    return false;
}

// Node extraction and walk edges are both far cheaper than a clearance band - they
// measured at under a millisecond on gg_debug - so they finish in one tick rather
// than earning a chunked stage of their own.
if(global.navBuildState == NAV_BUILD_FINISH)
{
    global.navNodes = navNodesExtract(global.navFree, global.navSolid, global.navMaskW, global.navMaskH);
    global.navEdges = navWalkEdges(global.navNodes, global.navNodeCount, global.navMaskH);

    // The scaffolding is much larger than the graph and trivially rederivable.
    ds_grid_destroy(global.navHfree);
    global.navHfree = -1;
    ds_grid_destroy(global.navFree);
    global.navFree = -1;
    ds_grid_destroy(global.navSolid);
    global.navSolid = -1;

    navCacheSave(navCacheKey(), global.navNodes, global.navNodeCount,
                 global.navEdges, global.navEdgeCount, global.navMaskW, global.navMaskH);

    // Wall-clock cost of the cold build, so a server operator can see what a new
    // map actually cost rather than guessing from the frame counter.
    global.navBuildMs = current_time - global.navBuildT0;

    global.navBuildState = NAV_BUILD_DONE;
    global.navReady = true;
    return true;
}

return false;
