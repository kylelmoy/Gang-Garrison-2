/// navJumpHeight(t, capHeight)
/// How far above the takeoff row a jumping character is after t ticks, in world px,
/// positive upward. The single definition of GG2's jump arc; everything that samples
/// one goes through here.
///
/// `capHeight` is how high the character is allowed to get before something stops it -
/// a ceiling, an overhang, the underside of the platform it is climbing onto. Pass
/// anything at or above the apex (57.4px) for "nothing in the way", which is the
/// ordinary case and reproduces the plain arc exactly.
///
/// Below the cap this is the textbook p(t) = v0*t - g*t*t/2, and that is exact rather
/// than approximate: Character's Step event adds half the tick's gravity, moves, then
/// adds the other half, which is midpoint integration, and midpoint integration of a
/// constant acceleration lands on the continuous curve at every integer tick. Checked
/// against a tick-by-tick simulation of the engine's own update: the two agree to
/// 1e-13 px over thirty ticks.
///
/// Above it the character has hit its head. GG2 zeroes vspeed on a ceiling and lets
/// gravity take over, so the arc resumes as a fall from rest at that height - and the
/// same midpoint integration makes *that* exact too, at g*d*d/2 for d ticks since the
/// bonk. A bonk is not a failure and must not be treated as one: every jump in this
/// game rises 57px whether the map has room for it or not, so refusing to believe in
/// jumps under low ceilings costs real edges. On koth_valley it cost the whole route
/// out of the valley floor - the step up is under an overhang eight cells up, the
/// character's head clips it near the top of the arc, and it lands on the step anyway.
///
/// ⚠️ Past terminal velocity the fall stops accelerating: Step.xml clamps vspeed at
/// NAV_JUMP_TERM_VY = 10 px/tick, which a fall from rest reaches after 16.7 ticks and
/// 83px. A 900px drop - NAV_MAX_FALL, the deepest the graph considers (M7 tier 2:
/// dkoth_atalia's spawn rooms sit a genuine 846px above the ground and nothing shorter
/// covers the intended route) - really takes 98.3 ticks and the unclamped parabola
/// says 54.8, a 44% underestimate that becomes a much larger overestimate of the speed
/// the arc needs and lands the bot well past its target. The gap only widens with
/// NAV_MAX_FALL, which is exactly why this clamp cannot be skipped as a simplification.

var t, capHeight, apexHeight, tUp, d, dTerm, drop;
t = argument0;
capHeight = argument1;

apexHeight = NAV_JUMP_V0 * NAV_JUMP_V0 / (2 * NAV_JUMP_GRAVITY);
if(capHeight > apexHeight)
    capHeight = apexHeight;
if(capHeight < 0)
    capHeight = 0;

// When the rise ends: where the arc meets the cap going up, which is the apex itself
// when nothing is in the way.
tUp = (NAV_JUMP_V0 - sqrt(max(0, NAV_JUMP_V0 * NAV_JUMP_V0 - 2 * NAV_JUMP_GRAVITY * capHeight)))
      / NAV_JUMP_GRAVITY;

if(t <= tUp)
    return NAV_JUMP_V0 * t - NAV_JUMP_GRAVITY * t * t / 2;

d = t - tUp;
dTerm = NAV_JUMP_TERM_VY / NAV_JUMP_GRAVITY;
if(d <= dTerm)
    drop = NAV_JUMP_GRAVITY * d * d / 2;
else
    drop = NAV_JUMP_GRAVITY * dTerm * dTerm / 2 + NAV_JUMP_TERM_VY * (d - dTerm);

return capHeight - drop;
