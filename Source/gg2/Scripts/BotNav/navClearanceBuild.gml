/// navClearanceBuild(solidGrid, w, h)
/// Dilates a mask-space solidity grid by the conservative character box
/// (NAV_BOX_W x NAV_BOX_H cells, which covers Heavy - see F24) and returns a new
/// ds_grid whose cells are 1 iff a character box anchored with its top-left corner
/// there is entirely clear of terrain.
///
/// Anchors whose box would run past the right or bottom edge are 0, so the caller
/// never has to bounds-check a node it got back from here.
///
/// This is the unchunked convenience path, and is what the unit tests exercise. A
/// live server builds the same thing a band at a time through navClearanceRows and
/// navClearanceCols, because the whole pass is ~1s on the largest shipped map and a
/// blocking loop that long stops socket servicing and drops clients (F31/F36).
///
/// The caller owns the returned grid and must ds_grid_destroy it (GM8 has no GC).

var solidGrid, w, h, hfree, freeGrid;
solidGrid = argument0;
w = argument1;
h = argument2;

freeGrid = ds_grid_create(w, h);
ds_grid_clear(freeGrid, 0);

// A map smaller than the character box has no standable anchors at all.
if(w < NAV_BOX_W or h < NAV_BOX_H)
    return freeGrid;

hfree = ds_grid_create(w, h);
ds_grid_clear(hfree, 0);

navClearanceRows(solidGrid, hfree, w, h, 0, h);
navClearanceCols(hfree, freeGrid, w, h, 0, w - NAV_BOX_W + 1);

ds_grid_destroy(hfree);
return freeGrid;
