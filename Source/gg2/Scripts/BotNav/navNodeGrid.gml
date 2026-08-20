/// navNodeGrid(nodes, nodeCount, w, h)
/// Returns a ds_grid the size of the mask where each cell holds the index of the node
/// occupying it, or -1. This is the "which surface is at this cell" lookup that fall
/// edge generation and navNodeFromWorld both need, and it turns both from a search
/// into a single read.
///
/// Filled with one native ds_grid_set_region per node rather than a cell loop, so the
/// cost is proportional to the node count (hundreds) rather than to the mask (up to
/// 560,000 cells).
///
/// This is scaffolding - it is as large as the mask - so free it once edges are
/// generated rather than keeping it alongside the graph.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var nodes, nodeCount, w, h, g, i, ny, nx0, nx1;
nodes = argument0;
nodeCount = argument1;
w = argument2;
h = argument3;

g = ds_grid_create(w, h);
ds_grid_clear(g, -1);

for(i = 0; i < nodeCount; i += 1)
{
    ny = ds_grid_get(nodes, NAV_NODE_Y, i);
    nx0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    nx1 = ds_grid_get(nodes, NAV_NODE_X1, i);
    ds_grid_set_region(g, nx0, ny, nx1, ny, i);
}

return g;
