/// botFallPredict(ty, tvy, t, tfloor)
/// Where a Character at world y `ty` moving at `tvy` px/tick vertically will be `t`
/// ticks from now: GG2's own gravity, clamped at terminal velocity, then clamped again
/// at the floor its feet would land on.
///
/// Extracted verbatim from botAimLead, which had it written out twice - once inside the
/// iteration and once again to re-derive the aim point at the settled t - and now has a
/// second caller in botStabWindow, which needs the same prediction for a different
/// question. Nothing about the arithmetic changed in the extraction.
///
/// Why it is not `ty + tvy*t`. A Character falls under NAV_JUMP_GRAVITY (0.6 px/tick^2)
/// to a terminal NAV_JUMP_TERM_VY (10), so a linear-only prediction has a target that
/// jumped a moment ago rising at its launch speed forever - which is a bot firing high
/// into the air at anyone airborne. This is the same closed form the graph generator's
/// navJumpHeight uses (gg2-nav-gen/src/jump.js),
/// generalised from a standing jump to an arbitrary starting tvy, and it matches a
/// tick-by-tick simulation of Character's own midpoint gravity to a few hundredths of a
/// pixel.
///
/// tfloor is the world y the target cannot be predicted to fall past - the mirror image
/// of the same bug, a long flight predicting a falling target through the ground it
/// would already have landed on. Pass 100000 (no map is that tall) when none is known;
/// botNodeSnap is where callers get a real one.
///
/// A grounded target that is not moving vertically (tvy = 0, tfloor = ty) clamps on the
/// very first tick and this returns ty exactly, so nothing changes for a target standing
/// still.

var ty, tvy, t, tfloor, tClamp, tyPred;

ty = argument0;
tvy = argument1;
t = argument2;
tfloor = argument3;

if(tvy < NAV_JUMP_TERM_VY)
    tClamp = (NAV_JUMP_TERM_VY - tvy) / NAV_JUMP_GRAVITY;
else
    tClamp = 0;

if(t <= tClamp)
    tyPred = ty + tvy * t + NAV_JUMP_GRAVITY * t * t / 2;
else
    tyPred = ty + tvy * tClamp + NAV_JUMP_GRAVITY * tClamp * tClamp / 2
             + NAV_JUMP_TERM_VY * (t - tClamp);

if(tyPred > tfloor)
    tyPred = tfloor;

return tyPred;
