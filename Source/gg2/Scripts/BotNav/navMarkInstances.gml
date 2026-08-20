/// navMarkInstances(solidGrid, platformGrid, lethalGrid, doorGrid, w, h)
/// Stamps the map objects that are not part of the walkmask into the nav grids.
///
/// The walkmask is only the terrain. PlayerWalls, drop-through platforms, the lethal
/// volumes and the one-way doors are ordinary instances, so a graph built from the
/// walkmask alone routes bots straight through player walls, treats every platform as
/// thin air, happily paths across a killbox, and walks LeftDoor/RightDoor as freely
/// passable in both directions when really only one way is open.
///
///   solidGrid     gains PlayerWall (and PlayerWallHorizontal, its child) - static,
///                 always blocking, so it belongs in the terrain grid.
///   platformGrid  gains DropdownPlatform (and MovingPlatform, its child), which is
///                 solid from above only. It must NOT go in solidGrid: a character
///                 jumps up through one freely, so treating it as terrain would wall
///                 off everything underneath.
///   lethalGrid    gains KillBox, PitFall and FragBox, which set hp = 0 on contact.
///   doorGrid      gains LeftDoor (NAV_DOOR_LEFT) and RightDoor (NAV_DOOR_RIGHT).
///                 Unlike the others this is not a solidity fact - a door blocks only
///                 one direction of horizontal travel through it
///                 (Character.events/Collision with LeftDoor.xml checks hspeed's
///                 sign) - so navNodesExtract uses it to cut a node boundary rather
///                 than to remove standability, and navWalkEdges reads it back to
///                 suppress the disallowed direction across that boundary.
///
/// Gates are deliberately absent. TeamGate, IntelGate and ControlPointSetupGate are
/// per-frame conditional solids - your own team's gate is passable, an IntelGate only
/// blocks a carrier - so baking them into the grid would bake in one team's view of
/// the map (F26). They belong in edge costs evaluated at query time.
///
/// Marks each instance's bounding box rather than testing per cell: there are dozens
/// of instances against up to 560,000 cells, and ds_grid_set_region is native.
///
/// ⚠️ MovingPlatform is stamped where it happens to be sitting when the graph is
/// built. A moving platform therefore reads as a static ledge at one end of its
/// travel. Correct handling needs a time-varying edge, which nothing here models yet.

var solidGrid, platformGrid, lethalGrid, doorGrid, w, h;
solidGrid = argument0;
platformGrid = argument1;
lethalGrid = argument2;
doorGrid = argument3;
w = argument4;
h = argument5;

with(PlayerWall)
{
    if(solidGrid >= 0)
    {
        ds_grid_set_region(solidGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), 1);
    }
}

with(DropdownPlatform)
{
    if(platformGrid >= 0)
    {
        ds_grid_set_region(platformGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), 1);
    }
}

with(KillBox)
{
    if(lethalGrid >= 0)
    {
        ds_grid_set_region(lethalGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), 1);
    }
}

with(PitFall)
{
    if(lethalGrid >= 0)
    {
        ds_grid_set_region(lethalGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), 1);
    }
}

with(FragBox)
{
    if(lethalGrid >= 0)
    {
        ds_grid_set_region(lethalGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), 1);
    }
}

with(LeftDoor)
{
    if(doorGrid >= 0)
    {
        ds_grid_set_region(doorGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), NAV_DOOR_LEFT);
    }
}

with(RightDoor)
{
    if(doorGrid >= 0)
    {
        ds_grid_set_region(doorGrid,
            max(0, floor(bbox_left / NAV_CELL_SIZE)),
            max(0, floor(bbox_top / NAV_CELL_SIZE)),
            min(w - 1, floor(bbox_right / NAV_CELL_SIZE)),
            min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE)), NAV_DOOR_RIGHT);
    }
}
