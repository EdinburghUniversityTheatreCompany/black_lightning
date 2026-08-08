import { Controller } from "@hotwired/stimulus"
import {
  chartOptions, colorFor, endLabelPlugin, loadChartJs, pointRadiusUnlessIsolated,
  seriesAriaLabel, withAlpha,
} from "../lib/climate_chart"

// Crypt temperature, crypt dew point and outdoor dew point on one °C axis, so
// the two ventilation questions can be read off a single picture.
//
// The styles are load-bearing: the two crypt lines share the sensor's hue so
// they read as one place, the outdoor line is dashed so it reads apart
// without relying on colour.
const STYLES = {
  solid: { borderDash: [], borderWidth: 2, alpha: 1 },
  muted: { borderDash: [2, 3], borderWidth: 2, alpha: 0.65 },
  dashed: { borderDash: [6, 4], borderWidth: 2, alpha: 1 },
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = { series: Array }

  #charts = []

  async connect() {
    if (this.seriesValue.length === 0) return

    const Chart = await loadChartJs()
    if (!this.element.isConnected) return

    this.#charts = [this.#build(Chart)]
    this.element.climateCharts = this.#charts
    this.element.dataset.climateVentilationChartReady = String(this.#charts.length)
  }

  disconnect() {
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateVentilationChartReady
  }

  #build(Chart) {
    const canvas = this.canvasTarget
    const title = "Temperature and dew point (°C)"

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", seriesAriaLabel({
      title, unit: "°C",
      entries: this.seriesValue.map((line) => ({
        name: line.label, values: line.points.map((point) => point.value),
      })),
      suffix: "Ventilating dries the crypt when the outside dew point sits below the crypt's own.",
    }))

    return new Chart(canvas, {
      type: "line",
      data: {
        datasets: this.seriesValue.map((line) => {
          const style = STYLES[line.style] ?? STYLES.solid
          const color = withAlpha(colorFor(line.color_index), style.alpha)
          return {
            label: line.label,
            spanGaps: false,
            data: line.points.map((point) => ({ x: point.t, y: point.value })),
            borderColor: color,
            backgroundColor: color,
            borderDash: style.borderDash,
            borderWidth: style.borderWidth,
            // See climate_charts_controller for why this isn't a plain 0.
            pointRadius: pointRadiusUnlessIsolated(),
            pointHoverRadius: 5,
            tension: 0.2,
          }
        }),
      },
      plugins: [endLabelPlugin()],
      options: chartOptions({ title, unit: "°C" }),
    })
  }
}
