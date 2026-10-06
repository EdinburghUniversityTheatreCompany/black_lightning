import {
  ClimateChartController, chartOptions, colorFor, endLabelPlugin, lineDataset,
  seriesAriaLabel, withAlpha,
} from "../lib/climate_chart"

// Crypt temperature, crypt dew point and outdoor dew point on one °C axis, so
// both ventilation questions read off one picture.
//
// The styles are load-bearing: the crypt pair shares the sensor's hue so they
// read as one place, and the outdoor line is dashed so it reads apart without
// relying on colour.
const STYLES = {
  solid: { borderDash: [], alpha: 1 },
  muted: { borderDash: [2, 3], alpha: 0.65 },
  dashed: { borderDash: [6, 4], alpha: 1 },
}

export default class extends ClimateChartController {
  static targets = ["canvas"]
  static values = { series: Array }

  build(Chart) {
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

    return [new Chart(canvas, {
      type: "line",
      data: {
        datasets: this.seriesValue.map((line) => {
          const style = STYLES[line.style] ?? STYLES.solid
          return lineDataset({
            label: line.label, points: line.points, key: "value",
            color: withAlpha(colorFor(line.color_index), style.alpha), borderDash: style.borderDash,
          })
        }),
      },
      plugins: [endLabelPlugin()],
      options: chartOptions({ title, unit: "°C" }),
    })]
  }
}
