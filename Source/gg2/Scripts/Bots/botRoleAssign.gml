/// botRoleAssign(player)
/// Gives one bot an attacking or a defending role by counting positions down the roster:
/// every Nth bot defends and the rest attack, where N comes from the bot's own class.
///
/// Nothing in the bot code distinguished attacking from defending before this (M7 6.3),
/// which is why every mode read the same way - the entire team running at the enemy
/// objective in single file and nobody ever behind them. Generator is the mode where the
/// two jobs are most explicitly separate (each team both defends its own generator and
/// attacks the other's), but CTF wants it just as much: a flag nobody is guarding is a
/// flag that leaves and does not come back.
///
/// Assigned once, when the bot joins or is re-teamed, rather than re-decided per tick.
/// A role that changes while a bot is walking somewhere is indistinguishable from a bot
/// that cannot make up its mind, and the whole value of the split is that it reads as
/// team composition from the outside.
///
/// Counting rather than rolling a die is deliberate: with three bots on a team, a 1-in-3
/// roll gives all-attack about 30% of the time, and "the split sometimes just does not
/// happen" is not a thing anyone can debug from a screenshot.
///
/// The class term is the period N, not a veto, and that distinction is the whole design.
/// The obvious rule - "Engineers and Heavies defend, Scouts and Spies attack" - breaks at
/// both ends: a team of nine Engineers would have nobody attacking and a team of nine
/// Scouts nobody defending, and both are compositions botPopulationUpdate can produce,
/// since it picks a class with irandom(8). Making the class choose *how often* instead
/// keeps a split at every composition: an all-Engineer team runs half defenders, an
/// all-Scout team one in six, and a mixed team draws its defenders disproportionately from
/// the classes suited to it. With every class on BOT_DEFEND_EVERY it reduces exactly to the
/// old behaviour.
///
/// ⚠️ The count is over the bots that share this bot's *period*, not over the whole team.
/// Counting the whole team would make the period meaningless in a mixed team - two
/// Engineers separated by four Scouts would sit at positions 0 and 5 and neither would land
/// on a multiple of 2. Sharing a period is what makes a lean group: Engineer and Heavy
/// count together as one defensive pool, Scout and Spy as one offensive pool, everyone else
/// as the third, which is also why this reads botClassProfile rather than the class itself.
///
/// ⚠️ What is counted is this bot's *position among its team's bots in the roster*, not
/// how many team-mates it has. The difference is the whole correctness of the rule: a
/// count of team-mates is the same number for every bot on the team, so on a team of
/// three it would make all three defenders at once and on a team of four it would make
/// none. A position gives 0, 1, 2, 3... down the roster, which is what produces one
/// defender in every BOT_DEFEND_EVERY. It also makes the first bot on a team an attacker
/// every time, which is the right default when there is only one, and it is stable - a
/// bot's position only changes when someone ahead of it leaves.
///
/// ⚠️ global.players can hold -1 for a dangling roster entry, and -1 is GM8's `self` -
/// so `mate.team` on one would silently read the *caller's* team rather than failing.
/// The guard is the explicit != -1 below; instance_exists cannot help here.
///
/// ⚠️ The loop variable is `mate` and not the obvious `other`, because `other` is a GM8
/// *keyword* (the other instance in a with/collision block) and `var ... other;` is a
/// compilation error that takes the whole game down at startup - the game launches,
/// paints, answers a ping and does nothing. It cost one build here. gg2_lint does not
/// catch this one: it checks the built-in *variable* list, and `other` is not on it.

var player, i, mate, place, every;

player = argument0;
place = 0;
every = botClassProfile(player.class, BOT_CP_DEFEND_EVERY);

for(i = 0; i < ds_list_size(global.players); i += 1)
{
    mate = ds_list_find_value(global.players, i);
    if(mate == -1)
        continue;
    if(mate == player)
        break;
    if(!mate.isBot)
        continue;
    if(mate.team != player.team)
        continue;
    if(botClassProfile(mate.class, BOT_CP_DEFEND_EVERY) != every)
        continue;
    place += 1;
}

if(((place + 1) mod every) == 0)
    player.botRole = BOT_ROLE_DEFEND;
else
    player.botRole = BOT_ROLE_ATTACK;

// The per-bot goal spread (M7 2.4) is derived here too, because it is "what makes this bot
// different from its team-mates" and it must be constant for the bot's whole life - a spread
// that changes re-issues the goal every time it is read.
//
// The id is a plain instance id, so consecutive bots differ by 1: `mod 2` alternates the
// side and the second term walks the magnitude around an 11-cycle, which is enough spread
// for any team size a GG2 server runs and is exactly reproducible from a bot's id.
//
// A per-bot route seed used to be derived here as well, on the same reasoning. It fed a cost
// jitter in navFindPath that produced no route variety at all - measured on ctf_truefort,
// all eight bots got the identical route, because per-edge noise averages out over a long
// path and leaves the ordering between routes untouched - so it is gone and route variety
// is a shared occupancy penalty instead (navFindPath, botOccupancyAdd). ROUTEVARIETY.md is
// the handoff. Anything that wants a stable per-bot number again can derive it from
// `player` exactly as the spread below does.
//
// WARNING: the spread assignment below was deleted along with the route seed, and the
// comment describing it was left behind - so botSpreadX sat at its Create-event 0 for
// every bot and the whole M7 2.4 spread quietly did nothing. test_botskill asserts
// `abs(botSpreadX) <= BOT_SPREAD_MAX`, which 0 satisfies, so nothing caught it.
player.botSpreadX = ((player mod 2) * 2 - 1) * BOT_SPREAD_MAX * (((player * 7) mod 11) / 10);

return player.botRole;
