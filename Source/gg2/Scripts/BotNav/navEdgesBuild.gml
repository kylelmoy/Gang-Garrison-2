/// navEdgesBuild(nodes, nodeCount, freeGrid, gateGrid, w, h)
/// Runs every edge generator and returns the finished edge grid, setting
/// global.navEdgeCount to how many it holds.
///
/// Does not touch global.navEdges - the caller installs the result. Building straight
/// into the live graph's variable would free the grid a running server is still
/// reading from.
///
/// gateGrid may be -1 for a caller that has no gates - the unit tests mostly do, and
/// the generators each guard the handle rather than the whole graph doing so once.
///
/// Edges come out grouped by their from-node, which is what lets navEdgeIndex reduce
/// adjacency to a contiguous range per node instead of a scan of the whole list on
/// every A* expansion.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var nodes, nodeCount, freeGrid, gateGrid, w, h, nodeGrid, rowStart, sorted;
nodes = argument0;
nodeCount = argument1;
freeGrid = argument2;
gateGrid = argument3;
w = argument4;
h = argument5;

navEdgesBegin();

if(nodeCount > 0)
{
    navWalkEdges(nodes, nodeCount, h);

    nodeGrid = navNodeGrid(nodes, nodeCount, w, h);
    navFallEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, w, h, 0, nodeCount);
    navDropEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, w, h, 0, nodeCount);

    rowStart = navRowIndex(nodes, nodeCount, h);
    navJumpEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, rowStart, w, h, 0, nodeCount);
    ds_grid_destroy(rowStart);

    navMoveBoxEdges(freeGrid, nodeGrid, gateGrid, nodes, w, h);

    ds_grid_destroy(nodeGrid);
}

ds_grid_resize(global.navAccEdges, NAV_EDGE_FIELDS, max(global.navAccCount, 1));

// Group by from-node. GM8 has no ds_grid_sort, and the key is a small dense integer,
// so this is a counting sort rather than a comparison sort.
sorted = navEdgesSortByFrom(global.navAccEdges, global.navAccCount, nodeCount);
ds_grid_destroy(global.navAccEdges);
global.navAccEdges = -1;
global.navAccCount = 0;
return sorted;
