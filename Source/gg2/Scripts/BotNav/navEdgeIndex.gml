/// navEdgeIndex(edges, edgeCount, nodeCount)
/// Returns a ds_grid of 2 columns by nodeCount rows holding, for each node, the index
/// of its first outgoing edge and how many it has. Edges must already be sorted by
/// NAV_EDGE_FROM, which navEdgesBuild guarantees.
///
/// Without this, every A* expansion is a scan of the whole edge list; with it, a
/// node's neighbours are a contiguous range. On cp_dirtbowl that is the difference
/// between 1,298 reads per expansion and about two.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var edges, edgeCount, nodeCount, idx, i, from;
edges = argument0;
edgeCount = argument1;
nodeCount = argument2;

idx = ds_grid_create(2, max(nodeCount, 1));
ds_grid_clear(idx, 0);

// Start defaults to -1 so "no outgoing edges" is unambiguous rather than looking like
// "starts at edge 0".
for(i = 0; i < nodeCount; i += 1)
    ds_grid_set(idx, 0, i, -1);

for(i = 0; i < edgeCount; i += 1)
{
    from = ds_grid_get(edges, NAV_EDGE_FROM, i);
    if(from < 0 or from >= nodeCount)
        continue;

    if(ds_grid_get(idx, 0, from) < 0)
        ds_grid_set(idx, 0, from, i);
    ds_grid_set(idx, 1, from, ds_grid_get(idx, 1, from) + 1);
}

return idx;
