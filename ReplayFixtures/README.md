# Replay Fixtures

Recorded command streams that every later build must replay to the same
states (Stage F3b, ARCHITECTURE decision 51). They port the reference's
desync tooling (`Railway/railway_game_reference_clean/docs/desync.md` §2.2,
§3.1, §3.2 and `01_MIGRATION_MAP.md`, "Determinism / debugging": a command
log, state checksums at intervals, replay test fixtures).

Each file holds:

- a starting world, saved as GameCore saves a world;
- the commands a network campaign generated on it, valid and refused alike;
- a checksum of the state before the first command, after every
  `interval` commands, and after the last.

`Tests/GameCoreTests/ReplayFixtureTests.swift` replays every file. Each
checksum must come out the same, and every world on the way must keep the
invariants. The first checksum that differs names the stretch of commands
where the states part. That is how the reference narrows a desync down
between two saves.

A checksum covers the game itself: time, money and the accounts, the track
network and its platforms, stations and their passengers, every train's
place, body, path, service and timetable, lines and their patterns, and
riders (`ReplayState`). It is not the save's bytes. So a change to how a
world is saved that keeps every value leaves the checksums alone, and a
changed checksum is a change of behaviour. Commands are written as plain
values (`ReplayCommand`), not with GameCore's own coding, which refuses
values a world cannot hold.

Rules, as for the golden scenarios and the save fixtures:

- Never edit a checksum, or record a file again, to make a test pass.
- A deliberate change of behaviour that moves a checksum is recorded again
  in the pull request that makes it. The pull request names each fixture
  whose checksums moved and why.
- Record with
  `REPLAY_RECORD="$PWD/ReplayFixtures" swift test --filter ReplayFixtureTests/testRecordingTheFixtures`.
  Each fixture comes from a campaign case: the first one from its recipe's
  index (`ReplayFixture.recipes`) whose clock is running and not near the
  end of time.

| File | Recorded from | What it runs |
| --- | --- | --- |
| `kernel.json` | `kernel.differential` | Track, stations, platforms and trains moved by hand on a generated network. |
| `repeating-services.json` | `service.repeating` | Timetables that turn trains round and repeat, among the kernel's commands. |
| `line-dispatch.json` | `line.dispatch` | Lines that send their trains out, with targets, windows, service days and rings. |
| `line-patterns.json` | `line.patterns` | Lines with patterns (short workings and expresses) and the load on each stretch. |
| `economy.json` | `economy.differential` | Passengers boarding lines' trains, fares, and the accounts over hours and days. |
| `network-economy.json` | `economy.differential` | The same case with network passenger routing (Phase 5F): journeys across lines, transfers, crowding and demand by generalized time. Recorded with the recipe's `networkRouting`; recording the other recipes again gave the same checksums. |
| `long-leg-traffic.json` | `LongLegReplayTests.world()` | Long legs under traffic control (NEXT_PRIORITIES 2026-10-12 §2 item 6): a local and an express ring line on 80 km of single track with passing loops, legs of 20 to 23 km whose routes hold thousands of spans; trains follow each other and meet head on. Until decision 344 they ended in a deadlock the dispatcher tried to resolve every minute; since then a train bound for A takes A's loop when its main track is held, and none deadlocks (recorded again in that pull request, checksums 2 to 5). Decision 364 recorded it again (checksums 1 to 5): its ring trains standing at C now run round to A and on for a whole lap from there, rather than lapping from C back to C, so their laps begin where the passengers' do; the commands and the start are unchanged, and `testNoTrainDeadlocksOverTheThreeHours` keeps every train free of deadlock. Built by hand, not from a campaign case, and recorded with the route reservation that came before it was made faster (main `77dc286`), which must replay it unchanged. Record it with `REPLAY_RECORD="$PWD/ReplayFixtures" swift test --filter LongLegReplayTests/testRecordingTheFixture`. |
| `problem-report-blank-map.json` | `Reports/blank-map.json` | A problem report's command log (decision 193): track, stations and platforms from the network tool on a blank map, a refused platform, the speed and game time between them. Converted by `ProblemReportFixtureTests`, not recorded from a campaign. |

Stage F3c removes the grid from GameCore without changing any game
behaviour. These files hold no grid command and no grid content, so they
must replay unchanged across it.

Stage F3d (ARCHITECTURE decision 54) makes the world its bounds in world
units and measures fares between stations' points. The starting worlds here
keep the `"map"` of tiles a world was saved with before save version 6;
GameCore reads it as bounds of 1024 units a tile, and a checksum does not
cover the bounds. Every station in these files stands at the centre of what
was a tile, so its fares are the same. They replay unchanged and were not
recorded again.

Decision 193 adds fixtures converted from problem reports. A report the
app shares (`command-log.json`, GamePresentation's `CommandLogReport`)
holds the save its game started from and the player's commands; reports
kept as examples are in `Reports/`. One from a world that reads nothing
from the app's data, whose commands the fixtures can say, converts with
`PROBLEM_REPORT=<report.json> REPLAY_RECORD="$PWD/ReplayFixtures" swift test --filter ProblemReportFixtureTests/testConvertingAReport`.
The rest replay through a session with the app's data
(`Tests/GamePresentationTests/CommandLogReplay.swift`). The same rules
hold: a converted fixture is added, never converted again to make a test
pass.
