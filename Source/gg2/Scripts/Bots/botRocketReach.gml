/// botRocketReach(char, needVx, flightTicks, v0)
/// How far along a ROCKET-JUMP arc this character would actually get, in world px, if it
/// left the takeoff column carrying v0 px/tick along the jump and then flew the arc the
/// way botPathKeys' in-flight tracker flies it.
///
/// botJumpReach beside this answers the same question for every other edge kind, and the
/// two must not be merged: they differ in both terms of the motion law, not one.
///
/// Character's Begin Step sets controlFactor and frictionFactor from moveStatus, and
/// moveStatus 1 - "rocketing/mining myself", which is exactly what a rocket jump is - is a
/// different row of that switch from the default:
///
///     case 1:   controlFactor = 0.65;   frictionFactor = 1;
///     default:  controlFactor = baseControl (0.85);   frictionFactor = baseFriction (1.15);
///
/// WARNING: frictionFactor 1 means `hspeed /= 1`. Horizontal speed does not bleed AT ALL for the
/// whole airborne period, which is around 69 ticks on a full-height rocket jump. That cuts
/// both ways and neither way is the ordinary arc's:
///
///   accelerating  a bot that leaves slow catches up FASTER than on an ordinary arc,
///                 because nothing is taking speed back off it between presses. Speed
///                 climbs linearly at runPower*0.65 until basemaxspeed caps the press,
///                 instead of approaching a ceiling geometrically.
///   braking       a bot that leaves HOT cannot shed speed by coasting. On an ordinary arc
///                 releasing the key sheds about 13% a tick; here the only way down is to
///                 press against the motion at 0.585 px/tick for a Soldier. A rocket jump
///                 carries its takeoff momentum the entire flight.
///
/// So using botJumpReach for these arcs would accept ones the bot sails past and refuse
/// ones it flies easily - wrong in both directions at once, which is worse than wrong in
/// one. gg2-nav-gen/src/follow.js's flyDistanceRocket is the same law on the generator
/// side and vetoes the arc before the edge is ever emitted; this is the follower's own
/// copy, asked at the takeoff gate. WARNING: If one moves, move both, or the gate is answering a
/// question about a flight the generator never proved.
///
/// WARNING: controlFactor is NOT read off the character here, where botJumpReach reads it live.
/// At the moment this is asked the bot is still on the ground with moveStatus 0, so the
/// live value is the ordinary 0.85 - the rocket that sets moveStatus to 1 does not exist
/// yet. NAV_RJ_CONTROL is the value that will apply for every tick this loop models.
///
/// basemaxspeed is read live and is correct live: Character's Create computes it once from
/// baseControl/baseFriction and stores it, and Begin Step's cap test reads that stored
/// value rather than recomputing it from the live controlFactor. A rocket-jumping
/// character accelerates more slowly toward exactly the same ceiling it always had.
///
/// Not monotonic in v0, for the same reason botJumpReach is not: arriving *ahead* of a
/// constant-velocity schedule makes the tracker brake. A caller must not bisect this for a
/// threshold, and the takeoff gate must keep its BOT_TAKEOFF_PATIENCE escape hatch.

var char, needVx, flightTicks, v0, total, v, px, air, n, want, press, acc, maxs;

char = argument0;
needVx = argument1;
flightTicks = argument2;
v0 = argument3;

acc = char.runPower * NAV_RJ_CONTROL;
maxs = char.basemaxspeed;

// NAV_RJ_FRICTION is 1 and the divide below is written out rather than folded away, so
// that a change to the constant is a change to this script's behaviour rather than a
// silent no-op. Guarded for the same reason botJumpReach guards baseFriction: a caller
// that hands over something that is not a Character should get a bad answer, not a modal
// divide-by-zero dialog.
if(NAV_RJ_FRICTION <= 0)
    return 0;

total = needVx * flightTicks;
v = v0;
px = 0;
n = max(1, round(flightTicks));

for(air = 1; air <= n; air += 1)
{
    want = min(total, needVx * air);

    // The speed gate, which is what makes this law converge without friction under it.
    // Position decides WHETHER to press; speed decides whether pressing can help. Once
    // the arc's own vx is reached there is nothing to gain - an unfrictioned character
    // holds it - and pressing on from there is what made the real tracker limit-cycle.
    // Same law as botPathKeys' in-flight branch; if one moves, move all four copies.
    press = 0;
    if(px < want - 1)
    {
        if(v < needVx)
            press = 1;
    }
    else if(px > want + 1)
    {
        if(v > needVx)
            press = -1;
    }

    if(press > 0 and v <= maxs)
        v += acc;
    else if(press < 0 and v >= -maxs)
        v -= acc;
    v /= NAV_RJ_FRICTION;
    if(abs(v) < BOT_REST_SPEED and press == 0)
        v = 0;

    px += v;
}

return px;
