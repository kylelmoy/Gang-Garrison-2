/// botSkillLerp(skill, easy, normal, hard, expert)
/// Interpolates one difficulty knob at a bot's skill, given the knob's four sourced
/// values. Returns a real; the caller rounds it if the knob is a tick count.
///
/// Every number in the difficulty table came from a shipped game's own bot tuning -
/// Quake III's chars.h, Counter-Strike's BotProfile.db, TF2's four tiers, Unreal
/// Tournament's eight - and each of those games states its values at four skill levels
/// rather than as a formula. Rather than invent a curve that happens to pass near them,
/// this interpolates linearly between the four anchor skills the sources are quoted at:
///
///     easy 0.15    normal 0.45    hard 0.75    expert 0.95
///
/// so a bot at exactly one of those skills gets exactly the published number, and
/// anything between is a straight line. Outside the range it clamps, which is what makes
/// skill a safe 0..1 scalar rather than one that has to be checked at every call site.
///
/// The knobs are deliberately not derived from one another: a weak bot is meant to be
/// slow (long acquisition, long fire delay) as much as inaccurate, because a bot that
/// reacts late reads as human and a bot that only sprays reads as broken.

var skill, v0, v1, v2, v3;

skill = argument0;
v0 = argument1;
v1 = argument2;
v2 = argument3;
v3 = argument4;

if(skill <= 0.15)
    return v0;
if(skill >= 0.95)
    return v3;
if(skill <= 0.45)
    return v0 + (v1 - v0) * (skill - 0.15) / 0.3;
if(skill <= 0.75)
    return v1 + (v2 - v1) * (skill - 0.45) / 0.3;

return v2 + (v3 - v2) * (skill - 0.75) / 0.2;
