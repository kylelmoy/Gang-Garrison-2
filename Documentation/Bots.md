# NPC Bots

Design notes for server-side AI players ("bots"). This is a condensed copy of the working
research/design record; see the project's planning notes for full findings (F1-F41) if you need
the "why" behind something here.

## The core idea

The server is authoritative and broadcasts every player's *inputs* each tick; clients simulate
locally from them (`Character.events/User Event 12.xml`, `GameServerBeginStep.gml`). So a bot is
nothing more than a server-side `Player` whose `Character.keyState` / `netAimDirection` /
`aimDistance` are written by AI code instead of by `processClientCommands`. Movement, weapons,
damage, the kill log, the scoreboard, and chat bubbles all already work unmodified. **Vanilla
clients need zero changes** and can join a bot-enabled server without any patch.

Design rule: bots must be expressible entirely through *existing* wire messages. Do not touch
`PROTOCOL_UUID` or widen the protocol.

## Architecture, coarsest first

1. **Bot identity** — `isBot` flag on `Player` (default `false`). Three call sites treat a `Player`
   as if it owned a real socket and must be guarded:
   - `GameServerBeginStep.gml`'s roster loop (`socket_has_error`/`kicked` reaping) — bots skip the
     socket-error check but still honour `kicked`, so the admin kick UI works on them for free.
   - `GameServerEndStep.gml`'s broadcast loop (`write_buffer(socket, ...)`).
   - `Scripts/Plugins/API/PluginPacketSendTo.gml` and `acceptJoiningPlayer.gml`'s multi-client-IP
     count.
   Slot accounting (`getNumberOfOccupiedSlots.gml`) excludes bots, so bots never cost a human a
   `SERVER_FULL`. Class limits, team balance, the scoreboard, and the Arena "wait for players"
   check already iterate `with(Player)` and count bots automatically — no change needed there.
2. **Population manager** — server-side, decides bot count per team from human count / target
   fill / difficulty; adds/removes on join, leave, and map change; picks classes via
   `checkClasslimits`. Bots must be re-teamed after every map change (the engine drops every
   `Player`, bots included, to spectator on map change; humans get a menu to re-pick, bots don't).
3. **Input driver** — per bot, per virtual (30 Hz) tick: compute `keyState` / `aimDirection` /
   `aimDistance` on the bot's `Character`, then call `event_user(1)` so `pressedKeys`/`releasedKeys`
   edge detection fires (jump, cloak, taunt all depend on this). Lives in
   `GameServerBeginStep.gml`'s roster loop, in the `else` branch beside
   `processClientCommands(player, i)` — the same point a human's `INPUTSTATE` is consumed, so
   ordering matches a human's by construction.
4. **Navigation** — server-only, **loaded** from a graph file generated ahead of time (see
   *Generating nav graphs* below). Nodes are run-length-encoded standable surfaces; edges are
   analytic rather than a full trajectory fan, each generator using GG2's own movement numbers —
   walks and one-cell steps, straight-down falls, drop-throughs, jump arcs against the real
   `v0`/gravity envelope, and movebox pushes. The fan of F35 remains the endpoint; what is built is
   its cheap first pass, and every edge it emits has to be one a bot can actually execute. What
   ships in `Scripts/BotNav/` is the *reading* half: the cache loader, the two indices it derives,
   world-to-node resolution, and A\* over the result.
5. **Combat/behaviour** — target selection modelled on `SentryTurret`'s End Step (a `ds_priority`
   over nearby `Character`s, LOS via `collision_line_bulletblocking`), plus per-class firing policy
   and a difficulty model (aim error, reaction latency, decision cadence).
6. **Configuration** — `[Bots]` section in `gg2.ini`, plus a **Bots** tab in the hosting menu:
   whether bots are enabled, how many players to fill to, a cap, a minimum number of humans, a name
   prefix, whether removal waits for death, and `Difficulty` (1-5), which becomes the skill scalar
   every behaviour knob is derived from.

## Generating nav graphs

The graph is not built by the game. `Scripts/BotNav/navCacheLoad.gml` reads it from
`botnav/<map>_a<area>[_<md5>].txt` beside the executable, and that is the only way one enters the
game. Files come from [`gg2-nav-gen`](../../gg2-nav-gen), a standalone Node port of the generator
that reads the map PNGs directly:

```console
$ node bin/gg2navgen.js build --all       # every shipped map, every stage, ~0.4s
$ node bin/gg2navgen.js build koth_valley # one map
$ node bin/gg2navgen.js build ./mymap.png # a custom map, by path
```

It writes into `Source/build/botnav` by default, which is where a dev build reads from, so
`build --all` warms the whole rotation in place. For a release, ship the same files in a `botnav`
directory next to `Gang Garrison 2.exe`.

**A map with no file is a map with no bot navigation.** `navGraphLoad` leaves the state
`NAV_BUILD_IDLE` and `global.navReady` false, bots do not path, and the server keeps serving the
map to humans normally. It retries every five seconds, so dropping a freshly generated file into
`botnav/` is picked up by a running server without a restart.

Two things stay in sync by hand:

- **`Constants.xml` is the shared contract.** `gg2-nav-gen` parses `NAV_*` and `TEAM_*` out of this
  checkout at run time rather than copying them, so a geometry or field-layout change lands there
  on the next run. Several `NAV_*` constants — the jump envelope, the per-side keep limits, the
  node and edge field indices — therefore have no GML reader any more and must not be deleted:
  they define the file format and the generator's behaviour.
- **`NAV_CACHE_VERSION` guards the layout.** Bump it whenever a node or edge field moves, or a
  server with a warm cache silently loads a graph whose columns mean something else. `navCacheLoad`
  refuses a file that does not carry the current version.

## Gotchas worth remembering

- **Never call `place_free` / `collision_point_solid` from nav or AI code.** Collision solidity is
  toggled on/off every frame (`charSetSolids`/`charUnsetSolids`) and is `false` outside that
  bracket, so those calls silently report open space everywhere. Use
  `collision_point(px, py, CustomMapO, false, true)` (precise mask, solidity-independent) instead.
  `collision_line_bulletblocking` is exempt — it's object-typed, not solidity-typed — and is safe
  to call from anywhere, including target-selection AI.
- **Every new object/script/constant costs a full Game Maker build.** Splice-only changes to
  existing script bodies are fast; new resources are not. `AgentSpare0..3` (four blank objects
  already compiled into the dev template) let a *new object's* behaviour be prototyped at ~3s
  before promoting it to a real named object.
- **A whole-map nav build is seconds of blocking work**, which is why the game no longer does one.
  It used to: a chunked builder spread ~1.3s of work across frames so it never stalled socket
  servicing, and cached the result so the expensive path ran once per map ever. That was the right
  shape for a live server and the wrong shape for *developing* the generator, where every one-line
  change to a cost function cost a full Game Maker build, a launch, and a rotation through every
  map to re-warm the cache. The generator moved out to `gg2-nav-gen`, which does all 22 shipped
  maps in under half a second from the map PNGs alone. The lesson generalises: work that depends
  only on static map data does not belong on a server tick.
- **Where a jump takes off from is a search, and what rules a takeoff out is what is above it.**
  Every jump in GG2 rises until something stops it, so a low ceiling over the end of a run shortens
  every arc that starts there, and one low enough leaves no arc that reaches the target at all —
  while two cells along there is headroom and the same jump is clean. Nothing about where the arc
  aims can fix that, which is what makes it a search over takeoffs. *(This search was originally
  added for a different case — a body flush against a crate it is trying to climb — which turned
  out to be an artefact of the arcs being far too fast, and went away when the flight model was
  fixed. Stepping back from a crate is actively counter-productive: the same landing from further
  away is a faster arc, and faster is what fails. When an arc fails, check **where** it was
  rejected before theorising about what it was aiming at.)*
- **A jump edge is flown as a trajectory, not as a speed.** The generator validated one specific
  arc, and every cell it checked for clearance is about that arc: the follower's job in the air is
  to be where the plan says it should be by *this* tick, pressing when it is behind and braking when
  it is ahead. Holding the arc's speed instead sounds equivalent and is not — a bot leaves the
  ground from a standstill and spends four or five ticks reaching a slow arc's speed, which is most
  of a cell of ground it can never make back, and any nudge in the air is permanent. Measured over
  every class, rise, ledge width and run-up, landing on the intended node went from 12–19% to 100%.
  Two details this depends on: the speed and duration are recorded **unrounded** (rounding
  0.54px/tick to 1 moves the landing two cells), and the elapsed ticks are counted rather than read
  off `vspeed`, which pins at 10 once a fall reaches terminal velocity and then reports every later
  tick as the same one.
- **A jump ends where the arc comes back down, and nowhere else.** GG2's jump is a fixed impulse:
  there is no short jump and no variable jump height, so the flight time is a function of the rise
  alone and the horizontal distance is only a constraint on the speed. Both of the plausible
  shortcuts are wrong, and both have shipped here. "When the character is first horizontally over
  the target" is true on the first tick of a drop, which credits a ledge with every surface below
  it. "When it first draws level with the target" is true seventeen ticks before a steep climb
  lands, which makes the arc fast enough to sail over an 18px ledge by four cells. Both make the
  bogus edges look *cheap*, so they also crowd the real ones out of the per-side keep limit. The
  descending half of the arc must be checked against the node grid, **swept** over the rows it
  crosses rather than point-sampled, because a node occupies one row of the mask and a falling arc
  rounds past it.
- **Hitting your head is a kind of jump, not a failed one.** A ceiling zeroes `vspeed` and the
  character comes down from there, landing exactly where a shorter arc lands. Refusing to model that
  throws away every climb under an overhang — on `koth_valley` it left the node on the valley floor
  with incoming falls and no outgoing anything, because the step up out of it happens to sit under
  one. `navJumpCeiling` measures the climb a takeoff actually has and the whole arc is derived from
  it.
- **Aim into the surface being landed on, not at its nearest column.** A node's span starts
  `NAV_BOX_W-1` columns before the solid it stands on, because an anchor counts as standable when
  any one of the four footprint cells is supported — so the nearest anchor is the one where the body
  hangs off the edge by three cells of four, and landing a pixel short of it is a fall. A couple of
  columns of lead is the difference between 62–76% and 100%. The lead has to be tried against real
  geometry and given up when it does not fly, though: a bigger lead is a longer arc over the same
  fixed airtime, so it is a *faster* one, and a faster arc is already drifting sideways while it is
  still level with the thing it is climbing onto.
- **The vertical arc is exact, in both directions, if you use the discrete form.** `Character`'s
  Step event adds half a tick's gravity, moves, then adds the other half, and midpoint integration
  of a constant acceleration lands on the continuous curve at every integer tick — so
  `v0*t - g*t²/2` is not an approximation here. Past terminal velocity it is: `vspeed` clamps at
  10px/tick, which a jump reaches after 30.5 ticks, and ignoring that underestimates the deepest
  drops the graph allows by 15% — which becomes a 15% *over*estimate of the speed the arc needs.
- **A goal offset must be applied *after* the objective resolves to a node, not before.**
  `botNodeSnap` searches *downward*, so snapping an already-offset position can land several
  storeys below the objective — the offset steps off the edge of the platform the intel is on and
  the search falls all the way to the ground floor, and the bot then walks confidently somewhere
  with nothing to do with its objective. The objective's own node resolves first and an offset snap
  is accepted only within a body height of it. Any future "nudge the goal" feature has this trap.
- **Two behaviours that each move a bot away from its objective will silently compose.** Once your
  team holds a point, an attacker walks out toward the enemy spawn and takes *that* ground; a class
  with its own positioning opinion stands somewhere else again. Running both left the Spy's flank
  anchored 400px from the objective, so the sightline it was carefully avoiding was to somewhere
  the objective was not — measured 243px out with a *clear* line to the point, the exact opposite
  of what was asked. Neither half looks wrong on its own. They are two answers to the same
  question, so exactly one of them may apply.
- **Not every anchor is a thing you shoot at.** `botGoalSpot`'s line-of-sight test is right for an
  objective and wrong for a waypoint: an Engineer's chokepoint is a bare point on a route between
  two places and can land inside a wall or above a roof. On `koth_valley` only 6 of 26 in-band
  nodes had a clear line to it, so the best-first search spent its whole `BOT_SPOT_TRIES` budget
  and returned nothing — and the Engineer fell back to standing on the very point it was supposed
  to be covering. Proximity was the whole requirement; that is what `BOT_LOS_ANY` is for.
- **A positioning behaviour must never override a goal the bot has to physically reach.** The CTF
  intel is *picked up*, so a class that stops short of it and waits never captures — and since
  `botPopulationUpdate` picks with `irandom(8)`, a whole team can roll that class and the round
  simply never ends. Standing off is only ever correct for an objective that is covered, held or
  shot.
- **Almost nothing in GG2 is hitscan.** Only the Sniper Rifle is true hitscan; every other weapon
  (including Scattergun, Shotgun, Minigun, Revolver) drops with per-tick gravity. A bot's aim
  solver needs drop compensation on all of them, not just the obviously-lobbed Minegun — a `Shot`
  crossing the 375px combat radius sags about 64px, a whole character height. Note the sag after
  `t` ticks is `gravity*t*(t+1)/2`, not `gravity*t²/2`: the engine adds gravity to `vspeed` before
  it applies the move, so the discrete form is the exact one.

## Status

- **M0** — `isBot` flag, the three socket guards, and slot accounting: implemented and verified
  against a live server + client session.
- **M1** — `botAdd(team, class, name)` / `botRemove(player)` roster insertion: implemented
  (`Scripts/Bots/botAdd.gml`, `Scripts/Bots/botRemove.gml`) and verified — a bot added this way is
  visible identically on the host and a real connected client, spawns a class-correct `Character`,
  can be damaged and killed (producing a correctly attributed kill-log line), and removal is
  broadcast like a real disconnect.
- **M2** — population manager, `[Bots]` ini config, and hosting menu tab: implemented
  (`Scripts/Bots/botPopulationUpdate.gml`, `botPickTeam.gml`, `botReteamAll.gml`;
  `BotsMenuController`) and verified — bots are added/removed automatically to track
  `FillToPlayers`/`MaxBots`/`MinHumans`, removal respects `RemoveOnDeath`/`RemoveTimeoutSeconds`
  (deferred until death or timeout rather than an abrupt kick), the lobby broadcast reports the
  real bot count, and `botReteamAll` correctly re-teams/re-classes bots reset to spectator by a map
  change.
- **M3** — input driver: implemented (`Scripts/Bots/botInputUpdate.gml`, `botFindTarget.gml`) and
  verified — bots pick the nearest visible enemy in range (`SentryTurret`-style `ds_priority` +
  `collision_line_bulletblocking`), aim and hold fire at it, and re-decide only every 15 ticks
  (staggered per bot) rather than tracking continuously. Confirmed via genuine bot-vs-bot combat
  (real kills, real respawns) and a direct `event_user(1)`/`pressedKeys` edge-detection check.
- **M4** — nav graph builder: implemented and verified, then **moved out of the game**. The
  walkmask is scanned into a solidity grid, dilated by the character box into a clearance grid, and
  run-length encoded into surface nodes; edges come from five generators (walk, fall, drop-through,
  jump, movebox) plus one-way doors, and A\* (`navFindPath`) searches them against a prebuilt
  adjacency index. Map objects the walkmask does not contain — `PlayerWall`, `DropdownPlatform`,
  `KillBox`/`PitFall`/`FragBox`, `LeftDoor`/`RightDoor`, the gates, the moveboxes — are stamped in
  separately rather than read from the mask. All of that now lives in `gg2-nav-gen`; what remains
  in `Scripts/BotNav/` is the loader, the indices, and the search. The in-game builder chunked
  itself across frames so it never blocked socket servicing (`cp_dirtbowl`, 560k cells, ~11.7s cold
  with a client connected and both ends holding 30 fps); the offline one does every shipped map in
  under half a second, which is why the chunking, the eleven build states and the scaffolding grids
  are all gone.
- **M5** — path following: implemented (`Scripts/Bots/botSetGoal.gml`, `botPathPlan.gml`,
  `botPathKeys.gml`) and verified. `botSetGoal(player, wx, wy)` is the entire interface — deciding
  *where* is M6's job. Gate passability is decided per query from the asking bot's team and intel
  carriage rather than baked into the graph, since a gate is not a wall to everyone. The follower
  re-plans on a slow timer, on being stuck, and immediately on finishing a move somewhere the route
  does not go, and blacklists the edge that misled it. Verified on `gg_debug`: a bot walks from
  spawn to a named point through a drop-through platform, back uphill over jump edges, and through
  its own team gate, arriving within a few pixels each time.
- **M6** — objectives, aim, per-class policy and difficulty: implemented.
  - **Objectives per game mode** (`Scripts/Bots/botObjectiveUpdate.gml`): implemented and verified.
    The game mode is inferred from which objects exist, the same way `basicRoomSetup` does it, since
    nothing stores it. CTF/Invasion bots fetch the enemy intel and run it home once carrying;
    Generator bots move on the enemy generator; KOTH, Arena, A/D and symmetrical CP all share one
    branch that targets the nearest *unlocked* control point's `CaptureZone`, which spreads bots
    across a multi-point map for free; DKOTH is special-cased because each team caps the other
    team's point. TDM issues no goal — there is no landmark to seek — so bots there keep the
    pre-M6 behaviour of fighting whatever comes into range. Goals are recomputed on a coarse
    cadence and only reissued when the target actually moves, because issuing one forces a re-plan.
    Verified live on `ctf_truefort`, `gen_destroy`, `koth_valley`, `cp_egypt` and `dkoth_sixties`.
  - **Aim** (`Scripts/Bots/botAimLead.gml`, `botAimSolve.gml`): implemented and verified. Bots
    solve drop compensation and target leading together, rather than aiming straight at a target
    the way they did through M3. `botAimLead` is pure arithmetic — one fixed-point iteration on the
    flight time, since rearranging the projectile's equations of motion turns the problem back into
    a straight-line aim at a virtual point — and `botAimSolve` is the per-weapon table on top of
    it, falling through to a direct aim for the Rifle and the Medigun's heal beam. Unit-tested in
    `Scripts/Unit tests/botaim/` against a forward simulation of `move_all_bullets` itself, so the
    solver and the engine cannot silently disagree.
  - **Jump execution** (`navJumpFlight`, `navJumpHeight`, `navJumpCeiling`, `navJumpLanding`,
    `botPathKeys`): implemented and verified. A jump edge now describes one specific arc — where it
    leaves from, how much climb the ceiling above that leaves it, which column of the target it
    aims at, how long it is in the air and how fast it crosses — and the follower flies that arc as
    a trajectory rather than holding its speed. This is what makes a *chain* of steep jumps work,
    where each link has to land for the next to be attempted. Verified on `koth_valley`: a bot
    placed on the valley floor climbs all four steep jumps to the control point and stands on the
    capture zone, where it previously managed one or two links in eight times the frames. All three
    `gg_debug` legs from M5 still pass and are roughly twice as fast as when they were recorded.
  - **Per-class firing policy** (`Scripts/Bots/botClassKeys.gml`, `botClassRange.gml`,
    `botServerActions.gml`): implemented and verified. Each class has an engagement range that is
    its weapon's real reach rather than a preference — a Pyro's flames die at ~130px and a Rifle is
    limited by sight — and it is both the target-search radius and the outer edge of the firing
    band, so a bot never tracks what it could not shoot. Minimum bands exist only where firing
    would hurt the shooter: a Soldier or Demoman does not fire inside its own blast radius.
    `SPECIAL` is not one action, so the policy is per class: a Pyro airblasts an incoming
    `Rocket`/`Flare`/`Mine` in front of it when it has the 40 ammo the blast costs; a Demoman
    detonates the moment any mine it owns has an enemy on it, since the key detonates all of them
    at once; a Medic holds the heal beam on the teammate who most needs it (scored by health
    fraction, then by how much the body can absorb) and pops Uber only with an enemy inside 200px,
    and fires needles on `SPECIAL` alone when there is no one to heal; a Spy re-cloaks when nothing
    is in front of it, uncloaks to shoot, and attacks while cloaked inside stab range. Cloak has to
    arrive as a rising edge rather than a held bit, so that branch throttles itself.
  - **The actions that are not key bits** (`Scripts/GameServer/serverToggleZoom.gml`,
    `serverBuildSentry.gml`, `serverEatSandvich.gml`): zoom, build and eat are client *commands*,
    not bits in the input byte, so a bot cannot press them. Rather than duplicate their
    preconditions, the bodies of those three cases were extracted from `processClientCommands` into
    scripts that both paths call. A Sniper zooms past 400px and unzooms inside 250 (two thresholds,
    so a target stepping over one line does not toggle a broadcast every cadence); an Engineer
    builds when nothing is shooting at it; a Heavy eats when hurt and out of the fight.
  - **Difficulty tiers** (`Scripts/Bots/botSkillApply.gml`, `botSkillLerp.gml`, `botAimSpread.gml`,
    `botCombatUpdate.gml`): implemented and verified. `[Bots] Difficulty` is 1-5 and becomes one
    skill scalar per bot, which drives eleven knobs interpolated between values published by games
    that shipped bot ladders — Quake III's `chars.h`, Counter-Strike's `BotProfile.db`, TF2's four
    tiers, Unreal Tournament's eight. The shape that matters is that a weak bot is **slow**, not
    just inaccurate: `see -> acquire -> aim-settled -> fire` is four separate gates, and a tier-1
    bot takes 83 frames from a target appearing to its first shot where a tier-5 bot takes 7.
    Between them sit a target snapshot that only refreshes every few ticks (perception lag), a
    desired aim recomputed on its own interval, and an aim that slews toward it at a limited turn
    rate — tracking lag, overshoot and settling all fall out of those three numbers, with no filter
    anywhere. Aim error is uniform rather than Gaussian, as Quake III's is, and carries a decaying
    focus cone after acquisition, a moving-target scale, and Quake III's close-range penalty, which
    makes *every* tier worse point-blank on purpose: it is an anti-frustration measure, since
    without it bots are unbeatable in a brawl. Target leading is gated the same way Quake III gates
    it — none, then one linear prediction, then the full iterated intercept — which is legible from
    the receiving end: linear leading lands a Shot on a target running 6px/tick at 150px and misses
    it by 46px at 375px, where the full solve still connects.
  - **Verified live** on `gg_debug` with a dedicated server at 30 fps: first-shot latency 83 frames
    (tier 1) against 7 (tier 5); aim held 0.1-0.9 degrees off the true bearing at tier 5 against a
    0-12 degree swing at tier 1; a tier-1 bot against a tier-5 bot over 2400 frames went 6 kills
    and 11 deaths to 11 and 6. Every `SPECIAL` policy and all three non-keybyte actions were
    checked against a live server: zoom in at 500px and out at 200, a sentry built, a sandvich
    eaten only when hurt, airblast held back at 10 ammo and fired at 200, a mine detonated only
    with an enemy on it, and the Spy's four cloak states. `Scripts/Unit tests/botskill/` covers the
    knob table, the error formula, the leading ladder and the class bands in 88 assertions.
  - **Not yet implemented as of M6**: Demoman sticky-jumping, Engineer sentry *placement* strategy
    (it builds where it stands), Spy flanking routes, and field of view as a difficulty knob. Bots
    also do not yet target sentries, only Characters. M7 and M8 below close the placement and
    flanking items; the rest stand.
- **M7** — the first human playtest's backlog, in four tiers. Tiers 1-3 implemented and verified;
  tier 4 investigated and deliberately declined.
  - **Tier 1, the small-diff/large-effect findings**: target gravity in the aim solve; target
    memory across a lost line of sight (a peek that breaks LOS for under a second keeps its target,
    so ducking back out costs nothing and re-emerging does not re-pay the whole acquire/fire
    chain); facing the direction of travel when there is nothing to aim at; a real goal during the
    30-60s KOTH/DKOTH/Arena lock-in instead of standing frozen at spawn; Sniper charge-gating;
    jump-to-dodge and a low-rate evasive hop; and wandering near an already-captured point instead
    of freezing on it forever. Also a difficulty rebalance: aim error compressed hard (12/6/2.5/0.7
    degrees to 4/1.5/0.5/0.2) and leading ungated from skill, because GG2's projectiles are slow
    and a target can reverse direction in one tick, so evasion already supplies the miss rate a
    hitscan game needed aim error for — stacking both spent the difficulty budget twice.
  - **Tier 2, nav-graph reachability**: 8 of 24 shipped maps had an objective no bot could path to.
    All 8 fixed, in four changes, each re-audited across all 24 cached graphs with no regression.
    (1) `navJumpTakeoff`'s search was anchored at the source run's own end, which is only correct
    when the target lies beyond that end; it is now anchored at the column nearest the target,
    clamped into the source's span. (2) and (3) `NAV_JUMP_MAX_PER_SIDE`, a "keep the cheapest N
    landings per source/direction" cap meant to fight redundant-link explosion, was discarding the
    *only* edge connecting a 115-node region to the rest of the graph, because cheaper
    mutually-redundant local hops filled the quota first. Raised 3→4, and `navJumpEdges` now keeps
    one bonus slot past the quota for whichever remaining candidate is cheapest *and* lands more
    than `NAV_JUMP_DIVERSITY_ROWS` from every already-kept landing — targeting "reaches somewhere
    different" directly rather than hoping a bigger cutoff happens to reach deep enough.
    (4) `NAV_MAX_FALL` was 40 rows: tuned for the ordinary case and never stress-tested against a
    map built around one deliberately extreme drop. Raised to 150 rows (900px) after confirming GG2
    has no fall damage anywhere in `Character`'s Step event.
  - **Tier 3, the goal layer** (`botGoalSpot.gml`, `botSetGoalNode.gml`, `botNodeSnap.gml`,
    `botClassMinBand.gml`, `botRoleAssign.gml`, `botEnemySpawn.gml`): implemented and verified. The
    one new idea is a goal expressed as a **predicate over nodes** rather than a world point:
    `botGoalSpot(char, tx, ty, minDist, maxDist, losSense, highBonus)` answers "where do I stand in
    order to do something to that", ranked cheaply over every node and paying for
    `collision_line_bulletblocking` only on the best `BOT_SPOT_TRIES` of them. Four separate
    findings wanted the same thing and none of them wanted a point: a firing position on a
    generator (which is *shot*, not stood on — at 2100 hp that is a sustained-fire job from range,
    and bots had never damaged one before, because `botFindTarget` iterated `with(Character)` and
    nothing else), ground overlooking a point we already hold, pushing past a captured objective
    toward the enemy, and the Medic's follow position. On top of it, `botRoleAssign` splits a team
    into attackers and defenders — nothing in the bot code distinguished the two before, which is
    why every mode read the same way, the whole team running at the enemy objective in single file
    with nobody behind them.
  - **Tier 4 was declined, and three of its four items build nothing.** The Demoman's "instant
    detonation" is *correct behaviour*, confirmed by measuring mine lifetimes live (4-23 ticks,
    every detonation with an enemy inside the blast): the mine is a direct-fire projectile that
    lands beside the target it was aimed at, so trap-laying is a new feature, not a repair.
    Double-jump and rocket-jump nav edges: no shipped map needs one, and rocket-jump would break
    the "combat owns ATTACK, navigation owns movement" invariant three scripts rely on.
- **M8** — per-class strategy: implemented and verified live.
  - **`botClassProfile(class, field)`** (`Scripts/Bots/botClassProfile.gml`) is the single home for
    every per-class fact not already owned by a named table script. Six per-class tests used to sit
    inline in shared scripts — four in `botCombatUpdate`, one each in `botInputUpdate` and
    `botObjectiveUpdate` — each defensible where it sat, but collectively "what does a Pyro do
    differently" was a four-file grep. `botClassRange`, `botClassMinBand`, `botClassKeys` and
    `botServerActions` were deliberately left alone: each is named for its one question and read
    from several places, so folding them in would trade four clear names for four more field
    constants. A class's knowledge now lives in exactly five places and `botClassProfile`'s own
    header is the index to all five.
  - **Class-aware roles**: the class supplies *N* in "one bot in every N defends" (2 for
    Engineer/Heavy, 3 default, 6 for Scout/Spy) rather than vetoing the answer outright. The
    obvious rule — "Engineers defend, Scouts attack" — breaks at both ends and both ends are
    reachable, since `botPopulationUpdate` picks a class with `irandom(8)`: an all-Engineer team
    would have nobody attacking and an all-Scout team nobody defending. With every class on the
    default period it reduces exactly to the pre-M8 behaviour.
  - **Per-class positioning**: four modes on top of `botGoalSpot` — a Sniper and a Heavy stand off
    from the objective inside their own weapon's reach, an Engineer takes a chokepoint on the route
    between the objective and the enemy spawn, and a Spy stages *out of sight of* the objective.
    Bands are derived from `botClassRange` rather than written out per class, so they stay correct
    when a weapon's reach is retuned. The Spy's flank needed `botGoalSpot`'s `needLOS` boolean
    generalised into a `BOT_LOS_ANY`/`NEED`/`AVOID` sense.
  - **Verified live** on `koth_valley` and `ctf_truefort`: a defending Sniper takes a position
    352px back with a clear sightline to the point, a Heavy 305px back and high, an Engineer a
    chokepoint on the route out of its own base, and a Spy a spot 152px from the objective with no
    line to it. `Scripts/Unit tests/botskill/` grew to 246 assertions.
  - **Still not implemented**: Demoman sticky-jumping, field of view as a difficulty knob, bots
    targeting sentries, per-class route costs, and per-class difficulty knobs.
