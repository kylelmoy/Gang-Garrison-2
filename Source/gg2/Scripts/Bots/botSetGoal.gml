/// botSetGoal(player, wx, wy)
/// Tells a bot to walk to a world position, replacing whatever it was heading for.
///
/// This is the whole interface between navigation and everything above it. Milestone 5
/// gives bots the ability to get somewhere; deciding *where* - the intel, a control
/// point, an enemy to flank - is milestone 6's job, and it will drive this and nothing
/// else. Until then the goal is set by hand, which is also how the follower is tested.
///
/// The route is not planned here. Planning needs the bot's Character to know where it
/// is starting from, and a bot can be given a goal while dead; botPathKeys plans on
/// the next tick it has a body, and re-plans on its own schedule after that.
///
/// WARNING: the old route is deliberately NOT freed. It used to be, and that is half of the
/// "bots momentarily stop moving (no path)" report - between this call and a successful
/// search the bot had nothing to follow, and if the search then failed it had nothing to
/// follow for a whole re-plan window. Keeping it means the bot carries on walking where it
/// was going until there is somewhere better to go, which is the other half of what was
/// asked for. botPathPlan swaps it out the moment it has a replacement.
///
/// botPathStale is what keeps that safe. A route to the old goal is a fine thing to walk
/// along and a terrible thing to *finish*: its last node has nothing to do with the new
/// destination, so botPathKeys must not let the bot declare arrival on it. The flag is
/// cleared by the first successful plan, which is normally the very next tick.

var player;
player = argument0;

player.botGoalX = argument1;
player.botGoalY = argument2;
player.botHasGoal = true;
player.botArrived = false;
player.botArrivedAt = -1;
player.botGoalNode = -1;

// Force the next tick to plan rather than waiting out the re-plan timer of the route
// it was following to somewhere else, and do not let a failed plan sit on that decision.
player.botPathStale = (player.botPath >= 0);
player.botPlanFailUntil = 0;
player.botReplanAt = 0;
