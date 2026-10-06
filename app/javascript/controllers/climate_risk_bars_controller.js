import { AXIS_COLOR, ClimateChartController, GRID_COLOR, colorFor, reducedMotion } from "../lib/climate_chart"

// Hours at risk per day, a bar group per crypt sensor. Mould follows how long
// the air sat near saturation, so a bad week shows as a cluster, not one total.
export default class extends ClimateChartController {
  static targets = ["canvas"]
  static values = { summaries: Array }

  chartJsOptions = { bars: true }

  // The union of days, so a day one sensor missed does not shift the others.
  #labels() {
    const dates = new Set()
    this.summariesValue.forEach((summary) => summary.days.forEach((day) => dates.add(day.date)))
    return [...dates].sort()
  }

  build(Chart) {
    const canvas = this.canvasTarget
    const labels = this.#labels()

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", this.#ariaLabel())

    return [new Chart(canvas, {
      type: "bar",
      data: {
        labels,
        datasets: this.summariesValue.map((summary) => {
          const byDate = new Map(summary.days.map((day) => [day.date, day.at_risk_hours]))
          return {
            label: summary.name,
            // An uncovered day is null, not zero: zero reads as "measured, and fine".
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
    })]
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
