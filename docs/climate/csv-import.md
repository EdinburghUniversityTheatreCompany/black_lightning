# Crypt climate monitor — getting readings in

The monitor (`/admin/climate`) charts temperature, relative humidity and dew point from the Govee
sensors in the crypt against outdoor conditions.

**Crypt readings arrive as CSV exports from the Govee app. There is no API polling.** That is a
deliberate choice, not a shortcut — see *Why not the API* below.

## The quick version

1. Govee Home → open the sensor → **Export Data** → enter an email address. A CSV arrives.
2. `/admin/climate` → **Import readings** → pick the sensor → drop the file in.

Re-importing an overlapping file is harmless: readings are keyed by sensor and timestamp, so an
overlap overwrites rather than duplicates.

## Why not the API

The Govee Developer API has no history endpoint — `/device/state` answers "what is the value right
now" and nothing else. In a basement with intermittent WiFi that is not merely unreliable, it is
*lossy in a way that cannot be recovered*: the sensor records to its own buffer regardless of
connectivity and uploads whatever it has when it next gets a connection, but a poller can only ever
sample the present, so everything buffered during a dropout is invisible to it. The export has all
of it.

Removing the poller also removed the API key, the per-account rate limit, and the whole
verify-which-unit-this-sensor-reports dance.

## The unit

An export header names its own unit:

```
Timestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity
2026-08-06 09:22:00,24.6,53.7
```

`Temperature_Celsius` or `Temperature_Fahrenheit`, depending on what the **app** is set to display.
The importer reads it and converts Fahrenheit on the way in, keeping the original value alongside.

**A file whose unit cannot be identified is refused, never guessed.** Guessing is how a year of
readings ends up silently wrong by thirty degrees. If you hit this, either re-export with the app
set to Celsius, or rename the column so it says which unit it is.

## What else the importer copes with

Built against a real export, so: the UTF-8 BOM Govee puts at the start (which otherwise swallows
the first header), the sampling prose baked into the timestamp column name, the stray space after
the first comma, integers written without a decimal point, CRLF endings, and tab-separated paste
from a spreadsheet.

Timestamps are read as Edinburgh local time, matching what the app exports. Readings outside
-20…50 °C or 0…100 % are skipped and reported — one bad line does not cost you the rest of the file.

## Timing

The device holds **about 20 days** before overwriting. The app keeps **up to 2 years**. So an
occasional export is enough, but if the crypt has a period worth keeping, export within 20 days of
it. You can drain the buffer over Bluetooth by standing next to the sensor with the app open — no
WiFi needed.

## Automating it (optional)

`Climate::MailboxPollJob` runs every 15 minutes and imports CSV attachments from a shared mailbox,
using the same parser as the manual upload. To switch it on:

1. Create or pick a shared mailbox, e.g. `climate@bedlamtheatre.co.uk`.
2. Extend the Entra app's `ApplicationAccessPolicy` to cover it — this is the same app registration
   the reimbursements mailbox uses (`Graph::Settings` reads `GRAPH_*`, falling back to the existing
   `REIMBURSEMENTS_AZURE_*` names).
3. Set `CLIMATE_MAILBOX` (fnox in development, credentials in production).
4. Point Govee's scheduled export at that address.

Unset, the job logs and returns — an environment without a mailbox is simply quiet.

**Which sensor an emailed file belongs to** is the one genuinely awkward part, because the CSV
carries no device identifier. The job matches a sensor whose name appears in the subject or the
attachment filename, and falls back to the only sensor when there is just one. Anything ambiguous
is **left unread and logged** rather than guessed, so it waits for a human instead of attributing
one wall's readings to another. Name each sensor to match what Govee calls it and this resolves
itself.

## Reading the dashboard

The number that matters is the **dew-point margin**: air temperature minus dew point, i.e. how far
the air has to cool before it condenses on a surface. Under about 3 °C is worth acting on, and the
tile turns red there.

A **break in a line** is missing data, not a flat reading — lines are deliberately not drawn across
a gap, because a straight line through an outage reads as a measurement that never happened.

## Outdoor data

From [Open-Meteo](https://open-meteo.com/) — free, no key, modelled for Bedlam's own coordinates,
fetched hourly. Two consequences:

- **Attribution is a licence condition** (CC BY 4.0), rendered in the "How this works" panel. Don't
  remove it.
- **The free tier is non-commercial only.** Fine for a student theatre. `Climate::OUTDOOR_SOURCES`
  is the swap point if that ever changes.

Each poll re-fetches a rolling multi-day window and upserts it, so an outage backfills itself.
