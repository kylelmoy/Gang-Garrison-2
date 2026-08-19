/// navWalkEdges(nodes, nodeCount, h)
/// Connects floor surfaces a character can simply walk between: runs one mask cell
/// apart vertically whose x-spans touch or overlap. GG2 gives a free 6px (exactly one
/// cell) step-up and step-down in characterHitObstacle (F24), so these cost nothing
/// beyond the horizontal travel and need no jump.
///
/// Returns a ds_grid of NAV_EDGE_FIELDS columns by (number of edges) rows and sets
/// global.navEdgeCount. Edges are directed and emitted in both directions, because
/// later edge types (LeftDoor/RightDoor, drop-throughs) are genuinely one-way and the
/// path follower should not have to special-case which list it is reading.
///
/// nodes must be sorted by y then x - navNodesExtract emits them that way - so that
/// only the single row below each node has to be searched instead of all n.
///
/// Cost is the distance between run midpoints, which approximates travel while the
/// path follower does not yet track where along a surface it entered. Refine this
/// together with the entry-point sliding in milestone 5.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

/// Locals avoid x/y, which are GM8 built-in instance variables - shadowing one with
/// var is a compilation error, not a warning.

var nodes, nodeCount, h, edges, capacity, count, rowStart, i, j, cy, ax0, ax1, bx0, bx1, cost, midA, midB;
nodes = argument0;
nodeCount = argument1;
h = argument2;

capacity = 64;
edges = ds_grid_create(NAV_EDGE_FIELDS, capacity);
ds_grid_clear(edges, 0);
count = 0;
global.navEdgeCount = 0;

if(nodeCount <= 0)
    return edges;

// Index of the first node on each row, or -1. Nodes are y-sorted, so one pass fills it.
rowStart = ds_grid_create(1, h + 2);
ds_grid_clear(rowStart, -1);
for(i = nodeCount - 1; i >= 0; i -= 1)
    ds_grid_set(rowStart, 0, ds_grid_get(nodes, NAV_NODE_Y, i), i);

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

    // Walk only the run of nodes actually on row y+1.
    while(j < nodeCount and ds_grid_get(nodes, NAV_NODE_Y, j) == cy + 1)
    {
        bx0 = ds_grid_get(nodes, NAV_NODE_X0, j);
        bx1 = ds_grid_get(nodes, NAV_NODE_X1, j);

        // Touch or overlap: one cell of horizontal slack is the step-up itself.
        if(bx0 <= ax1 + 1 and ax0 <= bx1 + 1)
        {
            midA = (ax0 + ax1) / 2;
            midB = (bx0 + bx1) / 2;
            cost = max(1, abs(midA - midB));

            if(count + 2 > capacity)
            {
                capacity *= 2;
                ds_grid_resize(edges, NAV_EDGE_FIELDS, capacity);
            }

            ds_grid_set(edges, NAV_EDGE_FROM, count, i);
            ds_grid_set(edges, NAV_EDGE_TO, count, j);
            ds_grid_set(edges, NAV_EDGE_TYPE, count, NAV_EDGE_WALK);
            ds_grid_set(edges, NAV_EDGE_BUCKET, count, 0);
            ds_grid_set(edges, NAV_EDGE_TICKS, count, 0);
            ds_grid_set(edges, NAV_EDGE_COST, count, cost);
            count += 1;

            ds_grid_set(edges, NAV_EDGE_FROM, count, j);
            ds_grid_set(edges, NAV_EDGE_TO, count, i);
            ds_grid_set(edges, NAV_EDGE_TYPE, count, NAV_EDGE_WALK);
            ds_grid_set(edges, NAV_EDGE_BUCKET, count, 0);
            ds_grid_set(edges, NAV_EDGE_TICKS, count, 0);
            ds_grid_set(edges, NAV_EDGE_COST, count, cost);
            count += 1;
        }

        j += 1;
    }
}

ds_grid_destroy(rowStart);
ds_grid_resize(edges, NAV_EDGE_FIELDS, max(count, 1));
global.navEdgeCount = count;
return edges;
