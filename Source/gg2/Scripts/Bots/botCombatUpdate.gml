/// botCombatUpdate(player)
/// Runs one tick of a bot's combat brain and returns the key bits it wants pressed.
/// The caller ORs them with the navigation half's keys; the two cannot conflict, since
/// this one owns ATTACK and SPECIAL and the follower owns LEFT/RIGHT/JUMP/DOWN.
///
/// This is the see -> acquire -> aim-settled -> fire chain the difficulty model is built
/// around (botSkillApply). Four separate gates, all read off the bot's own knobs:
///
///   1. see      botFindTarget picks a target on a staggered cadence.
///   2. acquire  the bot ignores it entirely for botAcquireTicks. Until then it does not
///               even turn towards it - which is what makes a weak bot look slow rather
///               than blind.
///   3. aim      from then on the desired direction is recomputed every botAimInterval
///               ticks from a target snapshot that itself only refreshes every
///               botPerceiveTicks, and the actual aim slews towards it at botTurnRate
///               degrees a tick. Tracking lag, overshoot and settling all come out of
///               those three numbers; there is no filter and no smoothing.
///   4. fire     ATTACK is withheld until botFireDelayTicks after acquisition *and* the
///               slew has settled to within BOT_AIM_SETTLE_DEG, and is dropped for an
///               aim interval whenever the hold-fire roll comes up (Q3's firethrottle).
///
/// Everything except the target search is per-tick; the expensive parts (that search,
/// line of sight, the aim solve) are on cadences that scale with skill, so a server full
/// of weak bots is also the cheap case.
///
/// Two deliberate exceptions to the gating:
///
/// - A Medic aiming at a *teammate* is healing, not shooting, so its keys are ungated.
///   The ally lookup lives here rather than in botClassKeys because it changes what the
///   bot aims at, and aiming is this script's job.
/// - SPECIAL is gated on acquisition but not on the fire delay, because the special-key
///   behaviours are reactive (a Pyro's airblast, a Demoman detonating under someone's
///   feet) and a reaction that arrives 1.5 s late is not a reaction.
///
/// Aim error is uniform on [-1, 1] scaled by the knob, not Gaussian: Quake III's
/// crandom() is uniform and so is every error term built on it. Two multipliers ride on
/// top - the moving-target scale, and Quake III's close-range penalty, which makes
/// *every* tier worse at point-blank range. That one is an anti-frustration measure
/// rather than a difficulty knob: without it bots are unbeatable in a brawl.

var player, char, tick, range, target, subject, subjectIsAlly, valid, dist;
var keys, moving, err, sinceSeen, canAim, canFire, settled;
var aimX, aimY, delta;

player = argument0;
char = player.object;
tick = frame;
keys = 0;
range = botClassRange(player.class);

// --- 1. see: keep or drop the current target, then look for a new one ---------------

target = player.botTarget;
if(target != noone)
{
    // Never fold these into one boolean expression: GM8 evaluates both sides of and/or
    // unconditionally, so a dead target's .hp would be read even behind instance_exists.
    valid = instance_exists(target);
    if(valid)
        valid = (target.hp > 0 and !target.cloak and target.team != char.team);
    if(valid)
        valid = (point_distance(char.x, char.y, target.x, target.y) <= range);
    if(valid and (tick + player) mod player.botPerceiveTicks == 0)
        valid = !collision_line_bulletblocking(char.x, char.y, target.x, target.y);
    if(!valid)
    {
        target = noone;
        player.botTarget = noone;
    }
}

if(target == noone and (tick + player) mod BOT_TARGET_PERIOD == 0)
{
    target = botFindTarget(char, range);
    if(target != noone)
    {
        player.botTarget = target;
        // Continuous sight starts now: both the acquisition gate and the focus cone's
        // decay are measured from this tick.
        player.botTargetAt = tick;
        player.botHoldFire = false;
    }
}

// --- the Medic exception: a hurt teammate outranks an enemy -------------------------

subject = target;
subjectIsAlly = false;
if(player.class == CLASS_MEDIC)
{
    if((tick + player) mod BOT_TARGET_PERIOD == 0)
        player.botAlly = botFindAlly(char, BOT_HEAL_RANGE);

    valid = (player.botAlly != noone);
    if(valid)
        valid = instance_exists(player.botAlly);
    if(valid)
        valid = (player.botAlly.hp > 0 and player.botAlly.team == char.team);
    if(valid)
    {
        subject = player.botAlly;
        subjectIsAlly = true;
    }
    else
        player.botAlly = noone;
}

if(subject == noone)
{
    // Nothing to aim at is a state a class can still have an opinion about - a Spy
    // re-cloaks, an Engineer builds, a Heavy eats - so both policies still run, and only
    // the aiming is skipped.
    keys = botClassKeys(player, char, noone, 0, false, tick);
    if((tick + player) mod BOT_TARGET_PERIOD == 0)
        botServerActions(player, char, noone, 0);
    player.botAttackKeys = keys;
    return keys;
}

dist = point_distance(char.x, char.y, subject.x, subject.y);

// --- 2. acquire ---------------------------------------------------------------------

sinceSeen = tick - player.botTargetAt;
canAim = subjectIsAlly or (sinceSeen >= player.botAcquireTicks);
canFire = subjectIsAlly or (sinceSeen >= player.botAcquireTicks + player.botFireDelayTicks);

if(!canAim)
{
    player.botAttackKeys = 0;
    return 0;
}

// --- 3. aim: perceive, solve, then slew ---------------------------------------------

if(tick >= player.botPerceiveAt or player.botAimSubject != subject)
{
    player.botPerceiveAt = tick + player.botPerceiveTicks;
    player.botAimSubject = subject;
    player.botSeeX = subject.x;
    player.botSeeY = subject.y;
    player.botSeeVX = subject.hspeed;
    player.botSeeVY = subject.vspeed;
}

if(tick >= player.botAimAt)
{
    player.botAimAt = tick + player.botAimInterval;

    aimX = player.botSeeX;
    aimY = player.botSeeY;

    // Splash weapons want the ground under a grounded target, not its chest: a rocket
    // that lands at the feet damages regardless of where the target steps next.
    if(player.botSplashAim and subject.onground
       and (player.class == CLASS_SOLDIER or player.class == CLASS_DEMOMAN))
        aimY += BOT_FEET_OFFSET;

    player.botAimX = aimX;
    player.botAimY = aimY;

    if(subjectIsAlly)
        player.botAimWant = point_direction(char.x, char.y, aimX, aimY);
    else
    {
        player.botAimWant = botAimSolve(char, aimX, aimY,
                                        player.botSeeVX, player.botSeeVY,
                                        player.botLeadMode);

        moving = (abs(player.botSeeVX) > 0.5 or abs(player.botSeeVY) > 0.5);
        err = botAimSpread(player.botAimErrorDeg, player.botAimConeDeg,
                           player.botMoveErrMult, moving, sinceSeen, dist);

        player.botAimWant += (random(2) - 1) * err;
        player.botHoldFire = (random(1) < player.botHoldFireChance);
    }
}

delta = botAngleDelta(player.botAimWant, player.botAimDir);
if(abs(delta) <= player.botTurnRate)
    player.botAimDir = player.botAimWant;
else
    player.botAimDir += sign(delta) * player.botTurnRate;
player.botAimDir = ((player.botAimDir mod 360) + 360) mod 360;

with(char)
{
    aimDirection = player.botAimDir;
    netAimDirection = aimDirection*65536/360;
    // The Medigun reconstructs its owner's mouse position from aimDirection and
    // aimDistance to pick a heal target, and the wire format carries it as a ubyte of
    // half-pixels, so anything past 510 is not representable anyway.
    aimDistance = min(510, point_distance(x, y, player.botAimX, player.botAimY));
}

// --- 4. fire ------------------------------------------------------------------------

settled = (abs(botAngleDelta(player.botAimWant, player.botAimDir)) <= BOT_AIM_SETTLE_DEG);

keys = botClassKeys(player, char, subject, dist, subjectIsAlly, tick);

if(!subjectIsAlly and (!canFire or !settled or player.botHoldFire))
{
    keys = keys & ~KEY_ATTACK;
    // A Medic shooting at an enemy is firing needles, and needles are on SPECIAL rather
    // than ATTACK - so for that one class SPECIAL is the trigger and has to answer to the
    // same gates. Every other class's SPECIAL is a reflex and deliberately does not.
    if(player.class == CLASS_MEDIC)
        keys = keys & ~KEY_SPECIAL;
}

if((tick + player) mod BOT_TARGET_PERIOD == 0)
    botServerActions(player, char, target, dist);

player.botAttackKeys = keys;
return keys;
