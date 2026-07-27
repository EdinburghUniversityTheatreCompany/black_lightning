# Test suite speedup — done

All numbers measured on this machine, 3027 tests, `docker start /mysql8` first.
Full-suite wall time on this laptop varies ±15% run to run, so only differences
bigger than that are attributed below.

| State | Time |
|---|---|
| Starting point (`power-saver`, serial) | **560s** |
| `performance` power profile, serial | **116–155s** |
| …plus `parallelize`, 8 workers | **37s** |

Roughly 15x, and none of it came from editing a test.

## Why there was nothing to micro-optimise

The cost was **diffuse, not concentrated**: median test 82ms, mean 184ms, p90
479ms. Slowest single file 6.5% of the total; the ~1600 tests under 100ms added
up to 9%. No hot spot — ~82% of the runtime sat in ~1400 mid-weight
functional/controller tests between 100ms and 1s.

So per-test tricks (`build_stubbed`, avoiding DB writes) would each shave a
sliver off a flat distribution. Parallelism was the only lever with a multiplier.

## What was done

**1. Power profile** (no commit — machine setting). `powerprofilesctl set
performance`: **560s → 116s**. An i7-12700H sits at ~500 MHz under `power-saver`.
The tell was a local run losing to a shared 4-core GitHub runner (133s).
*Check `powerprofilesctl get` before ever profiling this suite again.*

**2. bootsnap** (`4b7278f0`). Rails has shipped it by default since 5.2; this app
predates that and never picked it up. Boot **3.12s → 1.72s**; a single-file
`bin/rails test` **4.22s → 2.30s (-46%)**. That is the red-green loop, where boot
was 74% of the run. Negligible on a full-suite run, where boot is a one-off.

**3. Dropped spring** (`0be2b2a4`). In the Gemfile but never wired up — no
`bin/spring`, and `bin/rails` does not load it. Rails dropped it from default
apps in 7.0. Not worth wiring up: bootsnap covers the same boot cost without a
daemon, and this app already has documented boot-state gotchas
(`bin/restart-web`) that a preloader would compound.

**4. `cache_store` in the test env** (`8eb5cc2a`'s parent). test.rb never set one,
so Rails fell back to a **FileStore on `tmp/cache`** — a disk round-trip per
cache call, in a directory shared by every process and never rolled back between
tests. `:memory_store` instead (not `:null_store`; `ImportCacheTestHelpers`
genuinely round-trips the cache). No measurable serial gain — this is a
correctness prerequisite for parallelising.

**5. `better_errors` / `binding_of_caller` out of `:test`** (`8eb5cc2a`). They
attach a `Binding` to exceptions, which cannot be marshalled, so under
`parallelize` every failure became an unreportable worker crash
(`no _dump_data is defined for class Binding`) instead of a readable one. In
practice the run neither passed nor finished: 16 crashes, killed at 25 minutes.
Moving them to `:development` took the same run to a clean 27.7s.

**6. `run_rake_task` made fork-safe.** Minitest's `capture_io` synchronizes on a
shared mutex under `parallelize`; the helper used it and the one test needing the
output of an aborting task wrapped it in a *second* `capture_io`, so one thread
locked one mutex twice → `ThreadError: deadlock; recursive locking`. The helper
now swaps `$stdout` directly and keeps the buffer readable via
`#last_rake_output`. This also un-vacuumed an assertion: with the nesting, the
task's output went to the inner buffer, so `assert_no_match(/Encrypting/, output)`
could never fail.

**7. `parallelize`.** Shared filesystem state split per worker in
`parallelize_setup`: ActiveStorage disk root (both teardowns wiped a hardcoded
`tmp/storage` — another worker's blobs), the generator tests' `tmp/generators`,
and SimpleCov's `command_name`. **155s → 37s**, green both parallel and serial.

## Why workers are capped at 8

Not a hard limit — where the curve flattens. Measured:

| Workers | default MySQL | relaxed durability |
|---|---|---|
| 4 | 49.0s | — |
| 6 | 44.3s | — |
| 8 | **38.9s** | 36.8s |
| 12 | 40.3s | **34.1s** |
| 16 | — | 35.2s |
| 20 (`:number_of_processors`) | 52.1s | 39.5s |

Three limiters stack: the chip reports 20 threads but has 14 physical cores
(6 P + 8 E), and E-cores straggle; each worker is a full Rails process
(memory/cache pressure); and **MySQL is a shared serialization point** — one
server behind the per-worker databases.

That last one is measurable: `SET GLOBAL innodb_flush_log_at_trx_commit=2,
sync_binlog=0` moved the optimum from 8 to 12 and cut the 20-worker case 24%.
The cap stays at **8** because the committed default has to be right against an
untuned MySQL. It is a no-op on CI (fewer cores), and `PARALLEL_WORKERS`
overrides it.

**Optional, not applied:** the `mysql8` container runs full durability for a
throwaway test DB. Making the relaxation permanent
(`--innodb-flush-log-at-trx-commit=2 --sync-binlog=0 --skip-log-bin`) plus
`PARALLEL_WORKERS=12` is worth roughly another 10%. It affects the dev database
too, hence left as a judgement call.

## Not done, deliberately

- **`build_stubbed` / avoiding DB writes** (the netguru tips). 971 `create(:…)`
  against 52 `build(:…)` and no `build_stubbed` at all, so there is real fat —
  but against a flat profile each change buys a sliver. Revisit only if 37s
  starts to hurt.
- **Capybara slow finders** — the entire substance of both codeship articles.
  Audited: none here. Every `assert_not …has_?` is `User#has_role?`, and the one
  `sleep 0.1` is inside a bounded deadline loop. Poltergeist is obsolete; we are
  already on headless Chrome.
- **Devise stretches, stubbing external calls, "switch to Minitest"** — already
  done before this work.
- **YJIT** — not enabled, never measured. Cheap experiment, unknown payoff.
- **CI** — still runs serially. The `test` job is CI's critical path (4m42s vs
  2m20s for the next longest), so enabling parallelize there is the obvious next
  step; the runner has fewer cores so expect ~2x, not 4x.

## Tooling notes

`test-prof` and `stackprof` are in the Gemfile and referenced nowhere. Either
use them or drop them.

The per-file timings came from a throwaway Minitest reporter. **minitest 6 made
`load_plugins` opt-in**, so a `minitest/*_plugin.rb` on the load path silently
never runs — it must be required and pushed onto `Minitest.extensions`.
