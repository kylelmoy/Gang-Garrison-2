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
        global.navBuildState = NAV_BUILD_NODES;
    }
    return false;
}

// Node extraction is cheap - well under a millisecond even on cp_dirtbowl - so it
// finishes in one tick. Edge generation is not: jump edges alone are about a
// millisecond per node, which put ~845ms into a single frame when this stage did
// everything at once. That is a 25 frame stall on a live server, exactly what the
// chunking exists to avoid, so fall and jump run a slice of nodes at a time.
if(global.navBuildState == NAV_BUILD_NODES)
{
    global.navNodes = navNodesExtract(global.navFree, global.navSolid, global.navPlatform, global.navLethal, global.navDoor, global.navGate, global.navMaskW, global.navMaskH);
    global.navCellGrid = navNodeGrid(global.navNodes, global.navNodeCount, global.navMaskW, global.navMaskH);
    global.navRowStart = navRowIndex(global.navNodes, global.navNodeCount, global.navMaskH);
    // Which node set this index describes. navNodeFromWorld refuses to use it against any
    // other one; see its header for why a stale row index is worse than no row index.
    global.navRowFor = global.navNodes;
    global.navRowForCount = global.navNodeCount;

    navEdgesBegin();
    global.navCursor = 0;
    global.navBuildState = NAV_BUILD_WALK;
    return false;
}

if(global.navBuildState == NAV_BUILD_WALK)
{
    navWalkEdges(global.navNodes, global.navNodeCount, global.navMaskH);
    global.navCursor = 0;
    global.navBuildState = NAV_BUILD_FALL;
    return false;
}

if(global.navBuildState == NAV_BUILD_FALL)
{
    endAt = min(global.navNodeCount, global.navCursor + NAV_BUILD_EDGE_NODES * 4);
    navFallEdges(global.navNodes, global.navNodeCount, global.navFree, global.navCellGrid,
                 global.navGate, global.navMaskW, global.navMaskH, global.navCursor, endAt);
    navDropEdges(global.navNodes, global.navNodeCount, global.navFree, global.navCellGrid,
                 global.navGate, global.navMaskW, global.navMaskH, global.navCursor, endAt);
    global.navCursor = endAt;

    if(global.navCursor >= global.navNodeCount)
    {
        global.navCursor = 0;
        global.navBuildState = NAV_BUILD_JUMP;
    }
    return false;
}

if(global.navBuildState == NAV_BUILD_JUMP)
{
    endAt = min(global.navNodeCount, global.navCursor + NAV_BUILD_EDGE_NODES);
    navJumpEdges(global.navNodes, global.navNodeCount, global.navFree, global.navCellGrid,
                 global.navGate, global.navRowStart, global.navMaskW, global.navMaskH,
                 global.navCursor, endAt);
    global.navCursor = endAt;

    if(global.navCursor >= global.navNodeCount)
    {
        global.navCursor = 0;
        global.navBuildState = NAV_BUILD_MOVEBOX;
    }
    return false;
}

// A handful of instances at most, against hundreds of nodes either side of it, so
// this runs to completion in one tick rather than taking a cursor.
if(global.navBuildState == NAV_BUILD_MOVEBOX)
{
    navMoveBoxEdges(global.navFree, global.navCellGrid, global.navGate, global.navNodes, global.navMaskW, global.navMaskH);
    global.navBuildState = NAV_BUILD_FINISH;
    return false;
}

if(global.navBuildState == NAV_BUILD_FINISH)
{
    ds_grid_resize(global.navAccEdges, NAV_EDGE_FIELDS, max(global.navAccCount, 1));
    global.navEdges = navEdgesSortByFrom(global.navAccEdges, global.navAccCount, global.navNodeCount);
    ds_grid_destroy(global.navAccEdges);
    global.navAccEdges = -1;
    global.navAccCount = 0;

    global.navEdgeIdx = navEdgeIndex(global.navEdges, global.navEdgeCount, global.navNodeCount);

    // The scaffolding is much larger than the graph and trivially rederivable.
    //
    // navRowStart is the exception and is kept: it is one entry per mask row against the
    // cell grids' one per cell, and navNodeFromWorld needs it on every lookup to avoid
    // reading the whole node list. navGraphFree already frees it on the way out, and
    // navCacheLoad derives the same index for a cache hit.
    ds_grid_destroy(global.navCellGrid);
    global.navCellGrid = -1;
    ds_grid_destroy(global.navHfree);
    global.navHfree = -1;
    ds_grid_destroy(global.navFree);
    global.navFree = -1;
    ds_grid_destroy(global.navSolid);
    global.navSolid = -1;
    ds_grid_destroy(global.navPlatform);
    global.navPlatform = -1;
    ds_grid_destroy(global.navLethal);
    global.navLethal = -1;
    ds_grid_destroy(global.navDoor);
    global.navDoor = -1;
    ds_grid_destroy(global.navGate);
    global.navGate = -1;

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
