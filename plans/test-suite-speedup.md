# Test suite speedup

All numbers below are measured on this machine against the same 3027 tests
(`bin/rails test`, `docker start /mysql8` first), 2026-07-27.

| State | Time |
|---|---|
| Starting point (`power-saver`, serial) | **560s** |
| `performance` power profile, serial | **116s** |
| `performance` + `parallelize` 8 workers | **27.7s** |
| CI `test` job, same 3027 tests, for reference | 133s |

That is ~20x, and none of it comes from editing a test.

## Why there is nothing to micro-optimise

The cost is **diffuse, not concentrated**: median test 82ms, mean 184ms, p90
479ms. The slowest single file is 6.5% of the total; the ~1600 tests under 100ms
add up to only 9%. There is no hot spot. Roughly 82% of the runtime sits in
~1400 mid-weight functional/controller tests between 100ms and 1s.

So per-test tricks (`build_stubbed`, avoiding DB writes) each shave a thin slice
off a flat distribution. Parallelism is the only lever with a real multiplier.

## Phase 1 — power profile (done)

`powerprofilesctl set performance`. **560s → 116s**, no code change. An
i7-12700H sits at ~500 MHz under `power-saver`. The tell was a local run losing
to a shared 4-core GitHub runner.

Nothing to commit; noted so the next person doesn't re-profile a throttled box.

## Phase 2 — `cache_store` in the test env

`config/environments/test.rb` never sets `cache_store`, so Rails falls back to a
**`FileStore` on `tmp/cache/`**: a real disk round-trip on every cache call, and
a directory shared by every future parallel worker that is never rolled back
between tests.

```ruby
# config/environments/test.rb
config.cache_store = :memory_store
```

`:memory_store`, not `:null_store` — `ImportCacheTestHelpers` genuinely
round-trips the cache. Verified: fixes `mailbox_poll_job_test.rb` 3/3 under 4
workers, where the shared FileStore had been breaking the rate-limit tests.

Worth doing on its own merits even if parallelize never lands.

## Phase 3 — dev-only gems out of the test group

`better_errors` and `binding_of_caller` are in `group :development, :test`. They
attach a `Binding` to exceptions, which cannot be marshalled — so under
`parallelize` *every* test failure becomes an unreportable worker crash
(`no _dump_data is defined for class Binding`) and the run never finishes.

```ruby
group :development do
  gem "better_errors"
  gem "binding_of_caller"
end
```

Verified: this is what took the parallel run from "16 DRb crashes, killed at 25
minutes" to a clean 27.7s.

While here: `spring` is in the Gemfile but never wired up — there is no
`bin/spring` and `bin/rails` doesn't load it. It is dead weight at boot. Remove
it rather than wire it up; Spring is not in Rails 8 defaults.

## Phase 4 — per-worker isolation

Two remaining pieces of shared filesystem state:

```ruby
# test/test_helper.rb
parallelize_setup do |worker|
  svc = ActiveStorage::Blob.service
  svc.root = "#{svc.root}-#{worker}" if svc.respond_to?(:root=)

  Rails::Generators::TestCase.descendants.each do |klass|
    klass.destination_root = "#{klass.destination_root}-#{worker}"
  end
end
```

And **both** teardowns in `test_helper.rb` (`ActiveSupport::TestCase` and
`ActionController::TestCase`) currently `rm_rf` the hardcoded
`Rails.root.join("tmp", "storage")` — that is another worker's data. They must
remove `ActiveStorage::Blob.service.root` instead.

Also needs handling if `COVERAGE=1` is used: per-worker SimpleCov `command_name`
plus a merge in `parallelize_teardown`. **Untested so far.**

Verified: with these, the generator + attachment + ActiveStorage tests pass under
4 workers.

## Phase 5 — make `run_rake_task` fork-safe

`test/support/rake_task_test_helpers.rb` deadlocks in a forked worker:

```
Reimbursements::EncryptionTest#test_the_backfill_task_refuses_to_run_while_support_unencrypted_data_is_off
ThreadError: deadlock; recursive locking
  test/support/rake_task_test_helpers.rb:28
```

Confirmed parallel-only — the same file passes with `PARALLEL_WORKERS=1` and
fails with 4 or 8 workers. This is the **one remaining failure** in the 27.7s
run. Either make the helper fork-safe or keep rake-task tests out of the parallel
set.

## Phase 6 — turn it on

```ruby
# test/test_helper.rb
parallelize(workers: :number_of_processors)
```

**116s → 27.7s** on 8 workers. Do not enable until phase 5 is green.

Then mirror it in CI. The runner has fewer cores so the multiplier is smaller,
but the `test` job is CI's critical path (4m42s; next longest job is 2m20s), so
it is still the best lever there. System tests stay `PARALLEL_WORKERS=1`.

## Deliberately not doing

- **`build_stubbed` / avoiding DB writes** (the netguru tips). There are 971
  `create(:…)` against 52 `build(:…)` and no `build_stubbed` at all, so there is
  real fat here — but against a flat profile each change buys a sliver. Revisit
  only after parallelize, and only if 27.7s still feels slow.
- **Capybara slow finders** — the entire substance of both codeship articles.
  Audited: this suite has none. Every `assert_not …has_?` hit is `User#has_role?`,
  not Capybara, and the one `sleep 0.1` is inside a bounded deadline loop. The
  Poltergeist advice is obsolete; we are already on headless Chrome.
- **Devise stretches, mocking external calls, switching to Minitest** — already
  done.
- **YJIT** — not enabled anywhere and never measured here. Cheap experiment,
  unknown payoff; parallelize first.

## Tooling note

`test-prof` and `stackprof` are both in the Gemfile and referenced nowhere in the
repo. Either use them or drop them.

Per-file timings above came from a throwaway Minitest reporter. Note that
**minitest 6 made `load_plugins` opt-in**, so a `minitest/*_plugin.rb` on the
load path silently never runs — it has to be required and pushed onto
`Minitest.extensions` from `test_helper.rb`.
