/// botPickClass()
/// Picks the class a newly added bot spawns as.
///
/// This was irandom(8) inline in botPopulationUpdate - every class from Scout to Pyro with
/// equal weight, Quote excluded because it is not part of the normal roster. It is a script
/// now for one reason: the roster needs to be able to exclude a class, and a bare irandom
/// over a contiguous range cannot.
///
/// The Spy is out for now, by request after playtesting. Nothing about the Spy's own code is
/// known to be broken; the problem is that almost everything a Spy does is invisible to the
/// rest of the bot model. It spends most of its life cloaked, so botFindTarget skips it and
/// team-mates route around a fight it is standing in; its whole value is a backstab, which is
/// one botClassKeys branch behind a range test; and a bot doing all of that badly is
/// indistinguishable from a bot that is broken, which makes every other behaviour harder to
/// judge from a playtest. Banning it is cheaper than tuning it and it costs the roster one of
/// nine classes.
///
/// Rejection sampling rather than a shuffled list, because the excluded set is one class out
/// of nine: the loop expects 1.125 draws and the alternative is a table that has to be kept
/// in step with the class constants by hand.

var class;

class = CLASS_SPY;
while(class == CLASS_SPY)
    class = irandom(8);

return class;
