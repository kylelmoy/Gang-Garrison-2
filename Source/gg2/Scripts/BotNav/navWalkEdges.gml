/// navWalkEdges(nodes, nodeCount, h)
/// Appends walk edges to the open accumulator: runs one mask cell apart vertically
/// whose x-spans touch or overlap, plus runs on the very same row that touch. GG2
/// gives a free 6px (exactly one cell) step-up and step-down in characterHitObstacle
/// (F24), so a row-to-row step needs no jump and costs only the horizontal travel; a
/// same-row touch needs no step at all - it is one physically continuous floor that
/// navNodesExtract only split because the kind of support, or a door, changed at that
/// column (F39).
///
/// Row-to-row edges are emitted in both directions - a step is symmetric, unlike a
/// fall. Same-row edges are too, UNLESS one of the two touching nodes is a door cell
/// (NAV_NODE_DOOR from navNodesExtract): LeftDoor blocks only leftward crossing
/// (Character.events/Collision with LeftDoor.xml fires on hspeed < 0) and RightDoor
/// blocks only rightward, so the edge in the disallowed direction is simply not
/// added. A node's own door code applies to every same-row edge that touches it,
/// since the door sits at that x regardless of which neighbour is asking.
///
/// nodes must be sorted by y then x, which navNodesExtract guarantees, so only the
/// single row below each node, and the single next node in sort order, have to be
/// checked instead of all n.
///
/// Each edge carries the gate code of the node it arrives at, and nothing else. Walk
/// edges are the only ones that need no arc sampling to work that out: a walk crosses
/// exactly one node boundary, so the only gate it can meet is the one on the far side.
/// Taking the destination's code rather than either end's is also what lets a bot
/// walk *out* of a gate it may not walk into - a red bot that grabbed the intel inside
/// its own spawn, or anyone the setup gates just shut around, still gets edges out.
///
/// Cost is the distance between run midpoints for a step, or a flat 1 cell for a
/// same-row touch (they are, by construction, exactly adjacent). Both approximate
/// travel while the path follower does not yet track where along a surface it
/// entered. Refine it together with the entry-point sliding in milestone 5.

var nodes, nodeCount, h, rowStart, i, j, cy, ax0, ax1, bx0, bx1, cost, midA, midB, doorA, doorB, gateA, gateB;
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
            navEdgeAdd(i, j, NAV_EDGE_WALK, 0, 0, cost, ds_grid_get(nodes, NAV_NODE_GATE, j));
            navEdgeAdd(j, i, NAV_EDGE_WALK, 0, 0, cost, ds_grid_get(nodes, NAV_NODE_GATE, i));
        }

        j += 1;
    }
}

// Same-row touches: only ever the immediate next node in sort order, since two nodes
// on the same row cannot overlap and nothing else sorts between them.
for(i = 0; i < nodeCount - 1; i += 1)
{
    if(ds_grid_get(nodes, NAV_NODE_Y, i) != ds_grid_get(nodes, NAV_NODE_Y, i + 1))
        continue;

    ax1 = ds_grid_get(nodes, NAV_NODE_X1, i);
    bx0 = ds_grid_get(nodes, NAV_NODE_X0, i + 1);
    if(bx0 > ax1 + 1)
        continue;

    doorA = ds_grid_get(nodes, NAV_NODE_DOOR, i);
    doorB = ds_grid_get(nodes, NAV_NODE_DOOR, i + 1);
    gateA = ds_grid_get(nodes, NAV_NODE_GATE, i);
    gateB = ds_grid_get(nodes, NAV_NODE_GATE, i + 1);

    // i -> i+1 crosses rightward; i+1 -> i crosses leftward.
    if(doorA != NAV_DOOR_RIGHT and doorB != NAV_DOOR_RIGHT)
        navEdgeAdd(i, i + 1, NAV_EDGE_WALK, 0, 0, 1, gateB);
    if(doorA != NAV_DOOR_LEFT and doorB != NAV_DOOR_LEFT)
        navEdgeAdd(i + 1, i, NAV_EDGE_WALK, 0, 0, 1, gateA);
}

ds_grid_destroy(rowStart);
