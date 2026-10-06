import {
  ClimateChartController, colorFor, withAlpha, endLabelPlugin, legendAndTooltip,
  lineDataset, reducedMotion, seriesAriaLabel, timeScaleOptions,
} from "../lib/climate_chart"

// Three stacked charts (temperature, humidity, dew point) on one x-axis, a line
// per sensor plus the outdoor comparison. Past two days the mean hides the
// extremes, so each line also carries a shaded min-max band: the extreme is
// what condenses.
export default class extends ClimateChartController {
  static targets = ["temperature", "humidity", "dewPoint"]
  static values = { series: Array, banded: Boolean }

  #syncing = false

  build(Chart) {
    return [
      this.#chart(Chart, this.temperatureTarget, "temperature", "Temperature (°C)", "°C"),
      this.#chart(Chart, this.humidityTarget, "humidity", "Relative humidity (%)", "%"),
      this.#chart(Chart, this.dewPointTarget, "dew_point", "Dew point (°C)", "°C"),
    ]
  }

  #datasets(measure) {
    return this.seriesValue.flatMap((series) => {
      const color = colorFor(series.color_index)
      const line = lineDataset({
        label: series.name, points: series.points, key: measure, color,
        // Second cue for the outdoor line besides hue.
        borderDash: series.outdoor ? [6, 4] : [],
      })

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

  #chart(Chart, canvas, measure, title, unit) {
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
      for (const chart of this.charts) {
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
