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
6. **Configuration** — `[Bots]` section in `gg2.ini`, plus a **Bots** tab in the hosting menu.

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
- **Where a jump takes off from is a search, not the end of the run.** A character is 4 mask cells
  wide and anchored at its *left* column, so standing at the very end of a surface puts its body
  flush against whatever ends that surface. If that is also the thing being jumped onto — a crate, a
  step, a ledge — the body already occupies the landing's columns at floor level and every arc is
  rejected on its first sample, whichever column it aims at. Stepping the takeoff a few cells back
  makes the identical jump fine. This one cost `koth_valley` 257 of its 270 nav nodes, and survived
  an investigation that varied the *landing* column instead and concluded the geometry was
  impassable. When an arc fails, check where it was rejected before theorising about what it was
  aiming at.
- **A jump edge has to be flown at the speed it was validated at.** The generator records a
  per-arc horizontal speed, and for a steep climb that is 1–3 px/tick because the arc spends most of
  its time going up. A character holding a direction key reaches nearly ten, so a follower that
  simply holds the key sails past the landing and the graph's promise about where it ends up means
  nothing. Governing this needs both halves: stop pressing in the air *and* brake before the jump,
  because with no key held the engine bleeds only ~13% of horizontal speed per tick.
- **A jump arc has to be simulated all the way to where the character lands, not to where it is
  first horizontally over its target.** Those are the same moment when jumping up onto a ledge and
  wildly different when dropping down onto a floor, where "over it, and above it" is true on the
  first tick of the jump. Stopping there credits a ledge with every surface below it regardless of
  what is in between, and because those edges look cheap they crowd the real ones out of the
  per-side keep limit. `navJumpFlight` is where the two cases are separated; the descending half of
  the arc must also be checked against the node grid, *swept* over the rows it crosses rather than
  point-sampled, because a node occupies one row of the mask and a falling arc rounds past it.
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
- **M6** — objectives and aim: partly implemented.
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
  - **Not yet implemented**: per-class firing policy (engagement bands, the right-click behaviours,
    Medic needles versus heal beam) and the difficulty tiers. Bots currently all shoot at the same
    accuracy and cadence, and hold fire at whatever they can see.
