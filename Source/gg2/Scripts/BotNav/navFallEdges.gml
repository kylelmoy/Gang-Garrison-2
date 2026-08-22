/// navFallEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, w, h, fromNode, toNode)
/// Appends fall edges for nodes fromNode .. toNode-1: walking off the end of a
/// surface and dropping to whatever is below.
///
/// One-way by construction. Falling off a ledge is not reversible without a jump, so
/// unlike a walk edge this emits a single direction, and the reverse link only exists
/// if a jump edge later supplies it.
///
/// The model is a straight vertical drop from the cell just past each end of the run,
/// and that column is stored on the edge (NAV_EDGE_TAKEOFF) so the follower knows which
/// end to walk off rather than guessing - see the comment at the navEdgeAdd call.
/// A character does keep its horizontal speed while falling, so this under-reports
/// reachability - a bot can in reality drift some distance sideways on the way down.
/// That is deliberate for now: every edge this emits is genuinely traversable, which
/// keeps the graph honest, and drifting falls are better added as part of the
/// trajectory work than guessed at here.
///
/// gateGrid may be -1. When it is not, the swept column is checked for gate cells and
/// the first one that is not the gate the fall started inside becomes the edge's gate
/// code, so a drop past a spawn gate is offered only to whoever may pass it. The sweep
/// is in anchor coordinates and the gate stamp is dilated to match (navGateStamp), so
/// a hit means the character's body would really be inside the gate on the way down.
///
/// Takes a node range so the build can spread it across frames like the other stages.

var nodes, nodeCount, freeGrid, nodeGrid, gateGrid, w, h, fromNode, toNode;
var i, side, cy, ax0, ax1, xEdge, yy, landed, maxY, dropped, cost, srcGate, arcGate, cellGate;
nodes = argument0;
nodeCount = argument1;
freeGrid = argument2;
nodeGrid = argument3;
gateGrid = argument4;
w = argument5;
h = argument6;
fromNode = argument7;
toNode = argument8;

maxY = h - NAV_BOX_H;

for(i = fromNode; i < toNode; i += 1)
{
    cy = ds_grid_get(nodes, NAV_NODE_Y, i);
    ax0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    ax1 = ds_grid_get(nodes, NAV_NODE_X1, i);
    srcGate = ds_grid_get(nodes, NAV_NODE_GATE, i);

    for(side = 0; side < 2; side += 1)
    {
        if(side == 0)
            xEdge = ax0 - 1;
        else
            xEdge = ax1 + 1;

        if(xEdge < 0 or xEdge > w - NAV_BOX_W)
            continue;

        // The character has to be able to occupy the column it steps into, at the
        // height it is standing at, or it is walking into a wall rather than off a
        // ledge.
        if(ds_grid_get(freeGrid, xEdge, cy) != 1)
            continue;

        // And there has to be nothing to stand on there, or it is not a ledge at all.
        // A run ends wherever clearance or ground ends, so the very next column along
        // is often another node at the same height - a platform butted against
        // terrain, or the far side of a gate cut. Sweeping down from cy + 1 walks
        // straight past it and credits the surface far below with a fall the
        // character would never take, when all it does is step across. navWalkEdges
        // already links these.
        if(ds_grid_get(nodeGrid, xEdge, cy) >= 0)
            continue;

        landed = -1;
        dropped = 0;
        arcGate = NAV_GATE_NONE;
        for(yy = cy + 1; yy <= min(maxY, cy + NAV_MAX_FALL); yy += 1)
        {
            // Something solid interrupts the drop before any surface does.
            if(ds_grid_get(freeGrid, xEdge, yy) != 1)
                break;

            // Kept out of the loop condition on purpose: GM8 evaluates both sides of
            // and/or unconditionally, so a folded "gateGrid < 0 or ..." guard would
            // still call ds_grid_get on -1 (F40).
            if(arcGate == NAV_GATE_NONE and gateGrid >= 0)
            {
                cellGate = ds_grid_get(gateGrid, xEdge, yy);
                if(cellGate != NAV_GATE_NONE and cellGate != srcGate)
                    arcGate = cellGate;
            }

            dropped += 1;
            landed = ds_grid_get(nodeGrid, xEdge, yy);
            if(landed >= 0)
                break;
        }

        if(landed >= 0 and landed != i)
        {
            // Falling is cheap horizontally but should not be preferred over a level
            // walk to the same place, so charge the drop distance.
            cost = max(1, dropped);
            if(arcGate == NAV_GATE_NONE)
                arcGate = ds_grid_get(nodes, NAV_NODE_GATE, landed);
            // xEdge is carried as the edge's takeoff column, and it is not a
            // decoration. Which END of the run this fall leaves from is not
            // recoverable from the two nodes alone: where the landing surface reaches
            // under both ends of the takeoff run - a platform sitting on a wider ledge
            // - "the column just past the run that is inside the landing node" is true
            // of both, and a follower guessing between them walks the wrong way about
            // half the time. Measured on ctf_avanti: n92 (a strip of platform with a
            // solid block against its right end) falls to n104 off its LEFT end, the
            // follower guessed right, walked into the block and wedged there until the
            // stuck detector took the edge away. Same shape at n94 -> n138. This is the
            // jump generator's F41 lesson (see navEdgeAdd) applied to falls: the build
            // knows the column, so the build says so.
            navEdgeAdd(i, landed, NAV_EDGE_FALL, 0, dropped, cost, arcGate, xEdge);
        }
    }
}
