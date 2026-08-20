/// navEdgesBuild(nodes, nodeCount, freeGrid, w, h)
/// Runs every edge generator and returns the finished edge grid, setting
/// global.navEdgeCount to how many it holds.
///
/// Does not touch global.navEdges - the caller installs the result. Building straight
/// into the live graph's variable would free the grid a running server is still
/// reading from.
///
/// Edges come out grouped by their from-node, which is what lets navEdgeIndex reduce
/// adjacency to a contiguous range per node instead of a scan of the whole list on
/// every A* expansion.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var nodes, nodeCount, freeGrid, w, h, nodeGrid, rowStart, sorted;
nodes = argument0;
nodeCount = argument1;
freeGrid = argument2;
w = argument3;
h = argument4;

navEdgesBegin();

if(nodeCount > 0)
{
    navWalkEdges(nodes, nodeCount, h);

    nodeGrid = navNodeGrid(nodes, nodeCount, w, h);
    navFallEdges(nodes, nodeCount, freeGrid, nodeGrid, w, h, 0, nodeCount);

    rowStart = navRowIndex(nodes, nodeCount, h);
    navJumpEdges(nodes, nodeCount, freeGrid, nodeGrid, rowStart, w, h, 0, nodeCount);
    ds_grid_destroy(rowStart);

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
