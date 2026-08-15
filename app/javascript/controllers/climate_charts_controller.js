import { Controller } from "@hotwired/stimulus"
import {
  colorFor, withAlpha, endLabelPlugin, legendAndTooltip, loadChartJs,
  pointRadiusUnlessIsolated, reducedMotion, seriesAriaLabel, timeScaleOptions,
} from "../lib/climate_chart"

// Three stacked time-series charts (temperature, relative humidity, dew point)
// over one shared x-axis, one line per sensor plus the outdoor comparison.
//
// Past two days the server widens the buckets and the mean starts hiding the
// extremes, so each line then also carries a shaded min-max band. The extreme
// is what condenses on a wall.
export default class extends Controller {
  static targets = ["temperature", "humidity", "dewPoint"]
  static values = { series: Array, banded: Boolean }

  #charts = []
  #syncing = false

  async connect() {
    if (this.seriesValue.length === 0) return

    const Chart = await loadChartJs()

    // Turbo can disconnect us mid-import, onto detached canvases.
    if (!this.element.isConnected) return

    this.#charts = [
      this.#build(Chart, this.temperatureTarget, "temperature", "Temperature (°C)", "°C"),
      this.#build(Chart, this.humidityTarget, "humidity", "Relative humidity (%)", "%"),
      this.#build(Chart, this.dewPointTarget, "dew_point", "Dew point (°C)", "°C"),
    ].filter(Boolean)

    // Chart.js is an ES module, so there is no window.Chart. These are the
    // handles for checking what was actually plotted, from the browser tests
    // and from the console when a live page looks wrong.
    this.element.climateCharts = this.#charts
    this.element.dataset.climateChartsReady = String(this.#charts.length)
  }

  disconnect() {
    // Or every Turbo navigation back leaks a canvas and its listeners.
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateChartsReady
  }

  #datasets(measure) {
    return this.seriesValue.flatMap((series) => {
      const color = colorFor(series.color_index)
      const line = {
        label: series.name,
        // spanGaps stays false so the explicit null points the server inserts
        // BREAK the line across an outage rather than interpolating through it.
        spanGaps: false,
        data: series.points.map((point) => ({ x: point.t, y: point[measure] })),
        borderColor: color,
        backgroundColor: color,
        // Second cue for the outdoor line, so it reads apart without relying on hue.
        borderDash: series.outdoor ? [6, 4] : [],
        borderWidth: 2,
        // See pointRadiusUnlessIsolated: an isolated point needs a radius or
        // it vanishes along with the (absent) line either side of it.
        pointRadius: pointRadiusUnlessIsolated(),
        pointHoverRadius: 5,
        tension: 0.2,
      }

      return this.bandedValue ? [...this.#band(series, measure, color), line] : [line]
    })
  }

  // Drawn under the line, max first with fill pointing at the min below it.
  #band(series, measure, color) {
    const shared = {
      label: series.name,
      band: true,
      spanGaps: false,
      borderWidth: 0,
      pointRadius: 0,
      backgroundColor: withAlpha(color, 0.12),
    }

    return [
      { ...shared, fill: "+1", data: series.points.map((p) => ({ x: p.t, y: p[`${measure}_max`] })) },
      { ...shared, fill: false, data: series.points.map((p) => ({ x: p.t, y: p[`${measure}_min`] })) },
    ]
  }

  #build(Chart, canvas, measure, title, unit) {
    if (!canvas) return null

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", seriesAriaLabel({
      title, unit,
      entries: this.seriesValue.map((s) => ({ name: s.name, values: s.points.map((p) => p[measure]) })),
      suffix: "The current readings are also listed as text above this chart.",
    }))

    return new Chart(canvas, {
      type: "line",
      data: { datasets: this.#datasets(measure) },
      plugins: [endLabelPlugin()],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        interaction: { mode: "index", intersect: false },
        // Right padding is measured by the end-label plugin.
        layout: { padding: { right: 0 } },
        scales: timeScaleOptions({ title, unit }),
        plugins: legendAndTooltip({ unit }),
        onHover: (_event, elements, chart) => this.#syncHover(chart, elements),
      },
    })
  }

  // The point of stacking them is reading all three at the same instant.
  #syncHover(source, elements) {
    if (this.#syncing) return
    this.#syncing = true
    try {
      for (const chart of this.#charts) {
        if (chart === source) continue
        const mapped = elements.map((element) => ({
          datasetIndex: element.datasetIndex,
          index: element.index,
        }))
        chart.setActiveElements(mapped)
        chart.tooltip.setActiveElements(mapped, { x: 0, y: 0 })
        chart.update("none")
      }
    } finally {
      this.#syncing = false
    }
  }
}
