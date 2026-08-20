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

var player;
player = argument0;

player.botGoalX = argument1;
player.botGoalY = argument2;
player.botHasGoal = true;
player.botArrived = false;
player.botGoalNode = -1;

// Force the next tick to plan rather than waiting out the re-plan timer of the route
// it was following to somewhere else.
botPathFree(player);
player.botReplanAt = 0;
