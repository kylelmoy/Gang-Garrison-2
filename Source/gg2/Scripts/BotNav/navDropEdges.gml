/// navDropEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, w, h, fromNode, toNode)
/// Appends drop-through edges: standing on a DropdownPlatform and holding DOWN to
/// fall through it onto whatever is below.
///
/// Only nodes whose support is platform and nothing else qualify - NAV_NODE_FLAGS
/// carries that from navNodesExtract. A run with even one cell of terrain under it
/// cannot be dropped through, because the character would simply land on the terrain.
///
/// One-way, like a fall: getting back up needs a jump edge.
///
/// The drop is taken from the middle of the run rather than its ends, which is what
/// separates this from navFallEdges - a fall leaves past the edge of a surface, a
/// drop-through goes straight down through the middle of one. Holding DOWN disables
/// the platform entirely (both the standing test and the push-out, F24), so the
/// descent is an ordinary fall from there.
///
/// gateGrid may be -1, and is swept exactly as navFallEdges sweeps it - a drop-through
/// is an ordinary fall once the platform is disabled, so it meets gates the same way.
///
/// Takes a node range so the build can spread it across frames.

var nodes, nodeCount, freeGrid, nodeGrid, gateGrid, w, h, fromNode, toNode;
var i, cy, nx0, nx1, midX, yy, landed, maxY, dropped, cost, srcGate, arcGate, cellGate;
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
    if(ds_grid_get(nodes, NAV_NODE_FLAGS, i) != 1)
        continue;

    cy = ds_grid_get(nodes, NAV_NODE_Y, i);
    nx0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    nx1 = ds_grid_get(nodes, NAV_NODE_X1, i);
    midX = floor((nx0 + nx1) / 2);
    srcGate = ds_grid_get(nodes, NAV_NODE_GATE, i);

    landed = -1;
    dropped = 0;
    arcGate = NAV_GATE_NONE;
    for(yy = cy + 1; yy <= min(maxY, cy + NAV_MAX_FALL); yy += 1)
    {
        if(ds_grid_get(freeGrid, midX, yy) != 1)
            break;

        // Separate if rather than folded into a condition - see F40, and navFallEdges.
        if(arcGate == NAV_GATE_NONE and gateGrid >= 0)
        {
            cellGate = ds_grid_get(gateGrid, midX, yy);
            if(cellGate != NAV_GATE_NONE and cellGate != srcGate)
                arcGate = cellGate;
        }

        dropped += 1;
        landed = ds_grid_get(nodeGrid, midX, yy);
        if(landed >= 0)
            break;
    }

    if(landed >= 0 and landed != i)
    {
        cost = max(1, dropped);
        if(arcGate == NAV_GATE_NONE)
            arcGate = ds_grid_get(nodes, NAV_NODE_GATE, landed);
        navEdgeAdd(i, landed, NAV_EDGE_DROPTHROUGH, 0, dropped, cost, arcGate, -1);
    }
}
