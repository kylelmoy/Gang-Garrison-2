/// botSkillApply(player, skill)
/// Sets a bot's difficulty knobs from one master scalar, skill in [0, 1]. Called once
/// when a bot is created; the knobs are plain fields on the Player afterwards, so a
/// single bot can be retuned by hand (a test, a future per-class or per-name profile)
/// without going through this script again.
///
/// The five tiers the server exposes map onto skill in even steps:
///
///     tier 1  0.15   easy     tier 2  0.35   tier 3  0.55
///     tier 4  0.75   hard     tier 5  0.95   expert
///
/// so tiers 1, 4 and 5 land exactly on the sourced anchors (see botSkillLerp) and 2 and
/// 3 are interpolated. Every knob below is quoted easy/normal/hard/expert in that order.
///
/// The four latencies are the point of the whole model, and they are four rather than
/// one on purpose. Quake III gates aiming at half its reaction time and firing at the
/// full value, and Counter-Strike carries ReactionTime and AttackDelay separately;
/// modelling see -> acquire -> aim-settled -> fire as four gates is what makes a weak
/// bot feel *slow* rather than merely *inaccurate*, which reads far better to a player.
/// Community consensus on CS's ladder is that AttackDelay does most of the work: its
/// range is 0 to 1.5 s where ReactionTime spans only 0.2 to 0.5 s.
///
/// Knobs, with where the numbers come from:
///
/// - botAcquireTicks    30/15/9/6    ticks of continuous sight before the bot aims at a
///                                   target at all (TF2 1.0->0.2 s, CS 0.5->0.2 s).
/// - botFireDelayTicks  45/21/10/0   further ticks before it may pull the trigger
///                                   (CS AttackDelay 1.5->0 s).
/// - botPerceiveTicks   15/10/5/1    how often the target's position and velocity are
///                                   re-read. Q3 refreshes an enemy's position every
///                                   0.5 s, which buys perception lag for free.
/// - botAimInterval     8/5/3/2      how often the desired aim direction (and its error
///                                   sample) is recomputed from that snapshot
///                                   (TF2 aiming interval 0.25->0.05 s).
/// - botTurnRate        6/7.5/9/24   degrees per tick the aim slews toward it (UT's
///                                   turn-speed ladder). Tracking lag, overshoot and
///                                   settling all fall out of these two numbers - no
///                                   smoothing filter, and it is the CPU throttle too.
/// - botAimErrorDeg     4/1.5/0.5/0.2  half-width of the uniform angular error. Compressed
///                                   hard from the UT-sourced 12/6/2.5/0.7 (M7 3.4):
///                                   GG2's projectiles are slow and a target can reverse
///                                   direction in one tick, so evasion already supplies
///                                   the miss rate a hitscan game like UT needed aim error
///                                   for. Aim error stacked on top just spent the
///                                   difficulty budget twice; the four latency gates above
///                                   are left untouched; they are what is still working.
/// - botAimConeDeg      20/10/4/1    extra error immediately after acquiring, decaying
///                                   by BOT_AIM_CONE_DECAY per tick (CS:GO's
///                                   AimFocusInitial / AimFocusDecay).
/// - botMoveErrMult     1/0.6/0.4/0.3  error multiplier while the target is moving
///                                   (CS:GO AimFocusOffsetScale).
/// - botHoldFireChance  0.35/0.15/0.05/0  chance a legal shot is not taken, which is
///                                   Q3's firethrottle: a weak bot hesitates rather than
///                                   spraying, and hesitation is legible.
/// - botLeadMode        2/2/2/2      always the full iterated solve (M7 3.4). Q3 gates
///                                   leading on aim_skill 0.4 and 0.8, but under-leading
///                                   is not a legible difficulty signal to a player - it
///                                   just reads as a bad shot, and it was what made tier 4
///                                   read as worse than tier 3 (both BOT_LEAD_LINEAR, so
///                                   tier 4's only visible difference was a faster turn
///                                   rate closing on a shot it still wasn't leading).
/// - botSplashAim       off/off/on/on  aim at a grounded target's feet with a splash
///                                   weapon (Q3 gates this at aim_skill > 0.6).
///
/// ⚠️ Rounding the tick counts uses floor(x + 0.5), not round(): GM8's round() is
/// banker's rounding, so round(2.5) is 2 and round(3.5) is 4.

var player, skill;

player = argument0;
skill = max(0, min(1, argument1));

with(player)
{
    botSkill = skill;

    botAcquireTicks   = floor(botSkillLerp(skill, 30, 15, 9, 6) + 0.5);
    botFireDelayTicks = floor(botSkillLerp(skill, 45, 21, 10, 0) + 0.5);
    botPerceiveTicks  = max(1, floor(botSkillLerp(skill, 15, 10, 5, 1) + 0.5));
    botAimInterval    = max(1, floor(botSkillLerp(skill, 8, 5, 3, 2) + 0.5));
    botTurnRate       = botSkillLerp(skill, 6, 7.5, 9, 24);
    botAimErrorDeg    = botSkillLerp(skill, 4, 1.5, 0.5, 0.2);
    botAimConeDeg     = botSkillLerp(skill, 20, 10, 4, 1);
    botMoveErrMult    = botSkillLerp(skill, 1, 0.6, 0.4, 0.3);
    botHoldFireChance = botSkillLerp(skill, 0.35, 0.15, 0.05, 0);

    // Every tier gets the full iterated solve now (M7 3.4) - see the knob table above.
    botLeadMode = BOT_LEAD_FULL;

    botSplashAim = (skill >= 0.6);
}
