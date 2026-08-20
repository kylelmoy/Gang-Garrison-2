/// navEdgesSortByFrom(edges, edgeCount, nodeCount)
/// Returns a new edge grid with the rows grouped by their from-node, and sets
/// global.navEdgeCount to how many survived. The input grid is left alone; the caller
/// destroys whichever it no longer wants.
///
/// A counting sort rather than a comparison sort, because GM8 has no ds_grid_sort at
/// all (it is a GameMaker Studio function) and the key is already a small dense
/// integer - so this is O(E + N) and needs no comparisons.
///
/// Grouping is what lets navEdgeIndex describe a node's neighbours as a contiguous
/// range, which is the difference between A* reading two edges per expansion and
/// reading the entire list.
///
/// Edges naming a node outside the graph are dropped rather than carried, since they
/// could only come from a corrupt build and would index off the end during a search.

var edges, edgeCount, nodeCount, counts, cursor, out, i, from, dst, written;
edges = argument0;
edgeCount = argument1;
nodeCount = argument2;

out = ds_grid_create(NAV_EDGE_FIELDS, max(edgeCount, 1));
ds_grid_clear(out, 0);

if(edgeCount <= 0 or nodeCount <= 0)
{
    global.navEdgeCount = 0;
    return out;
}

counts = ds_grid_create(1, nodeCount + 1);
ds_grid_clear(counts, 0);

for(i = 0; i < edgeCount; i += 1)
{
    from = ds_grid_get(edges, NAV_EDGE_FROM, i);
    if(from >= 0 and from < nodeCount)
        ds_grid_set(counts, 0, from, ds_grid_get(counts, 0, from) + 1);
}

// Running start offset per node.
cursor = ds_grid_create(1, nodeCount + 1);
ds_grid_clear(cursor, 0);
written = 0;
for(i = 0; i < nodeCount; i += 1)
{
    ds_grid_set(cursor, 0, i, written);
    written += ds_grid_get(counts, 0, i);
}

for(i = 0; i < edgeCount; i += 1)
{
    from = ds_grid_get(edges, NAV_EDGE_FROM, i);
    if(from < 0 or from >= nodeCount)
        continue;

    dst = ds_grid_get(cursor, 0, from);
    ds_grid_set(cursor, 0, from, dst + 1);
    ds_grid_set_grid_region(out, edges, 0, i, NAV_EDGE_FIELDS - 1, i, 0, dst);
}

ds_grid_destroy(counts);
ds_grid_destroy(cursor);

global.navEdgeCount = written;
return out;
