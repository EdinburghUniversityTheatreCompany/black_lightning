import { Controller } from "@hotwired/stimulus"
import {
  colorFor, endLabelPlugin, legendAndTooltip, loadChartJs, reducedMotion,
  seriesAriaLabel, timeScaleOptions,
} from "../lib/climate_chart"

// How close the crypt came to condensing: one line per crypt sensor, plotting
// the WORST margin in each bucket rather than the average, with everything
// under the threshold shaded.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { series: Array, threshold: Number }

  #charts = []

  async connect() {
    if (this.seriesValue.length === 0) return

    const Chart = await loadChartJs()
    if (!this.element.isConnected) return

    this.#charts = [this.#build(Chart)]
    this.element.climateCharts = this.#charts
    this.element.dataset.climateMarginChartReady = String(this.#charts.length)
  }

  disconnect() {
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateMarginChartReady
  }

  #build(Chart) {
    const canvas = this.canvasTarget
    const title = "Margin above dew point (°C)"

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", seriesAriaLabel({
      title, unit: "°C",
      entries: this.seriesValue.map((s) => ({ name: s.name, values: s.points.map((p) => p.margin) })),
      suffix: "The same figures are summarised as text above this chart.",
    }))

    return new Chart(canvas, {
      type: "line",
      data: {
        datasets: this.seriesValue.map((series) => ({
          label: series.name,
          spanGaps: false,
          data: series.points.map((point) => ({ x: point.t, y: point.margin })),
          borderColor: colorFor(series.color_index),
          backgroundColor: colorFor(series.color_index),
          borderWidth: 2,
          pointRadius: 0,
          pointHoverRadius: 5,
          tension: 0.2,
        })),
      },
      plugins: [this.#riskBandPlugin(), endLabelPlugin()],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        interaction: { mode: "index", intersect: false },
        layout: { padding: { right: 0 } },
        scales: timeScaleOptions({ title, unit: "°C" }),
        plugins: legendAndTooltip({ unit: "°C" }),
      },
    })
  }

  // Drawn under the lines, so a night that dipped into the band is visible as
  // a line entering shaded ground rather than as a number to compare against.
  #riskBandPlugin() {
    const threshold = this.thresholdValue

    return {
      id: "climateRiskBand",
      beforeDatasetsDraw(chart) {
        const { ctx, chartArea, scales } = chart
        if (!chartArea) return

        const top = Math.max(scales.y.getPixelForValue(threshold), chartArea.top)
        if (top >= chartArea.bottom) return

        ctx.save()
        ctx.fillStyle = "rgba(227, 73, 72, 0.10)"
        ctx.fillRect(chartArea.left, top, chartArea.width, chartArea.bottom - top)
        ctx.strokeStyle = "rgba(227, 73, 72, 0.55)"
        ctx.setLineDash([4, 4])
        ctx.beginPath()
        ctx.moveTo(chartArea.left, top)
        ctx.lineTo(chartArea.right, top)
        ctx.stroke()
        ctx.restore()
      },
    }
  }
}
