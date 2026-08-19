/// navNodesExtract(freeGrid, solidGrid, w, h)
/// Run-length encodes the clearance grid into floor surfaces: one node per maximal
/// horizontal run of cells a character can stand on. Returns a ds_grid of
/// NAV_NODE_FIELDS columns by (number of nodes) rows, and sets global.navNodeCount.
///
/// Read the count from global.navNodeCount, not ds_grid_height - a graph with no
/// nodes still returns a one-row grid, because a zero-height ds_grid is not worth
/// relying on.
///
/// An anchor is standable when the character box fits there (freeGrid) and at least
/// one cell of the row directly under the box footprint is solid. "At least one"
/// rather than "all" is deliberate: a character part-way off a ledge is still
/// supported, and a node means "a bot can stand here", so the permissive test is the
/// correct one for reachability.
///
/// Nodes come out sorted by y then x, which navWalkEdges relies on to index rows.
///
/// Locals are cx/cy because x, y and solid are GM8 built-ins and shadowing one with
/// var is a compilation error.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var freeGrid, solidGrid, w, h, nodes, capacity, count, cx, cy, runStart, support, lastX, lastY, belowY;
freeGrid = argument0;
solidGrid = argument1;
w = argument2;
h = argument3;

capacity = 64;
nodes = ds_grid_create(NAV_NODE_FIELDS, capacity);
ds_grid_clear(nodes, 0);
count = 0;
global.navNodeCount = 0;

if(w < NAV_BOX_W or h < NAV_BOX_H)
    return nodes;

lastX = w - NAV_BOX_W;
lastY = h - NAV_BOX_H;

for(cy = 0; cy <= lastY; cy += 1)
{
    // The row of terrain the character's feet rest on. A box anchored at the very
    // bottom of the map has nothing under it and so is never standable.
    belowY = cy + NAV_BOX_H;
    if(belowY >= h)
        continue;

    // Running count of solid cells in the footprint window starting at cx.
    support = 0;
    for(cx = 0; cx < NAV_BOX_W; cx += 1)
        support += ds_grid_get(solidGrid, cx, belowY);

    cx = 0;
    while(cx <= lastX)
    {
        if(support > 0 and ds_grid_get(freeGrid, cx, cy) == 1)
        {
            // Walk the run out, carrying the support window along with it.
            runStart = cx;
            while(cx <= lastX and support > 0 and ds_grid_get(freeGrid, cx, cy) == 1)
            {
                if(cx + NAV_BOX_W < w)
                {
                    support -= ds_grid_get(solidGrid, cx, belowY);
                    support += ds_grid_get(solidGrid, cx + NAV_BOX_W, belowY);
                }
                cx += 1;
            }

            if(count >= capacity)
            {
                capacity *= 2;
                ds_grid_resize(nodes, NAV_NODE_FIELDS, capacity);
            }

            ds_grid_set(nodes, NAV_NODE_Y, count, cy);
            ds_grid_set(nodes, NAV_NODE_X0, count, runStart);
            ds_grid_set(nodes, NAV_NODE_X1, count, cx - 1);
            ds_grid_set(nodes, NAV_NODE_FLAGS, count, 0);
            count += 1;
        }
        else
        {
            if(cx + NAV_BOX_W < w)
            {
                support -= ds_grid_get(solidGrid, cx, belowY);
                support += ds_grid_get(solidGrid, cx + NAV_BOX_W, belowY);
            }
            cx += 1;
        }
    }
}

ds_grid_resize(nodes, NAV_NODE_FIELDS, max(count, 1));
global.navNodeCount = count;
return nodes;
