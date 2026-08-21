// void test_botaim()
// Bot aim solver unit test.
//
// Every case is pure arithmetic against botAimLead, so the suite needs no map, no
// server, no Character and no weapon instance, and is fully deterministic (F33). The
// weapon table itself lives in botAimSolve and is data rather than logic - it needs a
// live Character to exercise and is covered by shooting things in a real game instead.
//
// The assertion is deliberately not "botAimLead returns the angle I derived by hand",
// which would only re-state the implementation. Instead each case *forward-simulates
// the projectile the way move_all_bullets actually moves it* - vspeed += gravity, then
// x += hspeed, y += vspeed, once per tick - AND forward-simulates the target the way
// Character's own Step event moves vertically (half the tick's gravity before the move,
// half after, each half clamped at NAV_JUMP_TERM_VY, and clamped a second time at the
// case's own floor) - then asserts the shot passes within a tolerance of where the
// target will really be at that same tick. If the solver's algebra and the engine's
// integration ever disagree, this fails; if they agree, the shot lands.
//
// Coordinates are world px with y increasing downward, and speeds are px/tick, matching
// createShot's arguments exactly.

test_unit_begin();

var n, ci, tk;
var csx, csy, ctx, cty, ctvx, ctvy, cspd, cgrav, cdrift, cfloor;
var dir, px, py, pvx, pvy, ty2, tvspeed, best, d, tolerance;

// Each case is: shooter at (csx, csy), target now at (ctx, cty) and travelling at
// (ctvx, ctvy) px/tick, projectile of muzzle speed cspd with per-tick gravity cgrav and
// a constant added horizontal drift cdrift (the weapons that do shot.hspeed +=
// owner.hspeed). cfloor is the world y the target cannot be predicted to fall past - for
// a target already standing on the ground this is just cty, which is also what pins the
// new target-gravity term to exactly zero (see the loop below).
n = 0;

// A flat Shot across the whole 375px combat radius. This is the case that motivates the
// whole script: ~29 ticks of flight and ~64px of sag, all of it invisible to a plain
// point_direction. The control case at the bottom of this suite fires the same geometry
// without compensation and measures how far it misses.
csx[n] = 500; csy[n] = 500; ctx[n] = 875; cty[n] = 500;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// A target running away at a Scout's pace, so drop and lead have to be solved together
// rather than one after the other. This is the case that sets BOT_AIM_ITERATIONS: the
// iteration converges at about the closing speed over the muzzle speed per pass, so a
// fleeing target is the slow one. At 3 passes this missed by 26px.
csx[n] = 500; csy[n] = 500; ctx[n] = 750; cty[n] = 500;
ctvx[n] = 6; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// Running toward the shooter, which shortens the flight and so *reduces* the sag - the
// opposite correction, and a sign error in the lead term shows up here rather than above.
csx[n] = 500; csy[n] = 500; ctx[n] = 875; cty[n] = 500;
ctvx[n] = -6; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// Uphill: 200px across and 150px up.
csx[n] = 500; csy[n] = 500; ctx[n] = 700; cty[n] = 350;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 350; n += 1;

// Downhill: 200px across and 150px down.
csx[n] = 500; csy[n] = 500; ctx[n] = 700; cty[n] = 650;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 650; n += 1;

// A target already falling at a steady clip well short of terminal velocity, so the lead
// is vertical rather than horizontal. No floor within the flight, so the target keeps
// accelerating (clamped at NAV_JUMP_TERM_VY) the whole time - this is what exercises the
// terminal-velocity clamp on its own, before the ground clamp is added below.
csx[n] = 500; csy[n] = 500; ctx[n] = 750; cty[n] = 400;
ctvx[n] = 0; ctvy[n] = 5; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 100000; n += 1;

// The Minegun's heavier lob: gravity 0.2 at speed 12 over 300px.
csx[n] = 500; csy[n] = 500; ctx[n] = 800; cty[n] = 500;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 12; cgrav[n] = 0.2; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// A Rocket: no gravity at all, so this case is pure target leading and isolates it. The
// range is kept to 200px because the closing speed against a fleeing Scout is only
// 6px/tick, and a rocket that flies much longer than this exceeds its own rocketrange
// of 501 and fades before it arrives.
csx[n] = 500; csy[n] = 500; ctx[n] = 700; cty[n] = 500;
ctvx[n] = 6; ctvy[n] = 0; cspd[n] = 12; cgrav[n] = 0; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// A Scattergun fired while the bot itself sprints right at 4px/tick. The drift is added
// to the projectile, not to the aim point, so the solve has to lean back into it.
csx[n] = 500; csy[n] = 500; ctx[n] = 800; cty[n] = 500;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 4; cfloor[n] = 500; n += 1;

// Drift and a moving target at once, in opposite directions.
csx[n] = 500; csy[n] = 500; ctx[n] = 800; cty[n] = 460;
ctvx[n] = -5; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 4; cfloor[n] = 460; n += 1;

// Point blank, where the flight is a couple of ticks and the sag is nearly nothing. The
// clamp holds t at a minimum of 1 here, so this is also the case that proves the clamp
// does not distort a short shot.
csx[n] = 500; csy[n] = 500; ctx[n] = 560; cty[n] = 500;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// A slow Flame close in, where gravity is large relative to the speed.
csx[n] = 500; csy[n] = 500; ctx[n] = 600; cty[n] = 500;
ctvx[n] = 0; ctvy[n] = 0; cspd[n] = 8.25; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 500; n += 1;

// M7 3.6: a target that just jumped (NAV_JUMP_V0 = 8.3, launched upward), far above any
// floor. This is the reported bug verbatim - "if I am mid-jump, the enemy bot will fire
// high in the air" - and it is the case a pure ty + tvy*t prediction gets wrong forever,
// since the target never stops rising under that model. The control at the bottom of
// this suite fires that exact old prediction at this same target and misses by ~52px.
csx[n] = 500; csy[n] = 500; ctx[n] = 700; cty[n] = 450;
ctvx[n] = 0; ctvy[n] = -8.3; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 100000; n += 1;

// M7 3.6: a falling target that lands partway through the shot's flight and stops -
// exercises the ground clamp specifically, which is the mirror-image fix (predicting a
// falling target through the floor it has already landed on).
csx[n] = 500; csy[n] = 500; ctx[n] = 700; cty[n] = 400;
ctvx[n] = 3; ctvy[n] = 6; cspd[n] = 13; cgrav[n] = 0.15; cdrift[n] = 0; cfloor[n] = 420; n += 1;

// M7 3.6: a Rocket (no projectile gravity) against a target that just jumped, isolating
// the target-gravity term from the projectile's own sag the same way the plain Rocket
// case above isolates horizontal lead.
csx[n] = 500; csy[n] = 500; ctx[n] = 700; cty[n] = 500;
ctvx[n] = 6; ctvy[n] = -8.3; cspd[n] = 12; cgrav[n] = 0; cdrift[n] = 0; cfloor[n] = 100000; n += 1;

for(ci = 0; ci < n; ci += 1)
{
    dir = botAimLead(csx[ci], csy[ci], ctx[ci], cty[ci],
                     ctvx[ci], ctvy[ci], cspd[ci], cgrav[ci], cdrift[ci], cfloor[ci]);

    px = csx[ci];
    py = csy[ci];
    pvx = lengthdir_x(cspd[ci], dir) + cdrift[ci];
    pvy = lengthdir_y(cspd[ci], dir);

    // The target's own real trajectory, integrated the same way Character's Step event
    // does (half the tick's gravity before the move, half after, each half clamped at
    // NAV_JUMP_TERM_VY) and clamped a second time at the case's floor. For a grounded
    // case (ctvy = 0, cfloor = cty) this pins ty2 to cty on the very first tick and never
    // moves it again - the "grounded target, vanishing term" requirement from M7 3.6,
    // proven here rather than just asserted.
    ty2 = cty[ci];
    tvspeed = ctvy[ci];

    // 90 ticks deliberately, rather than BOT_AIM_MAX_TICKS: the simulation horizon has
    // to stay independent of the solver's own clamp, or raising the clamp would move the
    // goalposts along with it and a solution that arrives just past the cap would read as
    // a miss.
    best = 1000000;
    for(tk = 1; tk <= 90; tk += 1)
    {
        pvy += cgrav[ci];
        px += pvx;
        py += pvy;

        tvspeed += NAV_JUMP_GRAVITY / 2;
        if(tvspeed > NAV_JUMP_TERM_VY)
            tvspeed = NAV_JUMP_TERM_VY;
        ty2 += tvspeed;
        tvspeed += NAV_JUMP_GRAVITY / 2;
        if(tvspeed > NAV_JUMP_TERM_VY)
            tvspeed = NAV_JUMP_TERM_VY;
        if(ty2 > cfloor[ci])
        {
            ty2 = cfloor[ci];
            tvspeed = 0;
        }

        d = point_distance(px, py, ctx[ci] + ctvx[ci] * tk, ty2);
        if(d < best)
            best = d;
    }

    // The solve is continuous but the engine samples it once a tick, so the closest the
    // shot can be guaranteed to pass is half a tick of travel. Anything inside that is a
    // hit: a Character is about 19px wide and 46px tall (F24).
    tolerance = cspd[ci] / 2 + 1;
    test_assert_equals(true, best <= tolerance);
}

// Control: the same long flat shot as case 0, aimed the naive way. If this ever comes
// out close, the geometry above stopped testing anything and the tolerances are meeting
// in the middle rather than the solver doing work.
dir = point_direction(500, 500, 875, 500);
px = 500;
py = 500;
pvx = lengthdir_x(13, dir);
pvy = lengthdir_y(13, dir);
best = 1000000;
for(tk = 1; tk <= 90; tk += 1)
{
    pvy += 0.15;
    px += pvx;
    py += pvy;
    d = point_distance(px, py, 875, 500);
    if(d < best)
        best = d;
}
test_assert_equals(true, best >= 40);

// A target that simply cannot be caught: fleeing at 9px/tick, 375px away, from a Shot
// that only travels 13. The closing speed is 4px/tick, so the intercept is ~94 ticks and
// ~670px of sag away - past the clamp, and long past the projectile's own ~35-tick
// lifetime. What matters is that the clamp holds the answer somewhere sane instead of
// letting the sag feedback run away into a shot at the sky, so this asserts the aim stays
// a shallow lead rather than a lob. It comes out at 16.7 degrees. Grounded (cfloor = cty),
// so the target-gravity term does not perturb this one either.
dir = botAimLead(500, 500, 875, 500, 9, 0, 13, 0.15, 0, 500);
test_assert_equals(true, dir > 0 and dir < 45);

// Control for M7 3.6: fire using the OLD prediction (pure ty + tvy*t, no target gravity)
// at the mid-jump case above, then check that shot against the target's REAL falling
// trajectory. This is what a bot's shot used to do at anyone airborne. If this control
// ever comes out inside tolerance, the gravity term above is not doing anything and the
// case it guards is vacuous - measured, it misses by about 52px against a ~7.5px
// tolerance, matching the finding's own math (33px at 10 ticks, 126px at 20).
var oldT, oldAx, oldAy;
oldT = min(max(point_distance(500, 500, 700, 450) / 13, 1), BOT_AIM_MAX_TICKS);
oldAx = 700;
oldAy = 450 + (-8.3) * oldT - 0.15 * oldT * (oldT + 1) / 2;
dir = point_direction(500, 500, oldAx, oldAy);

px = 500; py = 500;
pvx = lengthdir_x(13, dir);
pvy = lengthdir_y(13, dir);
ty2 = 450;
tvspeed = -8.3;
best = 1000000;
for(tk = 1; tk <= 90; tk += 1)
{
    pvy += 0.15;
    px += pvx;
    py += pvy;

    tvspeed += NAV_JUMP_GRAVITY / 2;
    if(tvspeed > NAV_JUMP_TERM_VY)
        tvspeed = NAV_JUMP_TERM_VY;
    ty2 += tvspeed;
    tvspeed += NAV_JUMP_GRAVITY / 2;
    if(tvspeed > NAV_JUMP_TERM_VY)
        tvspeed = NAV_JUMP_TERM_VY;

    d = point_distance(px, py, 700, ty2);
    if(d < best)
        best = d;
}
test_assert_equals(true, best > 20);

test_unit_end();
