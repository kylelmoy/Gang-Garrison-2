/// navClearanceBuild(solidGrid, w, h)
/// Dilates a mask-space solidity grid by the conservative character box
/// (NAV_BOX_W x NAV_BOX_H cells, which covers Heavy - see F24) and returns a new
/// ds_grid whose cells are 1 iff a character box anchored with its top-left corner
/// there is entirely clear of terrain.
///
/// Anchors whose box would run past the right or bottom edge are 0, so the caller
/// never has to bounds-check a node it got back from here.
///
/// Two O(w*h) sliding-window passes rather than the naive O(w*h*BOX_W*BOX_H):
/// pass 1 collapses each horizontal span, pass 2 collapses each vertical span.
///
/// Locals are cx/cy rather than x/y because GM8 treats a var that shadows a built-in
/// instance variable as a compilation error, and x, y and solid are all built-ins.
///
/// The caller owns the returned grid and must ds_grid_destroy it (GM8 has no GC).

var solidGrid, w, h, hfree, freeGrid, cx, cy, count, lastX, lastY, colSum;
solidGrid = argument0;
w = argument1;
h = argument2;

freeGrid = ds_grid_create(w, h);
ds_grid_clear(freeGrid, 0);

// A map smaller than the character box has no standable anchors at all.
if(w < NAV_BOX_W or h < NAV_BOX_H)
    return freeGrid;

lastX = w - NAV_BOX_W;
lastY = h - NAV_BOX_H;

// Pass 1: hfree is 1 where NAV_BOX_W cells starting at cx in row cy are all empty.
hfree = ds_grid_create(w, h);
ds_grid_clear(hfree, 0);

for(cy = 0; cy < h; cy += 1)
{
    // Fast path for a row with no terrain in it at all. Real maps are mostly open
    // air - gg_debug is 96% empty - and one native region write beats w interpreted
    // ds_grid_get/set pairs by a wide margin.
    if(ds_grid_get_sum(solidGrid, 0, cy, w - 1, cy) == 0)
    {
        ds_grid_set_region(hfree, 0, cy, lastX, cy, 1);
        continue;
    }

    count = 0;
    for(cx = 0; cx < NAV_BOX_W; cx += 1)
        count += ds_grid_get(solidGrid, cx, cy);

    for(cx = 0; cx <= lastX; cx += 1)
    {
        if(count == 0)
            ds_grid_set(hfree, cx, cy, 1);

        if(cx + NAV_BOX_W < w)
        {
            count -= ds_grid_get(solidGrid, cx, cy);
            count += ds_grid_get(solidGrid, cx + NAV_BOX_W, cy);
        }
    }
}

// Pass 2: the box fits where NAV_BOX_H consecutive rows of hfree are all set.
for(cx = 0; cx <= lastX; cx += 1)
{
    // A column with no horizontal clearance anywhere can never hold the box, and one
    // that is clear top to bottom always can - both settle in a single native sum
    // instead of h interpreted reads.
    colSum = ds_grid_get_sum(hfree, cx, 0, cx, h - 1);
    if(colSum == 0)
        continue;
    if(colSum == h)
    {
        ds_grid_set_region(freeGrid, cx, 0, cx, lastY, 1);
        continue;
    }

    count = 0;
    for(cy = 0; cy < NAV_BOX_H; cy += 1)
        count += ds_grid_get(hfree, cx, cy);

    for(cy = 0; cy <= lastY; cy += 1)
    {
        if(count == NAV_BOX_H)
            ds_grid_set(freeGrid, cx, cy, 1);

        if(cy + NAV_BOX_H < h)
        {
            count -= ds_grid_get(hfree, cx, cy);
            count += ds_grid_get(hfree, cx, cy + NAV_BOX_H);
        }
    }
}

ds_grid_destroy(hfree);
return freeGrid;
