/// botNodeSnap(wx, wy)
/// Resolves a world position onto the nav graph by searching *downward* from it for the
/// nearest node, and returns that node - or -1 if nothing is below it inside NAV_MAX_FALL.
///
/// Objective markers are the reason this exists. Map objects are not anchored the way a
/// Character is (F24), so a control point's sprite, a CaptureZone's top-left origin or a
/// generator's body can sit well above the floor a bot would actually stand on, by
/// different amounts on different maps - measured live, a guessed fixed offset happened to
/// work for a dropped Intelligence and was off by ~70px for a KothControlPoint's zone.
/// Searching down is the only version of this that generalises.
///
/// The search breaks on the *nearest* match, so widening NAV_MAX_FALL (M7's dkoth_atalia
/// fix took it 40 -> 150 rows) can only ever find something a shorter limit missed; it
/// cannot change an answer this already had.

var wx, wy, snapY, snapLimit, node;

wx = argument0;
wy = argument1;

if(!global.navReady)
    return -1;

snapLimit = wy + NAV_MAX_FALL * NAV_CELL_SIZE;
for(snapY = wy; snapY <= snapLimit; snapY += NAV_CELL_SIZE)
{
    node = navNodeFromWorld(wx, snapY);
    if(node >= 0)
        return node;
}

return -1;
