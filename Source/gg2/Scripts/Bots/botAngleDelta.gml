/// botAngleDelta(a, b)
/// The shortest signed turn from angle b to angle a, in degrees, in (-180, 180].
/// Positive is counter-clockwise, matching point_direction and aimDirection.
///
/// GameMaker Studio has angle_difference for this. **Game Maker 8 does not**, and it is
/// exactly the kind of function that lints as unknown rather than silently doing
/// something else, so this is the whole substitute.
///
///     d = ((a - b) mod 360 + 540) mod 360 - 180
///
/// The doubled mod is not redundant. GM8's mod takes the sign of its dividend, so
/// (a - b) mod 360 lands anywhere in (-360, 360); adding 540 makes it strictly positive
/// before the second mod, which is what makes the result well defined for a negative
/// difference. Half of a turn comes back as -180 rather than 180, which is arbitrary but
/// harmless: every caller here is either taking its absolute value or its sign.

var a, b, d;

a = argument0;
b = argument1;

d = (a - b) mod 360;

return ((d + 540) mod 360) - 180;
