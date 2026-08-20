/// navRowIndex(nodes, nodeCount, h)
/// Returns a ds_grid mapping each mask row to the index of the first node on it, or
/// -1 where the row holds none. Nodes are emitted sorted by y then x, so the nodes of
/// one row are contiguous and the caller can walk forward from here until the y
/// changes.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var nodes, nodeCount, h, rowStart, i;
nodes = argument0;
nodeCount = argument1;
h = argument2;

rowStart = ds_grid_create(1, h + 2);
ds_grid_clear(rowStart, -1);

// Backwards, so the lowest index on each row is what survives.
for(i = nodeCount - 1; i >= 0; i -= 1)
    ds_grid_set(rowStart, 0, ds_grid_get(nodes, NAV_NODE_Y, i), i);

return rowStart;
