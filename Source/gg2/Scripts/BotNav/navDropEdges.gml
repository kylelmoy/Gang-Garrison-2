/// navDropEdges(nodes, nodeCount, freeGrid, nodeGrid, w, h, fromNode, toNode)
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
/// Takes a node range so the build can spread it across frames.

var nodes, nodeCount, freeGrid, nodeGrid, w, h, fromNode, toNode;
var i, cy, nx0, nx1, midX, yy, landed, maxY, dropped, cost;
nodes = argument0;
nodeCount = argument1;
freeGrid = argument2;
nodeGrid = argument3;
w = argument4;
h = argument5;
fromNode = argument6;
toNode = argument7;

maxY = h - NAV_BOX_H;

for(i = fromNode; i < toNode; i += 1)
{
    if(ds_grid_get(nodes, NAV_NODE_FLAGS, i) != 1)
        continue;

    cy = ds_grid_get(nodes, NAV_NODE_Y, i);
    nx0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    nx1 = ds_grid_get(nodes, NAV_NODE_X1, i);
    midX = floor((nx0 + nx1) / 2);

    landed = -1;
    dropped = 0;
    for(yy = cy + 1; yy <= min(maxY, cy + NAV_MAX_FALL); yy += 1)
    {
        if(ds_grid_get(freeGrid, midX, yy) != 1)
            break;

        dropped += 1;
        landed = ds_grid_get(nodeGrid, midX, yy);
        if(landed >= 0)
            break;
    }

    if(landed >= 0 and landed != i)
    {
        cost = max(1, dropped);
        navEdgeAdd(i, landed, NAV_EDGE_DROPTHROUGH, 0, dropped, cost);
    }
}
