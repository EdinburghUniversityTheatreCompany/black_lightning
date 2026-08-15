import { Controller } from "@hotwired/stimulus"
import { AXIS_COLOR, GRID_COLOR, colorFor, loadChartJs, reducedMotion } from "../lib/climate_chart"

// Hours at risk per day, one bar group per crypt sensor. Mould is a function
// of how long the air sat near saturation, so a bad week has to be visible as
// a cluster rather than buried in a single total.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { summaries: Array }

  #charts = []

  async connect() {
    const labels = this.#labels()
    if (labels.length === 0) return

    const Chart = await loadChartJs({ bars: true })
    if (!this.element.isConnected) return

    this.#charts = [this.#build(Chart, labels)]
    this.element.climateCharts = this.#charts
    this.element.dataset.climateRiskBarsReady = String(this.#charts.length)
  }

  disconnect() {
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateRiskBarsReady
  }

  // The union of every sensor's covered days, so a day one sensor missed
  // still lines up under the others rather than shifting them along.
  #labels() {
    const dates = new Set()
    this.summariesValue.forEach((summary) => summary.days.forEach((day) => dates.add(day.date)))
    return [...dates].sort()
  }

  #build(Chart, labels) {
    const canvas = this.canvasTarget

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", this.#ariaLabel())

    return new Chart(canvas, {
      type: "bar",
      data: {
        labels,
        datasets: this.summariesValue.map((summary) => {
          const byDate = new Map(summary.days.map((day) => [day.date, day.at_risk_hours]))
          return {
            label: summary.name,
            // A day the sensor did not cover is left null, not zero: zero
            // would read as "measured, and fine".
            data: labels.map((date) => (byDate.has(date) ? byDate.get(date) : null)),
            backgroundColor: colorFor(summary.color_index ?? 0),
          }
        }),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion() ? false : undefined,
        scales: {
          x: { grid: { display: false }, ticks: { color: AXIS_COLOR, maxRotation: 0, autoSkipPadding: 16 } },
          y: {
            beginAtZero: true,
            suggestedMax: 24,
            title: { display: true, text: "Hours at risk", color: AXIS_COLOR },
            grid: { color: GRID_COLOR },
            ticks: { color: AXIS_COLOR, precision: 0 },
          },
        },
        plugins: {
          legend: { position: "bottom", labels: { usePointStyle: true, color: "#0b0b0b" } },
          tooltip: {
            callbacks: {
              label: (item) =>
                item.raw === null
                  ? `${item.dataset.label}: no readings`
                  : `${item.dataset.label}: ${item.raw} h at risk`,
            },
          },
        },
      },
    })
  }

  #ariaLabel() {
    const parts = this.summariesValue.map((summary) => {
      const worst = summary.days.reduce(
        (max, day) => (day.at_risk_hours > max.at_risk_hours ? day : max),
        { at_risk_hours: 0, date: null },
      )
      if (!worst.date) return `${summary.name}: no day came under the threshold`
      return `${summary.name}: worst day ${worst.date}, ${worst.at_risk_hours} hours at risk`
    })

    return `Hours at risk per day. ${parts.join(". ")}. The totals are also listed as text above.`
  }
}
