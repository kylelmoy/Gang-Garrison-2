/// botAdd(team, class, name)
/// Creates a bot Player and joins it to the game exactly like a real client would:
/// roster insertion, PLAYER_JOIN/CHANGETEAM/CHANGECLASS broadcasts, then queues a spawn.
/// Returns the new Player instance.

var team, class, name, player, playerId;
team = argument0;
class = argument1;
name = argument2;

player = instance_create(0,0,Player);
player.isBot = true;
player.name = name;

// The server's 1-5 difficulty setting is one point on a continuous skill scale, in even
// steps, so tiers 1, 4 and 5 land exactly on the anchors the published tuning tables are
// quoted at (botSkillLerp). Everything a bot does differently at a different difficulty
// comes out of the knobs this sets.
botSkillApply(player, 0.15 + (max(BOT_TIER_MIN, min(BOT_TIER_MAX, global.botDifficulty)) - 1) * 0.2);

playerId = ds_list_size(global.players);
ds_list_add(global.players, player);
ServerPlayerJoin(player.name, global.sendBuffer);

class = checkClasslimits(player, team, class);
player.team = team;
player.class = class;
ServerPlayerChangeteam(playerId, player.team, global.sendBuffer);
ServerPlayerChangeclass(playerId, player.class, global.sendBuffer);

// Attack or defend, plus the per-bot goal spread and route seed that make this bot's
// version of a shared objective differ from its team-mates' (M7 tier 3). After the team
// *and* the class are set: it counts the team it is joining, and how often a bot of this
// class defends is a per-class number (botClassProfile). Note that the class it counts
// with is the one checkClasslimits handed back, not the one asked for.
botRoleAssign(player);

if(team != TEAM_SPECTATOR)
    player.alarm[5] = 1; // Will spawn in the same step (between Begin Step and Step)

return player;
