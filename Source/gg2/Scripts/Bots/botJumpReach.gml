/// botJumpReach(char, needVx, flightTicks, v0)
/// How far along a jump arc this character would actually get, in world px, if it left
/// the takeoff column carrying v0 px/tick along the jump and then flew the arc the way
/// botPathKeys' in-flight tracker flies it.
///
/// This is the arithmetic the takeoff gate was missing. navJumpTakeoff proves an arc as
/// a CONSTANT horizontal velocity applied from tick 0 and records it as NAV_EDGE_BUCKET;
/// a GG2 character accelerates - hspeed = (hspeed + runPower*controlFactor)/baseFriction
/// - and starts at whatever it is already carrying, which after a climb up a staircase
/// is nothing, or is pointing the wrong way. The tracker presses toward where the plan
/// says the bot should be by now, so it does catch up, but only out of the surplus
/// between the arc's speed and this class's own ceiling. An arc that asks for most of
/// that ceiling has no surplus, the deficit built up over the acceleration ramp is never
/// repaid, and the bot lands short - every single time, which is how the same edge gets
/// blacklisted, un-blacklisted and flown again for a whole round.
///
/// Two measurements decided the shape of this. Both are offline, over the twenty-three
/// cached graphs, with gg2-agent/tools/navfollow.js:
///
///   - 3310 of 62069 jump edges are unflyable by a Heavy from the run-up its source node
///     offers. NAV_JUMP_VX (4.53) is literally a Heavy's ceiling, so the fast arcs are
///     the ones that bite, and on koth_corinth 96% of a Heavy's routes to the point
///     cross one.
///   - 91.9% of jump edges need NO takeoff speed at all - the tracker flies them from a
///     standstill with room to spare.
///
/// That second number is why the gate asks this script rather than demanding the arc's
/// full speed. Demanding full speed was tried and lost: 647 -> 868 and 674 -> 997 ticks
/// on the valley scenarios with no more arrivals, because it forces a run-up on every
/// jump in the game. Asking what *this* arc needs leaves nine arcs in ten exactly as
/// they were and spends the run-up only where it is the difference between arriving and
/// never arriving.
///
/// The motion law is Character's Begin Step, in its order: the run key adds first and
/// only while under basemaxspeed, friction divides afterwards, and the "ice skating"
/// snap to rest applies only with nothing held. controlFactor is read live rather than
/// assumed, because Begin Step sets it from moveStatus and not from onground - the same
/// value applies in the air, which is the whole reason the tracker can correct a slow
/// takeoff at all.
///
/// The tracker replayed here is botPathKeys' own: press toward
/// navColWorldX(takeoff) + dir*min(needVx*flightTicks, needVx*airTicks), with a
/// one-pixel dead band. ⚠️ Anything that changes there has to change here, or the gate
/// is answering a question about a flight the follower does not make. The offline model
/// in navfollow.js is a third copy of the same law and is the cheap way to A/B a change
/// to it before a build.
///
/// Not monotonic in v0, and that is real rather than a rounding artefact: on the
/// koth_gallery n56 -> n44 arc, 3.50 clears, 3.75 and 4.00 fail and 4.25 clears again,
/// because arriving *ahead* of a constant-velocity schedule makes the tracker brake. So
/// a caller must not bisect this for a threshold, and the takeoff gate must have an
/// escape hatch (BOT_TAKEOFF_PATIENCE) for a bot that lands in a band it cannot leave.

var char, needVx, flightTicks, v0, total, v, px, air, n, want, press, acc, maxs, fric;

char = argument0;
needVx = argument1;
flightTicks = argument2;
v0 = argument3;

acc = char.runPower * char.controlFactor;
maxs = char.basemaxspeed;
fric = char.baseFriction;

// Character's own Create warns that baseFriction may be neither 0 nor 1 or the divide
// blows up. It is 1.15 on every class; this is here so a caller that hands over
// something that is not a Character fails as a bad answer rather than as a modal dialog.
if(fric <= 0)
    return 0;

total = needVx * flightTicks;
v = v0;
px = 0;
n = max(1, round(flightTicks));

for(air = 1; air <= n; air += 1)
{
    want = min(total, needVx * air);

    press = 0;
    if(px < want - 1)
        press = 1;
    else if(px > want + 1)
        press = -1;

    if(press > 0 and v <= maxs)
        v += acc;
    else if(press < 0 and v >= -maxs)
        v -= acc;
    v /= fric;
    if(abs(v) < BOT_REST_SPEED and press == 0)
        v = 0;

    px += v;
}

return px;
