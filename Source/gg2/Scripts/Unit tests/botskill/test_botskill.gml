// void test_botskill()
// Bot difficulty model unit test: the knob table, the error formula, the leading ladder
// and the per-class bands.
//
// Everything here is arithmetic or a table lookup, so the suite needs no map and no
// server (F33). The one exception is botSkillApply, which writes its knobs onto a Player,
// so the suite creates one, checks it and destroys it again - the same shape as
// test_navgraph's MoveBoxDown case, and for the same reason: the wiring is the thing
// worth testing, and the wiring needs an instance.
//
// The leading cases follow test_botaim's rule rather than restating the solver: each one
// forward-simulates the projectile exactly as move_all_bullets moves it - vspeed +=
// gravity, then x += hspeed, y += vspeed, once per tick - and asserts where the shot
// passes. What is being pinned is that the three lead modes are three *different*
// players: BOT_LEAD_NONE misses a runner behind, BOT_LEAD_LINEAR catches it near and
// loses it far, and BOT_LEAD_FULL connects at the edge of the combat radius. If those
// stop differing, the difficulty setting stops being visible from the receiving end,
// which is the only thing it is for.

test_unit_begin();

var i, t, skill, tk, dir, px, py, pvx, pvy, best, d, t0;
var lerped, prevAcq, prevFire, prevErr, prevTurn;
var probe, aimProbe, spread, spreadClose, spreadFar;

// --- botSkillLerp: the four anchors are exact, and outside them it clamps -------------

// The published acquisition-delay ladder, in ticks.
test_assert_equals(30, botSkillLerp(0.15, 30, 15, 9, 6));
test_assert_equals(15, botSkillLerp(0.45, 30, 15, 9, 6));
test_assert_equals(9,  botSkillLerp(0.75, 30, 15, 9, 6));
test_assert_equals(6,  botSkillLerp(0.95, 30, 15, 9, 6));

// Clamping is what lets skill be a plain 0..1 scalar with no checks at the call sites.
test_assert_equals(30, botSkillLerp(0, 30, 15, 9, 6));
test_assert_equals(30, botSkillLerp(-5, 30, 15, 9, 6));
test_assert_equals(6,  botSkillLerp(1, 30, 15, 9, 6));
test_assert_equals(6,  botSkillLerp(99, 30, 15, 9, 6));

// Halfway between two anchors is halfway between their values, in each of the three
// segments - including the last one, which is 0.2 wide rather than 0.3.
test_assert_equals(22.5, botSkillLerp(0.3, 30, 15, 9, 6));
test_assert_equals(12,   botSkillLerp(0.6, 30, 15, 9, 6));
test_assert_equals(7.5,  botSkillLerp(0.85, 30, 15, 9, 6));

// --- the five tiers are monotone in every knob that has a direction -------------------

// Tier n has skill 0.15 + (n-1)*0.2. A higher tier must never be slower to react, never
// less accurate and never slower to turn: a non-monotone knob is a difficulty setting
// that makes a bot worse when it is turned up.
prevAcq = 1000;
prevFire = 1000;
prevErr = 1000;
prevTurn = 0;
for(i = 1; i <= 5; i += 1)
{
    skill = 0.15 + (i - 1) * 0.2;

    lerped = botSkillLerp(skill, 30, 15, 9, 6);
    test_assert_equals(true, lerped <= prevAcq);
    prevAcq = lerped;

    lerped = botSkillLerp(skill, 45, 21, 10, 0);
    test_assert_equals(true, lerped <= prevFire);
    prevFire = lerped;

    lerped = botSkillLerp(skill, 4, 1.5, 0.5, 0.2);
    test_assert_equals(true, lerped <= prevErr);
    prevErr = lerped;

    lerped = botSkillLerp(skill, 6, 7.5, 9, 24);
    test_assert_equals(true, lerped >= prevTurn);
    prevTurn = lerped;
}

// --- botSkillApply: the knobs land on the Player, at the published values -------------

probe = instance_create(0, 0, Player);

botSkillApply(probe, 0.15);
test_assert_equals(0.15, probe.botSkill);
test_assert_equals(30, probe.botAcquireTicks);
test_assert_equals(45, probe.botFireDelayTicks);
test_assert_equals(15, probe.botPerceiveTicks);
test_assert_equals(8, probe.botAimInterval);
test_assert_equals(4, probe.botAimErrorDeg);
test_assert_equals(20, probe.botAimConeDeg);
test_assert_equals(6, probe.botTurnRate);
// Every tier leads fully now (M7 3.4) - under-leading was not a legible difficulty
// signal, it just read as a bad shot. Easy bots still do not aim splash at feet, which
// is Quake III's own gate and stays legible to whoever is being shot at.
test_assert_equals(BOT_LEAD_FULL, probe.botLeadMode);
test_assert_equals(false, probe.botSplashAim);

botSkillApply(probe, 0.95);
test_assert_equals(6, probe.botAcquireTicks);
test_assert_equals(0, probe.botFireDelayTicks);
test_assert_equals(1, probe.botPerceiveTicks);
test_assert_equals(2, probe.botAimInterval);
test_assert_equals(0.2, probe.botAimErrorDeg);
test_assert_equals(24, probe.botTurnRate);
test_assert_equals(0, probe.botHoldFireChance);
test_assert_equals(BOT_LEAD_FULL, probe.botLeadMode);
test_assert_equals(true, probe.botSplashAim);

// Tier 4 - hard - also leads fully now (M7 3.4): what still keeps "hard" and "expert"
// apart at range is the aim-error ladder and the latency gates, not leading.
botSkillApply(probe, 0.75);
test_assert_equals(BOT_LEAD_FULL, probe.botLeadMode);
test_assert_equals(true, probe.botSplashAim);

// A tick count is never fractional, and never zero where zero would mean "every tick
// forever": GM8's round() is banker's rounding, so botSkillApply uses floor(x + 0.5).
botSkillApply(probe, 0.55);
test_assert_equals(true, probe.botAimInterval >= 1);
test_assert_equals(probe.botAimInterval, floor(probe.botAimInterval));
test_assert_equals(probe.botPerceiveTicks, floor(probe.botPerceiveTicks));
test_assert_equals(probe.botAcquireTicks, floor(probe.botAcquireTicks));

// Out-of-range skill is clamped rather than extrapolated.
botSkillApply(probe, 5);
test_assert_equals(1, probe.botSkill);
botSkillApply(probe, -1);
test_assert_equals(0, probe.botSkill);

with(probe)
    instance_destroy();

// --- botAimSpread: cone decay, movement scale, close-range penalty --------------------

// At acquisition the whole cone is present: 12 + 20 = 32 degrees for an easy bot, at a
// distance past the close-range ramp and against a stationary target.
test_assert_equals(32, botAimSpread(12, 20, 1, false, 0, 90));

// The cone decays towards nothing, so a bot that has been staring at the same target
// settles to its base error.
spread = botAimSpread(12, 20, 1, false, 400, 90);
test_assert_equals(true, spread > 12);
test_assert_equals(true, spread < 12.5);
test_assert_equals(true, botAimSpread(12, 20, 1, false, 100, 90) < botAimSpread(12, 20, 1, false, 30, 90));

// Quake III's close-range penalty applies at every tier: accuracy is scaled by
// BOT_CLOSE_PENALTY at zero distance and 1 at BOT_CLOSE_RANGE, so the error is divided
// by that. Point-blank error is therefore 1/0.6 of mid-range error, exactly.
spreadClose = botAimSpread(3, 0, 1, false, 0, 0);
spreadFar = botAimSpread(3, 0, 1, false, 0, BOT_CLOSE_RANGE);
test_assert_equals(3, spreadFar);
test_assert_equals(true, abs(spreadClose - 3 / BOT_CLOSE_PENALTY) < 0.0001);
// Past the ramp nothing changes: a target at 400px is no easier than one at 90.
test_assert_equals(spreadFar, botAimSpread(3, 0, 1, false, 0, 400));

// The moving-target multiplier only applies when the target is moving. Compared with a
// tolerance rather than for equality: 3 * 0.3 is 0.8999999999999999 in binary floating
// point, and test_assert_equals is exact.
test_assert_equals(3, botAimSpread(3, 0, 0.3, false, 0, 90));
test_assert_equals(true, abs(botAimSpread(3, 0, 0.3, true, 0, 90) - 0.9) < 0.0001);

// --- the leading ladder, against a forward simulation of the engine's own integration --

// A Scout running at 6px/tick, 375px away - the far edge of a Scattergun engagement -
// and a Shot at speed 13 with 0.15 gravity. Each mode aims its own way; the assertions
// are about where the shot ends up, not about the angle.
for(i = 0; i <= 2; i += 1)
{
    // Grounded target (tvy = 0, floor pinned to its own ty), so botAimLead's
    // target-gravity term vanishes and these three modes are still comparing pure
    // leading behaviour, same as before that term existed.
    if(i == BOT_LEAD_NONE)
        dir = botAimLead(500, 500, 875, 500, 0, 0, 13, 0.15, 0, 500);
    else if(i == BOT_LEAD_LINEAR)
    {
        // The one line of botAimSolve worth duplicating: predict once at the flight time
        // to where the target stands now, then solve the drop to that fixed point.
        t0 = min(max(point_distance(500, 500, 875, 500) / 13, 1), BOT_AIM_MAX_TICKS);
        dir = botAimLead(500, 500, 875 + 6 * t0, 500, 0, 0, 13, 0.15, 0, 500);
    }
    else
        dir = botAimLead(500, 500, 875, 500, 6, 0, 13, 0.15, 0, 500);

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
        d = point_distance(px, py, 875 + 6 * tk, 500);
        if(d < best)
            best = d;
    }

    // The full solve lands it; the other two are behind, and not marginally. A
    // Character is about 19px wide, so 40px is unambiguously a miss. Measured: 83px for
    // no lead, 46px for linear, 4.6px for the full solve.
    if(i == BOT_LEAD_FULL)
        test_assert_equals(true, best <= 13 / 2 + 1);
    else
        test_assert_equals(true, best >= 40);
}

// Close in, linear leading is enough: the flight is short, so the flight time to where
// the target is now and the flight time to where it will be barely differ. This is the
// case that makes the ladder a ladder rather than a switch - a hard bot is not simply
// worse everywhere, it is worse at range.
t0 = min(max(point_distance(500, 500, 650, 500) / 13, 1), BOT_AIM_MAX_TICKS);
dir = botAimLead(500, 500, 650 + 6 * t0, 500, 0, 0, 13, 0.15, 0, 500);
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
    d = point_distance(px, py, 650 + 6 * tk, 500);
    if(d < best)
        best = d;
}
// 7.8px from the chest, against 46px at 375px - inside a Character, which is about 19px
// wide and 46px tall (F24), so it connects. The tolerance here is a hitbox rather than
// test_botaim's half-tick-of-travel, because linear leading is an approximation on
// purpose: what is asserted is that it still hits, not that it is exact.
test_assert_equals(true, best <= 10);

// --- per-class bands are non-empty and correctly ordered ------------------------------

// Every class must be able to shoot at something: a minimum band above the class's own
// range would produce a bot that tracks an enemy and never fires, which reads exactly
// like a broken bot rather than a badly tuned one.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
    test_assert_equals(true, botClassRange(i) > 0);

test_assert_equals(true, BOT_SPLASH_SAFE < botClassRange(CLASS_SOLDIER));
test_assert_equals(true, BOT_SPLASH_SAFE < botClassRange(CLASS_DEMOMAN));
// A Pyro's flames die at BOT_FLAME_REACH, so its attention must reach at least that far.
test_assert_equals(true, BOT_FLAME_REACH <= botClassRange(CLASS_PYRO));
// Stab range has to be inside the Spy's own band or the stab is unreachable.
test_assert_equals(true, BOT_STAB_RANGE < botClassRange(CLASS_SPY));
// The Medic's beam and its target search have to agree.
test_assert_equals(true, BOT_HEAL_RANGE <= botClassRange(CLASS_MEDIC));

// Zoom hysteresis: the two thresholds must not cross, or a Sniper toggles its zoom every
// time the target steps over a single line - and each toggle is a broadcast packet.
test_assert_equals(true, BOT_UNZOOM_RANGE < BOT_ZOOM_RANGE);
test_assert_equals(true, BOT_ZOOM_RANGE <= botClassRange(CLASS_SNIPER));

// --- botClassMinBand: the inner edge of the same band (M7 tier 3) ---------------------

// botClassRange owns the outer edge, botClassMinBand the inner one, and the invariant
// that matters is that they never cross: a minimum above the maximum is a bot that
// tracks an enemy and never fires, which reads as broken rather than as badly tuned.
// Asserted for every class rather than for the two splash ones, because the default
// branch applies to classes nobody thinks about when adding a new constant.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
{
    test_assert_equals(true, botClassMinBand(i) >= 0);
    test_assert_equals(true, botClassMinBand(i) < botClassRange(i));
}

// The two splash classes carry the self-harm band; everyone else carries at most the
// much smaller degeneracy floor. This is what botFindTarget's "rank a point-blank enemy
// a whole attention radius worse" and botInputUpdate's back-off both read.
test_assert_equals(BOT_SPLASH_SAFE, botClassMinBand(CLASS_SOLDIER));
test_assert_equals(BOT_SPLASH_SAFE, botClassMinBand(CLASS_DEMOMAN));

// The three close-range classes must have no minimum at all. Backing a Pyro away from a
// fight backs it out of the only fight it can win - its Flame cannot reach past
// BOT_FLAME_REACH - and the same goes for a Spy's stab and a Medic's beam.
test_assert_equals(0, botClassMinBand(CLASS_PYRO));
test_assert_equals(0, botClassMinBand(CLASS_SPY));
test_assert_equals(0, botClassMinBand(CLASS_MEDIC));
test_assert_equals(BOT_MIN_ENGAGE, botClassMinBand(CLASS_SCOUT));
test_assert_equals(BOT_MIN_ENGAGE, botClassMinBand(CLASS_SNIPER));

// A Generator ranks below every possible live enemy, whatever the class and however far
// away it is. If it did not, a bot would keep shooting a wall while somebody killed it.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
    test_assert_equals(true, botClassRange(i) * 2 < BOT_GEN_THREAT);

// A firing position has to be inside the weapon's reach *and* outside the self-harm band,
// or botGoalSpot is asked for a band with nothing in it and every generator attacker
// falls back to walking onto the generator itself.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
    test_assert_equals(true, botClassMinBand(i) < botClassRange(i) * BOT_SPOT_BAND);

// --- botClassProfile: the per-class table every shared script now reads ----------------

// Six per-class tests used to live inline in botCombatUpdate, botInputUpdate and
// botObjectiveUpdate; they are all one lookup now, and this block is what keeps that
// lookup honest. Nothing here re-states the table - asserting "the Medic heals" against a
// script whose whole content is "the Medic heals" pins nothing. What is asserted is the
// invariants the *callers* rely on, and the places where two independent tables have to
// agree with each other.

// Every flag field answers 0 or 1 for every class, including the classes nobody thinks
// about. A caller treats these as booleans without checking, so a stray 2 or -1 from a
// mistyped case would be a truthy value in a branch that is supposed to be off.
var fields, f, fi, v;
fields = ds_list_create();
ds_list_add(fields, BOT_CP_POTSHOT);
ds_list_add(fields, BOT_CP_HEALS);
ds_list_add(fields, BOT_CP_SPLASH);
ds_list_add(fields, BOT_CP_SPECIAL_FIRE);
ds_list_add(fields, BOT_CP_AIRJUMP);
ds_list_add(fields, BOT_CP_FOLLOW);
for(fi = 0; fi < ds_list_size(fields); fi += 1)
{
    f = ds_list_find_value(fields, fi);
    for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
    {
        v = botClassProfile(i, f);
        test_assert_equals(true, v == 0 or v == 1);
    }
}
ds_list_destroy(fields);

// An unknown field is 0 rather than undefined, which is what lets a caller add a field
// constant before the table has an opinion about it.
test_assert_equals(0, botClassProfile(CLASS_SCOUT, 999));

// The two tables that describe the same fact have to agree: aiming at a grounded target's
// feet is only correct for a weapon whose blast can reach the shooter, and that same blast
// is why botClassMinBand hands those classes BOT_SPLASH_SAFE. If one is edited and the
// other is not, a class either self-damages or stops using splash properly, and neither
// shows up as an error anywhere.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
{
    if(botClassProfile(i, BOT_CP_SPLASH))
        test_assert_equals(BOT_SPLASH_SAFE, botClassMinBand(i));
}

// The per-class aim multipliers scale a difficulty knob rather than replacing it, so a
// zero or a negative is not "no error" - it is a class that cannot miss, or one whose
// error runs backwards through botAimSpread's close-range divisor. Every class has to
// have a usable one whether or not it has an opinion.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
{
    test_assert_equals(true, botClassProfile(i, BOT_CP_AIM_ERR) > 0);
    test_assert_equals(true, botClassProfile(i, BOT_CP_AIM_SETTLE) > 0);
}

// The two the playtest actually asked for, and they are opposite on purpose: the Soldier
// makes every shot count, the Heavy does not need to hit with every bullet. Asserted by
// direction rather than by value so retuning the constants does not rewrite the test,
// but a sign flip - which would silently swap the two classes' feel - does fail it.
test_assert_equals(true, botClassProfile(CLASS_SOLDIER, BOT_CP_AIM_ERR) < 1);
test_assert_equals(true, botClassProfile(CLASS_HEAVY, BOT_CP_AIM_ERR) > 1);
test_assert_equals(true, botClassProfile(CLASS_HEAVY, BOT_CP_AIM_SETTLE) > 1);

// ⚠️ The multiplier must not be baked into botSkillApply. It runs once, from botAdd, so a
// baked value goes stale when a bot changes class - and the tier's published numbers are
// asserted exactly above, which is what keeps the two axes independent.
// ⚠️ Its own Player: the one above is destroyed right after the knob table, and reusing
// it here reads every field as "Unknown variable" and stops the suite mid-run.
aimProbe = instance_create(0, 0, Player);
botSkillApply(aimProbe, 0.15);
aimProbe.class = CLASS_SOLDIER;
test_assert_equals(4, aimProbe.botAimErrorDeg);
aimProbe.class = CLASS_HEAVY;
test_assert_equals(4, aimProbe.botAimErrorDeg);
with(aimProbe)
    instance_destroy();

// A period of 0 is not a slower defender, it is `mod 0` - a hard error in botRoleAssign
// on the first bot of that class to join.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
    test_assert_equals(true, botClassProfile(i, BOT_CP_DEFEND_EVERY) >= 1);

// Every positioning mode is one of the four botObjectiveUpdate knows how to act on. An
// unrecognised value there is silently "no opinion", so it would read as a class whose
// tuning simply does nothing.
for(i = CLASS_SCOUT; i <= CLASS_QUOTE; i += 1)
{
    v = botClassProfile(i, BOT_CP_SPOT_MODE);
    test_assert_equals(true, v == BOT_SPOT_NONE or v == BOT_SPOT_STANDOFF
                             or v == BOT_SPOT_CHOKE or v == BOT_SPOT_FLANK);

    // A class that stands off has to have somewhere to stand: the near edge of its band is
    // a fraction of the far edge and the far edge is a fraction of its own weapon range, so
    // a class whose range was retuned downward could end up with the two crossed - and
    // botGoalSpot returns -1 for an empty band, which reads as "no spot on this map"
    // rather than as a tuning mistake.
    if(v == BOT_SPOT_STANDOFF)
    {
        test_assert_equals(true,
            max(botClassMinBand(i), 1) < botClassRange(i) * BOT_SPOT_BAND);
        test_assert_equals(true, BOT_SPOT_NEAR_FRAC < 1);
    }
}

// The classes whose job is to physically reach the objective must not have a spot mode at
// all: a Scout caps at capStrength 2, twice everyone else's rate, and standing it off from
// the point would turn off the single best reason to have one. botObjectiveUpdate's
// carryGoal gate is the second line of defence here, not the first.
test_assert_equals(BOT_SPOT_NONE, botClassProfile(CLASS_SCOUT, BOT_CP_SPOT_MODE));
// A Medic never reaches this code - it follows an ally and returns early - so a spot mode
// on it would be dead tuning that looks live.
test_assert_equals(true, botClassProfile(CLASS_MEDIC, BOT_CP_FOLLOW));
test_assert_equals(BOT_SPOT_NONE, botClassProfile(CLASS_MEDIC, BOT_CP_SPOT_MODE));

// --- botRoleAssign: one defender in every N of a class's lean group --------------------

// The bug this pins is a real one the first version of botRoleAssign had: counting a
// bot's *team-mates* rather than its own position down the roster gives every bot on the
// team the same number, so a team of exactly BOT_DEFEND_EVERY becomes all defenders at
// once and a team of any other size becomes none. Both assertions below are deliberately
// stated so that they do not depend on how many bots the roster already held - any six
// consecutive positions contain exactly two multiples of three, wherever they start, and
// the two are always BOT_DEFEND_EVERY apart. Under the old bug the count is 6 or 0.
//
// The probes are Soldiers rather than the Player default: the period is per class now, and
// the default class is CLASS_SCOUT, which is one of the two deliberately defence-averse
// ones. A Soldier is on the shared default period, so this block still measures exactly
// what it measured before the class term existed.
var roles, bots, defenders, firstDef, lastDef, k;
bots = ds_list_create();
for(k = 0; k < 6; k += 1)
{
    probe = instance_create(0, 0, Player);
    probe.isBot = true;
    probe.team = TEAM_RED;
    probe.class = CLASS_SOLDIER;
    ds_list_add(global.players, probe);
    ds_list_add(bots, probe);
}

defenders = 0;
firstDef = -1;
lastDef = -1;
roles = "";
for(k = 0; k < 6; k += 1)
{
    probe = ds_list_find_value(bots, k);
    botRoleAssign(probe);
    if(probe.botRole == BOT_ROLE_DEFEND)
    {
        defenders += 1;
        if(firstDef < 0)
            firstDef = k;
        lastDef = k;
    }
    roles = roles + string(probe.botRole);

    // The goal spread is bounded, or a bot walks off to a point that has nothing to do
    // with the objective it was given (M7 2.4).
    test_assert_equals(true, abs(probe.botSpreadX) <= BOT_SPREAD_MAX);
}
test_assert_equals(2, defenders);
test_assert_equals(BOT_DEFEND_EVERY, lastDef - firstDef);

// Stable: re-running it changes nothing, so a role cannot flicker between two values
// while a bot is walking somewhere - which would be indistinguishable from a bot that
// cannot make up its mind, and would throw away the whole point of the split.
for(k = 0; k < 6; k += 1)
{
    probe = ds_list_find_value(bots, k);
    botRoleAssign(probe);
    roles = roles + string(probe.botRole);
}
test_assert_equals(string_copy(roles, 1, 6), string_copy(roles, 7, 6));

for(k = 0; k < 6; k += 1)
{
    probe = ds_list_find_value(bots, k);
    ds_list_delete(global.players, ds_list_find_index(global.players, probe));
    with(probe)
        instance_destroy();
}
ds_list_destroy(bots);

// --- the lean groups are counted separately, which is the whole class term -------------

// Twelve bots alternating Engineer and Scout. Engineers are on BOT_DEFEND_KEEN and Scouts
// on BOT_DEFEND_AVERSE, so the six Engineers must produce 6/KEEN defenders and the six
// Scouts 6/AVERSE, whatever the roster already held - any six consecutive positions in a
// period-N group contain exactly 6/N multiples of N, the same argument the block above
// makes for period 3.
//
// Interleaving them is the point. If the count were over the whole team rather than over
// the bots sharing this bot's period, the Engineers would land on roster positions 0, 2,
// 4, 6, 8, 10 and (position + 1) mod 2 would be 1 for every single one of them: zero
// Engineer defenders, which is the exact inversion of what the class term is for, on the
// composition it is most obviously meant to help.
var engDef, scoutDef;
bots = ds_list_create();
for(k = 0; k < 12; k += 1)
{
    probe = instance_create(0, 0, Player);
    probe.isBot = true;
    probe.team = TEAM_RED;
    if((k mod 2) == 0)
        probe.class = CLASS_ENGINEER;
    else
        probe.class = CLASS_SCOUT;
    ds_list_add(global.players, probe);
    ds_list_add(bots, probe);
}

engDef = 0;
scoutDef = 0;
for(k = 0; k < 12; k += 1)
{
    probe = ds_list_find_value(bots, k);
    botRoleAssign(probe);
    if(probe.botRole == BOT_ROLE_DEFEND)
    {
        if(probe.class == CLASS_ENGINEER)
            engDef += 1;
        else
            scoutDef += 1;
    }
}
test_assert_equals(6 / BOT_DEFEND_KEEN, engDef);
test_assert_equals(6 / BOT_DEFEND_AVERSE, scoutDef);

// Both ends of the composition range still split. The failure the period model exists to
// avoid is a rule that vetoes by class instead of pacing by class: "Engineers defend,
// Scouts attack" leaves an all-Engineer team with nobody attacking and an all-Scout team
// with nobody defending, and botPopulationUpdate picks a class with irandom(8), so it can
// produce either.
test_assert_equals(true, engDef > 0);
test_assert_equals(true, engDef < 6);
test_assert_equals(true, scoutDef > 0);
test_assert_equals(true, scoutDef < 6);

for(k = 0; k < 12; k += 1)
{
    probe = ds_list_find_value(bots, k);
    ds_list_delete(global.players, ds_list_find_index(global.players, probe));
    with(probe)
        instance_destroy();
}
ds_list_destroy(bots);

test_unit_end();
