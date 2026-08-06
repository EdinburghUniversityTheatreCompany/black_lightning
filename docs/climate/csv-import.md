# Crypt climate monitor: getting readings in

The monitor (`/admin/climate`) charts temperature, relative humidity and dew point from the Govee
sensors in the crypt, against outside conditions.

**Crypt readings arrive as CSV exports from the Govee app. There's no API polling.** That's a
deliberate choice, not a shortcut. See *Why not the API* below.

## The quick version

1. Govee Home, open the sensor, **Export Data**, enter an email address. A CSV arrives.
2. `/admin/climate`, then **Import readings**. Pick the sensor and drop the file in.

Re-importing an overlapping file is harmless. Readings are keyed by sensor and timestamp, so an
overlap overwrites rather than duplicates.

## Why not the API

The Govee Developer API has no history endpoint. `/device/state` answers "what is the value right
now" and nothing else. In a basement with intermittent WiFi that isn't merely unreliable, it's
lossy in a way you can't recover: the sensor records to its own buffer whether or not it has a
connection, and uploads when it next gets one. A poller can only ever sample the present, so
everything buffered during a dropout stays invisible to it. The export has all of it.

Dropping the poller also dropped the API key, the per-account rate limit, and the whole
verify-which-unit-this-sensor-reports dance.

## The unit

An export header names its own unit:

```
Timestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity
2026-08-06 09:22:00,24.6,53.7
```

You'll get `Temperature_Celsius` or `Temperature_Fahrenheit`, depending on what the **app** is set
to display. The importer reads that and converts Fahrenheit on the way in, keeping the original
value alongside.

**A file whose unit can't be identified is refused, never guessed.** Guessing is how a year of
readings ends up silently wrong by thirty degrees. If you hit this, either re-export with the app
set to Celsius, or rename the column so it says which unit it is.

## What else the importer copes with

It's built against a real export, so it handles the UTF-8 BOM Govee puts at the start (which
otherwise swallows the first header), the sampling prose baked into the timestamp column name, the
stray space after the first comma, integers written without a decimal point, CRLF endings, and
tab-separated paste from a spreadsheet.

Timestamps are read as Edinburgh local time, matching what the app exports. Readings outside
-20 to 50 °C or 0 to 100 % get skipped and reported, so one bad line doesn't cost you the rest of
the file.

## Timing

The device holds **about 20 days** before overwriting. The app keeps **up to 2 years**. An
occasional export is enough, but if the crypt has a period worth keeping, export within 20 days of
it. You can drain the buffer over Bluetooth by standing next to the sensor with the app open, so
you don't need WiFi at all.

## Automating it (optional)

`Climate::MailboxPollJob` runs every 15 minutes and imports CSV attachments from a shared mailbox,
using the same parser as the manual upload. To switch it on:

1. Create or pick a shared mailbox, e.g. `climatesensors@bedlamtheatre.co.uk`.
2. Give the Entra app access to it. See [graph-mailbox-rbac.md](../graph-mailbox-rbac.md).
3. Set `CLIMATE_MAILBOX` (fnox in development, credentials in production).
4. Point Govee's scheduled export at that address.

Leave it unset and the job logs and returns, so an environment without a mailbox stays quiet.

### One sensor, for now

Nothing in Govee's export email identifies the device. Not the subject, not the attachment
filename. So the job assumes **one** crypt sensor and imports against it.

With more than one it leaves the message unread and raises an alert (once a day, not once a
cycle), rather than filing one wall's readings under another. To support several later, the only
method that changes is `Climate::MailboxPollJob#sensor_for`: give each sensor its own mailbox or
plus address and resolve on the recipient, or add a per-sensor match string if Govee ever starts
naming the device.

## Reading the dashboard

The number that matters is the **dew-point margin**: air temperature minus dew point, i.e. how far
the air has to cool before it condenses on a surface. Under about 3 °C is worth acting on, and the
tile turns red there.

A **break in a line** is missing data, not a flat reading. Lines are deliberately not drawn across
a gap, because a straight line through an outage reads as a measurement that never happened.

## Outdoor data

Outside conditions come from [Open-Meteo](https://open-meteo.com/): free, no key, modelled for
Bedlam's own coordinates, fetched hourly. Two things follow from that.

- **Attribution is a licence condition** (CC BY 4.0), rendered in the "How this works" panel.
  Don't remove it.
- **The free tier is non-commercial only.** Fine for a student theatre. `Climate::OUTDOOR_SOURCES`
  is the swap point if that ever changes.

Each poll re-fetches a rolling multi-day window and upserts it, so an outage backfills itself.
That self-healing is why Open-Meteo won over sources with a better uptime guarantee but no history.
