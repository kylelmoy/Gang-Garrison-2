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
/// Two milestone 7 tier 3 additions ride on the same chain rather than beside it:
///
/// - The target may not be a Character at all - a **Generator** (6.3) or a **Sentry**. It
///   goes through every gate above unchanged, since it is just something to shoot, but
///   almost every field this script reads off a target exists only on a Character, so
///   player.botTargetIsChar is consulted before each of them. GM8 does not short-circuit
///   and/or, so those tests are separate ifs rather than extra clauses; reading onground off
///   a generator is a hard error, not a false.
/// - A **potshot** (3.5) is an ordinary target acquired at a widened radius when there was
///   nothing in the ordinary one. It is only the *search* that widens; everything
///   afterwards, including the fire gates, is identical.
///
/// Aim error is uniform on [-1, 1] scaled by the knob, not Gaussian: Quake III's
/// crandom() is uniform and so is every error term built on it. Two multipliers ride on
/// top - the moving-target scale, and Quake III's close-range penalty, which makes
/// *every* tier worse at point-blank range. That one is an anti-frustration measure
/// rather than a difficulty knob: without it bots are unbeatable in a brawl.

var player, char, tick, range, keepRange, target, subject, subjectIsAlly, valid, dist;
var keys, moving, err, errMult, sinceSeen, canAim, canFire, settled;
var aimX, aimY, delta, subjX, subjY, tgtX, tgtY;

player = argument0;
char = player.object;
tick = frame;
keys = 0;
range = botClassRange(player.class);

// --- 1. see: keep or drop the current target, then look for a new one ---------------

// A target acquired by the potshot roll (M7 3.5) is outside this class's ordinary
// attention radius by construction, so it has to be allowed to *stay* outside it - the
// same band that let it be picked. Without this the shot is taken and the target dropped
// again on the very next tick, which re-pays the whole acquire/fire chain for every
// single potshot and means none of them ever actually leaves the barrel.
keepRange = range;
if(player.botPotshot)
    keepRange = range * BOT_POTSHOT_MULT;

target = player.botTarget;
if(target != noone)
{
    // Never fold these into one boolean expression: GM8 evaluates both sides of and/or
    // unconditionally, so a dead target's .hp would be read even behind instance_exists.
    valid = instance_exists(target);
    if(valid)
    {
        // A Generator or a Sentry has hp and a team and nothing else this chain reads - no
        // cloak, no onground, no player - so its checks are the Character ones minus the
        // fields it does not have. Getting that wrong is not a crash in GM8, it is a silent
        // read of some other instance's variable.
        if(player.botTargetIsChar)
            valid = (target.hp > 0 and !target.cloak and target.team != char.team);
        else
            valid = (target.hp > 0 and target.team != char.team);
    }
    // Measured to the same point botFindTarget measured to when it picked this target -
    // the middle of a map object's body, the chest of a Character. Mixing the two would
    // let a generator be acquired at its centre and dropped on its origin the next tick,
    // over and over, on any map where the two are far apart.
    tgtX = char.x;
    tgtY = char.y;
    if(valid)
    {
        tgtX = target.x;
        tgtY = target.y;
        if(!player.botTargetIsChar)
        {
            tgtX = (target.bbox_left + target.bbox_right) / 2;
            tgtY = (target.bbox_top + target.bbox_bottom) / 2;
        }
        valid = (point_distance(char.x, char.y, tgtX, tgtY) <= keepRange);
    }
    if(valid and (tick + player) mod player.botPerceiveTicks == 0)
    {
        // Losing line of sight is not losing the target (M7 3.8). A peek that breaks LOS
        // for under 30 ticks (a second - "for a beat") keeps its target, and keeps
        // botTargetAt untouched below, so ducking back out costs nothing and re-emerging
        // does not re-pay the whole acquire/fire-delay chain from zero, which is what
        // made a peek-and-retreat free before this. player.botVisible governs whether the
        // aim snapshot below is allowed to update from the target's live position - while
        // blind the bot keeps aiming at (and firing at) where it last actually saw them.
        if(collision_line_bulletblocking(char.x, char.y, tgtX, tgtY))
        {
            player.botVisible = false;
            if(tick - player.botLastSeenAt > 30)
                valid = false;
        }
        else
        {
            player.botVisible = true;
            player.botLastSeenAt = tick;
        }
    }
    if(!valid)
    {
        target = noone;
        player.botTarget = noone;
        player.botTargetIsChar = true;
        player.botPotshot = false;
    }
}

if(target == noone and (tick + player) mod BOT_TARGET_PERIOD == 0)
{
    target = botFindTarget(char, range);
    player.botPotshot = false;

    // Humans take potshots in the general direction of an enemy they cannot really reach
    // (M7 3.5). It costs nothing but ammo, it occasionally lands, and it is one of the
    // few things that reads as a person rather than as a rangefinder. Only when there is
    // nothing in the ordinary band already - a potshot is what you do with an idle
    // trigger finger, not instead of a real engagement.
    //
    // Off for the Pyro, whose Flame simply cannot travel past ~130px, so a long shot is
    // pure ammo waste that also lights up exactly where it is standing; and off for the
    // Medic, whose primary is a heal beam and whose needles at long range are the same
    // deal.
    if(target == noone and botClassProfile(player.class, BOT_CP_POTSHOT)
       and random(1) < BOT_POTSHOT_CHANCE)
    {
        target = botFindTarget(char, range * BOT_POTSHOT_MULT);
        player.botPotshot = (target != noone);
    }

    if(target != noone)
    {
        player.botTarget = target;
        player.botTargetIsChar = botIsCharacter(target);
        // Continuous sight starts now: both the acquisition gate and the focus cone's
        // decay are measured from this tick.
        player.botTargetAt = tick;
        player.botLastSeenAt = tick;
        player.botVisible = true;
        player.botHoldFire = false;
    }
    else
        player.botTargetIsChar = true;
}

// --- the Medic exception: a hurt teammate outranks an enemy -------------------------

subject = target;
subjectIsAlly = false;
if(botClassProfile(player.class, BOT_CP_HEALS))
{
    if((tick + player) mod BOT_TARGET_PERIOD == 0)
        // false: a Medic beaming another Medic is correct play. Only the follow *goal*
        // in botObjectiveUpdate has to exclude them, and it says why.
        player.botAlly = botFindAlly(char, BOT_HEAL_RANGE, false);

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

    // Face the way you're walking (M7 3.1) - without this, aimDirection is never touched in
    // this branch and keeps whatever stale bearing it last held, often at a target that died
    // a screen away.
    //
    // Squarely left or right, not along the velocity vector, which is what this used to do
    // and what reads from outside as a bot staring at the floor as it walks downhill or at
    // the sky on the way up a jump - reported from play as "bots seem to aim in the direction
    // of their velocity". A player with nothing to shoot at holds the crosshair level and
    // ahead, and a level aim is also the one that needs the least slewing when something
    // does appear. Only the horizontal component decides the facing, and only while actually
    // moving horizontally (the same 0.195 dead zone Character's own friction uses to call
    // itself stopped), so standing still keeps the last-held aim rather than snapping.
    if(char.hspeed > 0.195)
        player.botAimWant = 0;
    else if(char.hspeed < -0.195)
        player.botAimWant = 180;

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
    }

    player.botAttackKeys = keys;
    return keys;
}

// Where the subject *is*, for range and for aiming. A Character is anchored at its chest
// (F24) and that is the right point; a Generator is a large map object anchored wherever
// its sprite happens to be, so measure to the middle of its body instead - the same
// correction botFindTarget and botObjectiveUpdate make about the same object.
subjX = subject.x;
subjY = subject.y;
if(!player.botTargetIsChar and !subjectIsAlly)
{
    subjX = (subject.bbox_left + subject.bbox_right) / 2;
    subjY = (subject.bbox_top + subject.bbox_bottom) / 2;
}

dist = point_distance(char.x, char.y, subjX, subjY);

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

// Allies are never occluded here (no LOS check applies to the Medic exception), but an
// enemy subject only refreshes its snapshot while player.botVisible - otherwise this
// would leak the target's live position through the wall it just ducked behind, which is
// the exact bug M7 3.8 fixes. Skipping the refresh while blind is what keeps the aim (and
// therefore the fire) pinned to the last position actually seen.
if((tick >= player.botPerceiveAt or player.botAimSubject != subject)
   and (subjectIsAlly or player.botVisible))
{
    player.botPerceiveAt = tick + player.botPerceiveTicks;
    player.botAimSubject = subject;
    player.botSeeX = subjX;
    player.botSeeY = subjY;
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
    //
    // The generator test is its own if and must stay that way. A Generator has no
    // onground variable at all, and GM8 evaluates both sides of `and` unconditionally -
    // so folding it into the condition below would read onground off a generator every
    // time a Soldier shot one, which is a hard runtime error rather than a false. Its own
    // middle is already the best point on it, so there is nothing to offset anyway.
    if(player.botTargetIsChar)
    {
        if(player.botSplashAim and subject.onground
           and botClassProfile(player.class, BOT_CP_SPLASH))
            aimY += BOT_FEET_OFFSET;
    }

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
        // The class multiplier is applied here rather than baked into the knob by
        // botSkillApply: that script runs once from botAdd, so a baked value goes stale
        // when a bot changes class, and the tier and the class are meant to be
        // independent axes. Both halves of the error scale together - the cone is the
        // same error immediately after acquiring, so scaling one without the other would
        // make a class's aim change shape as it settles rather than just size.
        errMult = botClassProfile(player.class, BOT_CP_AIM_ERR);
        err = botAimSpread(player.botAimErrorDeg * errMult, player.botAimConeDeg * errMult,
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

// How nearly the slew has to have caught up before the trigger is allowed, scaled by
// class: a Heavy laying down area denial should open up while still turning, where a
// Soldier with four rockets should not.
settled = (abs(botAngleDelta(player.botAimWant, player.botAimDir))
           <= BOT_AIM_SETTLE_DEG * botClassProfile(player.class, BOT_CP_AIM_SETTLE));

keys = botClassKeys(player, char, subject, dist, subjectIsAlly, tick);

if(!subjectIsAlly and (!canFire or !settled or player.botHoldFire))
{
    keys = keys & ~KEY_ATTACK;
    // A Medic shooting at an enemy is firing needles, and needles are on SPECIAL rather
    // than ATTACK - so for that one class SPECIAL is the trigger and has to answer to the
    // same gates. Every other class's SPECIAL is a reflex and deliberately does not.
    if(botClassProfile(player.class, BOT_CP_SPECIAL_FIRE))
        keys = keys & ~KEY_SPECIAL;
}

if((tick + player) mod BOT_TARGET_PERIOD == 0)
    botServerActions(player, char, target, dist);

player.botAttackKeys = keys;
return keys;
