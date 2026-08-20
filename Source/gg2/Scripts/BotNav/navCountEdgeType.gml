/// navCountEdgeType(edges, edgeCount, type)
/// Returns how many edges in the list are of the given NAV_EDGE_* type.
///
/// Asserting on the mix of edge types rather than a single total is what keeps the
/// nav tests meaningful as generators are added: a bare count says nothing about
/// whether the right kind of connection was made, and would have to be rewritten
/// every time a new edge type starts contributing.

var edges, edgeCount, type, i, n;
edges = argument0;
edgeCount = argument1;
type = argument2;

n = 0;
for(i = 0; i < edgeCount; i += 1)
{
    if(ds_grid_get(edges, NAV_EDGE_TYPE, i) == type)
        n += 1;
}

return n;
