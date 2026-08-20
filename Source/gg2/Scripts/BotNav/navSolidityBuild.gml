/// navSolidityBuild()
/// Builds the whole mask-space solidity grid for the current map in one go and
/// returns it, setting global.navMaskW and global.navMaskH to its dimensions.
///
/// This is the unchunked convenience path: correct for gg_debug (120x64, 7,680 cells)
/// and fine for a test, but NOT what a live server should call on a large map - see
/// navSolidityScan for why. The chunked build state machine uses navSolidityScan
/// directly and shares this script's dummy setup.
///
/// The dummy wears global.CustomMapCollisionSprite at scale 1 rather than the scale 6
/// CustomMapO wears, so queries are in mask cells and cost no coordinate transform
/// (F23). One mask cell is 6 world px, always.
///
/// Returns -1 if no map collision sprite exists yet, so a caller that runs before
/// CustomMapProcessLevelData gets a checkable answer instead of a dialog.
///
/// The caller owns the returned grid and must ds_grid_destroy it.

var dummy, grid, w, h;

global.navMaskW = 0;
global.navMaskH = 0;

if(!variable_global_exists("CustomMapCollisionSprite"))
    return -1;
if(!sprite_exists(global.CustomMapCollisionSprite))
    return -1;

w = sprite_get_width(global.CustomMapCollisionSprite);
h = sprite_get_height(global.CustomMapCollisionSprite);

dummy = instance_create(0, 0, CollisionDummy);
dummy.sprite_index = global.CustomMapCollisionSprite;
dummy.image_xscale = 1;
dummy.image_yscale = 1;
dummy.visible = false;

grid = ds_grid_create(w, h);
ds_grid_clear(grid, 0);

navSolidityScan(dummy, grid, w, 0, h);
navMarkInstances(grid, -1, -1, w, h);

with(dummy)
    instance_destroy();

global.navMaskW = w;
global.navMaskH = h;
return grid;
