/// botPickTeam()
/// Picks whichever team has fewer players, ties broken randomly - used when adding or
/// re-teaming a bot, since bots have no team-select menu to answer themselves.

var redCount, blueCount;
redCount = 0;
blueCount = 0;
with(Player)
{
    if(team == TEAM_RED)
        redCount += 1;
    else if(team == TEAM_BLUE)
        blueCount += 1;
}

if(redCount < blueCount)
    return TEAM_RED;
else if(blueCount < redCount)
    return TEAM_BLUE;
else
    return choose(TEAM_RED, TEAM_BLUE);
