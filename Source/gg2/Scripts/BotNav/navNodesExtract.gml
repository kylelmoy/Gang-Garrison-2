/// navNodesExtract(freeGrid, solidGrid, platformGrid, lethalGrid, w, h)
/// Run-length encodes the clearance grid into floor surfaces: one node per maximal
/// horizontal run of cells a character can stand on. Returns a ds_grid of
/// NAV_NODE_FIELDS columns by (number of nodes) rows, and sets global.navNodeCount.
///
/// platformGrid and lethalGrid may be -1 when a caller has neither - the unit tests
/// build bare terrain and pass -1 for both.
///
/// Read the count from global.navNodeCount, not ds_grid_height - a graph with no
/// nodes still returns a one-row grid, because a zero-height ds_grid is not worth
/// relying on.
///
/// An anchor is standable when the character box fits there (freeGrid) and at least
/// one cell of the row directly under the box footprint supports it. "At least one"
/// rather than "all" is deliberate: a character part-way off a ledge is still
/// supported, and a node means "a bot can stand here", so the permissive test is the
/// correct one for reachability.
///
/// Support comes from terrain or from a drop-through platform, which is solid from
/// above and is exactly as standable as ground. Whether the support is platform-only
/// is recorded in the node's flags, because that is what makes a drop-through edge
/// possible - a bot can hold DOWN and fall through a platform, and cannot do that
/// through terrain.
///
/// A run is cut wherever the support row is lethal. KillBox, PitFall and FragBox set
/// hp = 0 on contact, so a node there is not somewhere a bot may stand; it is a place
/// the graph must never offer.
///
/// Nodes come out sorted by y then x, which navWalkEdges relies on to index rows.

var freeGrid, solidGrid, platformGrid, lethalGrid, w, h;
var nodes, capacity, count, cx, cy, runStart, support, psupport, lethal, lastX, lastY, belowY, platformOnly, standable;
freeGrid = argument0;
solidGrid = argument1;
platformGrid = argument2;
lethalGrid = argument3;
w = argument4;
h = argument5;

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

    // Running counts of what is under the footprint window starting at cx.
    support = 0;
    psupport = 0;
    lethal = 0;
    for(cx = 0; cx < NAV_BOX_W; cx += 1)
    {
        support += ds_grid_get(solidGrid, cx, belowY);
        if(platformGrid >= 0)
            psupport += ds_grid_get(platformGrid, cx, belowY);
        if(lethalGrid >= 0)
            lethal += ds_grid_get(lethalGrid, cx, belowY);
    }

    cx = 0;
    while(cx <= lastX)
    {
        standable = (lethal == 0) and (support > 0 or psupport > 0) and ds_grid_get(freeGrid, cx, cy) == 1;

        if(standable)
        {
            runStart = cx;
            platformOnly = (support == 0 and psupport > 0);

            // The run is also cut where the kind of support changes. A stretch that is
            // half ground and half platform is one continuous walkable surface, but
            // only the platform half can be dropped through - so keeping them in one
            // node would either invent a drop-through over solid ground or lose the
            // real one. Splitting them keeps every edge honest.
            while(cx <= lastX and standable and ((support == 0 and psupport > 0) == platformOnly))
            {
                if(cx + NAV_BOX_W < w)
                {
                    support -= ds_grid_get(solidGrid, cx, belowY);
                    support += ds_grid_get(solidGrid, cx + NAV_BOX_W, belowY);
                    if(platformGrid >= 0)
                    {
                        psupport -= ds_grid_get(platformGrid, cx, belowY);
                        psupport += ds_grid_get(platformGrid, cx + NAV_BOX_W, belowY);
                    }
                    if(lethalGrid >= 0)
                    {
                        lethal -= ds_grid_get(lethalGrid, cx, belowY);
                        lethal += ds_grid_get(lethalGrid, cx + NAV_BOX_W, belowY);
                    }
                }
                cx += 1;
                standable = (cx <= lastX) and (lethal == 0) and (support > 0 or psupport > 0) and ds_grid_get(freeGrid, cx, cy) == 1;
            }

            if(count >= capacity)
            {
                capacity *= 2;
                ds_grid_resize(nodes, NAV_NODE_FIELDS, capacity);
            }

            ds_grid_set(nodes, NAV_NODE_Y, count, cy);
            ds_grid_set(nodes, NAV_NODE_X0, count, runStart);
            ds_grid_set(nodes, NAV_NODE_X1, count, cx - 1);
            ds_grid_set(nodes, NAV_NODE_FLAGS, count, platformOnly);
            count += 1;
        }
        else
        {
            if(cx + NAV_BOX_W < w)
            {
                support -= ds_grid_get(solidGrid, cx, belowY);
                support += ds_grid_get(solidGrid, cx + NAV_BOX_W, belowY);
                if(platformGrid >= 0)
                {
                    psupport -= ds_grid_get(platformGrid, cx, belowY);
                    psupport += ds_grid_get(platformGrid, cx + NAV_BOX_W, belowY);
                }
                if(lethalGrid >= 0)
                {
                    lethal -= ds_grid_get(lethalGrid, cx, belowY);
                    lethal += ds_grid_get(lethalGrid, cx + NAV_BOX_W, belowY);
                }
            }
            cx += 1;
        }
    }
}

ds_grid_resize(nodes, NAV_NODE_FIELDS, max(count, 1));
global.navNodeCount = count;
return nodes;
