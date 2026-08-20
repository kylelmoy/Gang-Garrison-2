/// navColWorldX(col)
/// The world x a character stands at when its nav anchor is in this column - the
/// centre of the body box, which is where Character's own x sits.
///
/// The inverse of navAnchorCol, to a cell's rounding.

return argument0 * NAV_CELL_SIZE + NAV_BOX_W * NAV_CELL_SIZE / 2;
