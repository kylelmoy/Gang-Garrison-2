/// navWalkEdges(nodes, nodeCount, h)
/// Appends walk edges to the open accumulator: runs one mask cell apart vertically
/// whose x-spans touch or overlap. GG2 gives a free 6px (exactly one cell) step-up
/// and step-down in characterHitObstacle (F24), so these need no jump and cost only
/// the horizontal travel.
///
/// Emitted in both directions - a step is symmetric, unlike a fall.
///
/// nodes must be sorted by y then x, which navNodesExtract guarantees, so only the
/// single row below each node has to be searched instead of all n.
///
/// Cost is the distance between run midpoints, which approximates travel while the
/// path follower does not yet track where along a surface it entered. Refine it
/// together with the entry-point sliding in milestone 5.

var nodes, nodeCount, h, rowStart, i, j, cy, ax0, ax1, bx0, bx1, cost, midA, midB;
nodes = argument0;
nodeCount = argument1;
h = argument2;

if(nodeCount <= 0)
    exit;

rowStart = navRowIndex(nodes, nodeCount, h);

for(i = 0; i < nodeCount; i += 1)
{
    cy = ds_grid_get(nodes, NAV_NODE_Y, i);
    ax0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    ax1 = ds_grid_get(nodes, NAV_NODE_X1, i);

    if(cy + 1 > h)
        continue;

    j = ds_grid_get(rowStart, 0, cy + 1);
    if(j < 0)
        continue;

    // Walk only the nodes actually on the row below.
    while(j < nodeCount and ds_grid_get(nodes, NAV_NODE_Y, j) == cy + 1)
    {
        bx0 = ds_grid_get(nodes, NAV_NODE_X0, j);
        bx1 = ds_grid_get(nodes, NAV_NODE_X1, j);

        // Touch or overlap: one cell of horizontal slack is the step itself.
        if(bx0 <= ax1 + 1 and ax0 <= bx1 + 1)
        {
            midA = (ax0 + ax1) / 2;
            midB = (bx0 + bx1) / 2;
            cost = max(1, abs(midA - midB));
            navEdgeAdd(i, j, NAV_EDGE_WALK, 0, 0, cost);
            navEdgeAdd(j, i, NAV_EDGE_WALK, 0, 0, cost);
        }

        j += 1;
    }
}

ds_grid_destroy(rowStart);
