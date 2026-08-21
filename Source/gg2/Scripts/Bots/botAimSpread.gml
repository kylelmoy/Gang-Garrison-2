/// botAimSpread(errDeg, coneDeg, moveMult, moving, sinceSeen, dist)
/// The half-width, in degrees, of the uniform error a bot adds to a solved aim. Pure
/// arithmetic, kept out of botCombatUpdate so the one piece of the difficulty model that
/// is a formula rather than a table can be tested without a Character, a target or a map.
///
///     spread = (errDeg + coneDeg * BOT_AIM_CONE_DECAY^sinceSeen)
///              * (moving ? moveMult : 1)
///              / (BOT_CLOSE_PENALTY + min(dist, BOT_CLOSE_RANGE)/BOT_CLOSE_RANGE
///                                     * (1 - BOT_CLOSE_PENALTY))
///
/// Three effects, from three different games, and they compose rather than compete:
///
/// - The **focus cone** is CS:GO's AimFocusInitial/AimFocusDecay: aim is wildest in the
///   instant after a target is acquired and tightens while the bot keeps looking at it.
///   sinceSeen is ticks since acquisition, so this is what makes a bot's first shot its
///   worst one - which is both realistic and the thing that gives a player time to react.
/// - The **moving-target scale** is CS:GO's AimFocusOffsetScale. Counter-intuitively it
///   *reduces* error at high skill (0.3 at expert): the published tables treat it as how
///   much of the bot's error survives when it has to track, and a good bot tracks.
/// - The **close-range penalty** is Quake III's distance ramp, and it applies at every
///   tier on purpose. Accuracy is scaled by BOT_CLOSE_PENALTY at point-blank rising to 1
///   at BOT_CLOSE_RANGE, so the error it produces is divided by that - a bot is *worse*
///   in a brawl than at mid range. It is an anti-frustration measure, not a difficulty
///   knob: without it bots are unbeatable up close, where a human has the least time to
///   respond.
///
/// The result is a half-width: the caller adds a uniform sample on [-spread, spread].
/// Uniform, not Gaussian - Quake III's crandom() is uniform on [-1, 1] and every error
/// term in the best-regarded bot AI of its generation is built on it.

var errDeg, coneDeg, moveMult, moving, sinceSeen, dist, spread, closeFactor;

errDeg = argument0;
coneDeg = argument1;
moveMult = argument2;
moving = argument3;
sinceSeen = argument4;
dist = argument5;

spread = errDeg + coneDeg * power(BOT_AIM_CONE_DECAY, max(0, sinceSeen));

if(moving)
    spread *= moveMult;

closeFactor = BOT_CLOSE_PENALTY
              + min(max(0, dist), BOT_CLOSE_RANGE) / BOT_CLOSE_RANGE * (1 - BOT_CLOSE_PENALTY);

return spread / closeFactor;
