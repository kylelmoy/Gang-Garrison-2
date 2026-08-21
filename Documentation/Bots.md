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
4. **Navigation** — built once per map load, server-only, from the walkmask
   (`global.CustomMapCollisionSprite`), chunked across frames so it never blocks socket servicing
   and cached to disk keyed by map MD5. Nodes are run-length-encoded standable surfaces; edges are
   analytic rather than a full trajectory fan, each generator using GG2's own movement numbers —
   walks and one-cell steps, straight-down falls, drop-throughs, jump arcs against the real
   `v0`/gravity envelope, and movebox pushes. The fan of F35 remains the endpoint; what is built is
   its cheap first pass, and every edge it emits has to be one a bot can actually execute.
5. **Combat/behaviour** — target selection modelled on `SentryTurret`'s End Step (a `ds_priority`
   over nearby `Character`s, LOS via `collision_line_bulletblocking`), plus per-class firing policy
   and a difficulty model (aim error, reaction latency, decision cadence).
6. **Configuration** — `[Bots]` section in `gg2.ini`, plus a **Bots** tab in the hosting menu:
   whether bots are enabled, how many players to fill to, a cap, a minimum number of humans, a name
   prefix, whether removal waits for death, and `Difficulty` (1-5), which becomes the skill scalar
   every behaviour knob is derived from.

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
- **A whole-map nav build is seconds of blocking work** — fine in the map editor, not fine as a
  blocking loop on a live server. Chunk it across frames from an alarm, and cache the built graph
  to disk keyed by map MD5 so the expensive path runs once per map ever.
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
- **M4** — nav graph builder: implemented (`Scripts/BotNav/`) and verified. The walkmask is scanned
  into a solidity grid, dilated by the character box into a clearance grid, and run-length encoded
  into surface nodes; edges come from five generators (walk, fall, drop-through, jump, movebox)
  plus one-way doors, and A\* (`navFindPath`) searches them against a prebuilt adjacency index. The
  build is chunked across frames so it never blocks socket servicing, and cached to disk keyed by
  map name, area and MD5. Map objects the walkmask does not contain — `PlayerWall`,
  `DropdownPlatform`, `KillBox`/`PitFall`/`FragBox`, `LeftDoor`/`RightDoor`, the gates, the
  moveboxes — are stamped in separately by `navMarkInstances`. `cp_dirtbowl` (560k cells) builds in
  ~11.7s cold with a client connected, both ends holding 30 fps, and loads from cache instantly
  after.
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
  - **Not yet implemented**: Demoman sticky-jumping, Engineer sentry *placement* strategy (it
    builds where it stands), Spy flanking routes, and field of view as a difficulty knob. Bots also
    do not yet target sentries, only Characters.
