# Project Black Lightning

This version of the Bedlam website (named Project BlackLightning) was built primarily during semester 1 of the 2012/13 academic year.

It got a big upgrade in the summer of 2020 to Rails 6 and some useful features got added, such as wiki login integration.

In 2022 Alex Mohan Morzeria-Davidovitch and Mick Zijdel redesigned the website, making it more responsive and modern. A great many features were also polished over this time, and acts almost as a Version 2 of the website. It was also upgraded to Rails 7 and Node 16 during this time.

If you would like to get involved in editing/running the Bedlam website, please contact the EUTC's IT Subcommittee (it@bedlamtheatre.co.uk). You can find a guide at https://wiki.bedlamtheatre.co.uk/en/docs/it/website/development.

## Tech stack

Current key versions (kept in sync with the manifests — `Gemfile.lock`, `package.json`):

| Layer | Tool | Version |
| --- | --- | --- |
| Framework | Rails | 8.1 |
| Language | Ruby | 4.0.2 |
| Database | MySQL | 8 (multi-database: primary, queue, cache) |
| Auth | Devise | 5.0 |
| Components | ViewComponent | 4.12 |
| Hotwire | Turbo | 8.0 |
| JS bundler | Vite (`vite_rails`) | 8.1 / 3.11 |
| JS runtime | Node | 24.13.0 |
| JS sprinkles | Stimulus | 3.2 |
| CSS | Tailwind | v4 |
| Package manager (JS) | pnpm | 10.x |

## Development setup

Toolchain versions are pinned with [mise](https://mise.jdx.dev) (`mise.toml` + `mise.lock`), and
pre-commit checks run through [hk](https://hk.jdx.dev) (`hk.pkl`). First-time setup:

```sh
mise install        # provisions hk, pkl, gitleaks, node (verified against mise.lock)
hk install          # installs the git pre-commit hooks (replaces the old overcommit setup)
bundle install
pnpm install
```

Run the app with `bin/dev` (Puma + Vite via foreman). Run the checks CI runs with `hk run check`;
run the test suite with `bin/rails test test:system` (start the test DB first — see the
development guide). Lint JS with `pnpm lint`.

## The Fine Print

The website is currently maintained by:

* Mick Zijdel (2020 - 2022) <mick.zijdel@bedlamtheatre.co.uk>
* [Alex Mohan Morzeria-Davidovitch](https://github.com/AlexMohanMD) (2020 - 2023) <me+git@alexmmd.com>
* Lewis Eggeling (2022 - ?) <lewis.eggeling@bedlamtheatre.co.uk>

Based on the original project, the work of Team Adjective-Noun, comprising:

* Hayden Ball <hayden@haydenball.me.uk>
* Tom Turner <tom@tomturner.org.uk>
* Craig Snowden <craig@craigsnowden.com>
* Lewis Eason <me@lewiseason.co.uk>

With further additions by
* Kyle Cooke

with support of the EUTC.
