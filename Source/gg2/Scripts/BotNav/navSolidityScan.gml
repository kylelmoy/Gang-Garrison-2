/// navSolidityScan(dummy, grid, w, fromY, toY)
/// Fills rows fromY .. toY-1 of a mask-space solidity grid from the map's real
/// collision geometry. Cells that are solid become 1; the grid must already be
/// cleared to 0.
///
/// Takes a row band rather than the whole map because a full scan is seconds of work
/// on a large map (cp_dirtbowl is 560k cells) and a multi-second blocking loop on a
/// live server stops GameServerBeginStep servicing sockets, which drops every
/// connected client (F31). The caller drives this a band at a time across frames.
///
/// ⚠️ Queries CustomMapO's sprite through a scale-1 CollisionDummy, NOT place_free or
/// collision_point_solid. Obstacle.solid is toggled on and off every single frame by
/// charSetSolids/charUnsetSolids, so the solid-based collision family reports open
/// space everywhere when called from anywhere but inside a character's own movement
/// step (F22) - which looks exactly like a working scan that found an empty map.
/// collision_point against an explicit instance is object-typed and so is immune.
///
/// dummy is an instance id, not the CollisionDummy object: the map builder's
/// compressWalkmask passes the object, which is only safe while exactly one exists.

var dummy, grid, w, fromY, toY, cx, cy;
dummy = argument0;
grid = argument1;
w = argument2;
fromY = argument3;
toY = argument4;

for(cy = fromY; cy < toY; cy += 1)
{
    for(cx = 0; cx < w; cx += 1)
    {
        if(collision_point(cx, cy, dummy, 1, 0))
            ds_grid_set(grid, cx, cy, 1);
    }
}
