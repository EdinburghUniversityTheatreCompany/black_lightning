# Crypt climate monitor — setting up the Govee sensors

The crypt climate monitor (`/admin/climate`) charts temperature, relative humidity and dew point
from the Govee H5179 Wi-Fi thermo-hygrometers in the crypt, against outdoor conditions.

This is the one-time setup. **Step 3 is not optional** — the sensors record nothing until it is
done, and that is deliberate.

## 1. Get a Govee Developer API key

1. Open the **Govee Home** app on the account the crypt sensors are paired to.
2. Go to **Profile → Settings → About us → Apply for API Key**.
3. Fill in the request (name and reason — "monitoring humidity in a theatre basement" is fine).
   The key arrives by email, usually within minutes.

The key is per **account**, and so is the rate limit: 10,000 requests/day across everything using
it. The pollers use about 450/day for three sensors. If this key is ever shared with another
integration (Home Assistant, govee2mqtt), the budgets share, and the poll job logs a warning when
the remaining budget drops below 1,000.

## 2. Store the key

The setting is read ENV-first, then per-environment credentials — `Climate::Settings`.

**Development** — a *reference* in `fnox.toml` (which is gitignored; this repo is public):

```toml
[secrets]
CLIMATE_GOVEE_API_KEY = { provider = "bws", value = "govee-api-key" }
```

Put the real value in Bitwarden Secrets Manager under that name first, or `fnox activate` will fail
on a dangling reference. Never put it in `development.yml.enc` — `development.key` is committed.

**Production** — `bin/rails credentials:edit --environment production`:

```yaml
climate:
  govee_api_key: "…"
```

With no key configured the poll job logs and returns. An unconfigured environment is quiet, not
broken — and the outdoor half keeps working, because Open-Meteo needs no key at all.

## 3. Discover the sensors, then verify each one's unit

1. Go to **/admin/climate/sensors** and press **Discover Govee devices**. Every thermometer on the
   account is added; lights and other devices are ignored. New rows arrive **inactive** and
   **unit-unverified**.
2. For each sensor press **Check unit**. The page shows the raw number Govee just returned and what
   it means read each way, e.g. *"Govee reports 53.6 — that is 53.6 °C if the API reports Celsius,
   or 12.0 °C if it reports Fahrenheit."*
3. **Walk into the crypt with the Govee app open** (or read the sensor's own display) and press the
   button matching what it says.
4. Edit the sensor to give it a useful name and location, then tick **Active**.

### Why this step exists

Govee does not document the unit of `sensorTemperature`, and for these sensors it is widely
reported as **Fahrenheit even when the app displays Celsius**. Ingesting Fahrenheit as Celsius
would store years of unusable history that no later fix can distinguish from real readings.

So `temperature_unit` is nullable with no default, and `Climate::ReadingIngest` **refuses to write**
for a sensor without one. Not recording is recoverable; recording the wrong thing is not.

Getting the answer wrong is recoverable too: every reading stores `raw_temperature` and the unit it
was written under, so the history can be recomputed from the raw values. Come back to **Check unit**
and choose again.

## 4. Check it is working

- `/admin/climate/sensors` shows **Last polled** advancing (every 10 minutes) and **Last error**
  empty.
- `/admin/climate` shows a tile per sensor with plausible crypt values — roughly 8–16 °C and high
  humidity — and the charts fill in as readings accumulate.

There is no backfill for indoor data. The Govee API serves only the current reading and keeps no
history, so the charts start from the moment a sensor is activated.

## Outdoor data

Outside conditions come from [Open-Meteo](https://open-meteo.com/) — free, no key, no signup, and
modelled for Bedlam's own coordinates. Two things follow:

- **Attribution is a licence condition** (CC BY 4.0), not a courtesy. It is rendered in the "How
  this works" panel on the dashboard; don't remove it.
- **The free tier is non-commercial only.** Fine for a student theatre. If that ever changes,
  `Climate::OUTDOOR_SOURCES` is the swap point — any client answering `#hourly_series` with the
  same row shape works, so Met Office DataHub or the NOAA METAR feed at Edinburgh Airport would be
  one new class plus one hash entry.

The outdoor poller asks for a rolling multi-day window every hour and upserts the lot, so an outage
backfills itself on the next successful run. That self-healing property is why Open-Meteo was
chosen over sources with a stronger uptime guarantee but no history endpoint.

## Reading the dashboard

The number that matters is the **dew-point margin**: air temperature minus dew point, i.e. how far
the air has to cool before it condenses on a surface. Under about 3 °C is worth acting on, and the
tile turns red at that point.

A **break in a line** is missing data, not a flat reading — lines are deliberately not drawn across
a gap. A sensor Govee reports as offline records nothing at all, because Govee keeps serving the
last known value for a unit with dead batteries, which would otherwise draw a perfectly flat and
entirely fictional line.
