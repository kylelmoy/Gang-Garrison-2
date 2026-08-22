/// navClearanceBuild(solidGrid, w, h)
/// Dilates a mask-space solidity grid by the character box (NAV_BOX_W x NAV_BOX_H cells)
/// and returns a new ds_grid whose cells are 1 iff a character box anchored with its
/// top-left corner there is entirely clear of terrain.
///
/// ⚠️ **The box is the real body, measured, not a safe-looking round number.** It was
/// NAV_BOX_H = 7 (42px) on the grounds that it "covers Heavy". It over-covered Heavy by a
/// whole cell: the class sprites carry MANUAL rectangle masks and the tallest of them,
/// Heavy, is 19 x 36px (Scout 13x34, Soldier 13x32, Pyro 15x30). Six rows is 36px, which
/// is exactly Heavy, so 7 modelled a character taller than any that exists and every gap
/// between 36 and 41px high read as solid rock.
///
/// That is not a rounding detail. Measured across the 21 shipped maps it walled off 370
/// floor cells a player walks through without noticing - on koth_corinth, 84px of
/// continuous floor at one height that the graph priced at 187 cells to go around, and on
/// arena_montane a 36px gap it priced at 639. Both maps were reported as "the bots go a
/// stupid way round" before anyone measured the sprite.
///
/// The width is left at 4 cells and that is correct: 19px unaligned spans four 6px cells.
///
/// ⚠️ What six rows is exactly right for is STANDING. GG2 rests a character with its feet
/// on a surface, so a standing body is row-aligned and occupies exactly six rows. A body
/// in mid-air is not aligned and touches seven, so arc clearance sampled against this grid
/// is optimistic by up to one row - the arc sampler already rounds its row, which blurs it
/// by half a row in both directions anyway. Watch the jump-edge counts if that ever starts
/// producing arcs the follower cannot fly; the fix would be a second, taller grid for arcs
/// rather than making standing conservative again.
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
