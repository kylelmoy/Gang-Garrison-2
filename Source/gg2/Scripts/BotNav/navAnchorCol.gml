/// navAnchorCol(worldX)
/// The nav anchor column a character standing at world x occupies.
///
/// A node's x-span is in anchor columns - the *left edge* of the NAV_BOX_W cell wide
/// body box - while a Character's x is the centre of its sprite, so the two are half a
/// box apart. Getting this wrong is invisible on a wide surface and quietly wrong on a
/// narrow one: a two-cell ledge is missed entirely, and a path follower steers to a
/// point two cells off the node it thinks it is heading for.
///
/// Paired with navColWorldX, which goes the other way. Nothing should convert between
/// the two by hand.

return floor(argument0 / NAV_CELL_SIZE) - (NAV_BOX_W div 2);
