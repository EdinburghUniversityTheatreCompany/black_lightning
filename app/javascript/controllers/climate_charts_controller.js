import { Controller } from "@hotwired/stimulus"

// Three stacked time-series charts (temperature, relative humidity, dew point)
// over one shared x-axis, one line per sensor plus the outdoor comparison.
//
// Chart.js is imported lazily inside connect(), matching techie_graph_controller
// and map_controller, so no other admin page pays for it.
export default class extends Controller {
  static targets = ["temperature", "humidity", "dewPoint", "empty"]
  static values = { series: Array }

  // Categorical slots, assigned in fixed order and never cycled. Validated for
  // the light surface: worst adjacent CVD ΔE 9.1, worst adjacent normal-vision
  // ΔE 19.6. Three of them fall below 3:1 contrast, which is why every series
  // also carries an end-of-line direct label — colour is never the only cue.
  static PALETTE = [
    "#2a78d6", // blue
    "#eb6834", // orange
    "#1baf7a", // aqua
    "#eda100", // yellow
    "#e87ba4", // magenta
    "#008300", // green
    "#4a3aa7", // violet
    "#e34948", // red
  ]

  #charts = []
  #syncing = false

  async connect() {
    if (this.seriesValue.length === 0) return

    const [chartjs] = await Promise.all([
      import("chart.js"),
      import("chartjs-adapter-date-fns"),
    ])
    const {
      Chart, LineController, LineElement, PointElement,
      LinearScale, TimeScale, Tooltip, Legend, Filler,
    } = chartjs

    Chart.register(LineController, LineElement, PointElement, LinearScale, TimeScale, Tooltip, Legend, Filler)

    // Turbo can disconnect us mid-import; without this the charts are built
    // onto canvases that are already detached.
    if (!this.element.isConnected) return

    this.#charts = [
      this.#build(Chart, this.temperatureTarget, "temperature", "Temperature (°C)", "°C"),
      this.#build(Chart, this.humidityTarget, "humidity", "Relative humidity (%)", "%"),
      this.#build(Chart, this.dewPointTarget, "dew_point", "Dew point (°C)", "°C"),
    ].filter(Boolean)

    // Chart.js is an ES module here, so there is no window.Chart to inspect.
    // These two are the handles for checking what was actually plotted — from
    // the browser tests, and from the console when a live page looks wrong.
    this.element.climateCharts = this.#charts
    this.element.dataset.climateChartsReady = String(this.#charts.length)
  }

  disconnect() {
    // Without this every Turbo navigation back to the page leaks a canvas and
    // its listeners.
    this.#charts.forEach((chart) => chart.destroy())
    this.#charts = []
    delete this.element.climateCharts
    delete this.element.dataset.climateChartsReady
  }

  get #reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  #color(series) {
    const palette = this.constructor.PALETTE
    return palette[series.color_index % palette.length]
  }

  #datasets(measure) {
    return this.seriesValue.map((series) => ({
      label: series.name,
      // spanGaps stays false so the explicit null points the server inserts
      // BREAK the line across an outage rather than interpolating through it.
      spanGaps: false,
      data: series.points.map((point) => ({ x: point.t, y: point[measure] })),
      borderColor: this.#color(series),
      backgroundColor: this.#color(series),
      // Second cue for the outdoor reference line, so it reads apart from the
      // indoor sensors without relying on hue.
      borderDash: series.outdoor ? [6, 4] : [],
      borderWidth: 2,
      pointRadius: 0,
      pointHoverRadius: 5,
      tension: 0.2,
    }))
  }

  #build(Chart, canvas, measure, title, unit) {
    if (!canvas) return null

    canvas.setAttribute("role", "img")
    canvas.setAttribute("aria-label", this.#ariaLabel(measure, title, unit))

    return new Chart(canvas, {
      type: "line",
      data: { datasets: this.#datasets(measure) },
      plugins: [this.#endLabelPlugin()],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: this.#reducedMotion ? false : undefined,
        interaction: { mode: "index", intersect: false },
        // Room on the right for the end-of-line labels.
        layout: { padding: { right: 84 } },
        scales: {
          x: {
            type: "time",
            time: { tooltipFormat: "d MMM yyyy HH:mm" },
            grid: { color: "rgba(0,0,0,0.05)" },
            ticks: { maxRotation: 0, autoSkipPadding: 24, color: "#52514e" },
          },
          y: {
            title: { display: true, text: title, color: "#52514e" },
            grid: { color: "rgba(0,0,0,0.05)" },
            ticks: { color: "#52514e", callback: (value) => `${value}${unit}` },
          },
        },
        plugins: {
          legend: { position: "bottom", labels: { usePointStyle: true, color: "#0b0b0b" } },
          tooltip: {
            callbacks: {
              label: (item) => `${item.dataset.label}: ${item.formattedValue}${unit}`,
            },
          },
        },
        onHover: (_event, elements, chart) => this.#syncHover(chart, elements),
      },
    })
  }

  // Hovering one chart shows the same instant on all three — the whole point of
  // stacking them is reading temperature, humidity and dew point together.
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

  // Direct labels at the end of each line. Required relief for the palette
  // slots that fall below 3:1 against the surface, and the fastest way to read
  // which line is which without crossing to the legend.
  #endLabelPlugin() {
    return {
      id: "climateEndLabels",
      afterDatasetsDraw(chart) {
        const { ctx } = chart
        ctx.save()
        ctx.font = "600 11px system-ui, sans-serif"
        ctx.textBaseline = "middle"

        chart.data.datasets.forEach((dataset, index) => {
          const meta = chart.getDatasetMeta(index)
          if (meta.hidden) return

          const last = [...meta.data].reverse().find((point) => point && !Number.isNaN(point.y))
          if (!last) return

          ctx.fillStyle = dataset.borderColor
          ctx.fillText(dataset.label, last.x + 6, last.y)
        })
        ctx.restore()
      },
    }
  }

  #ariaLabel(measure, title, unit) {
    const parts = this.seriesValue.map((series) => {
      const values = series.points.map((point) => point[measure]).filter((value) => value !== null)
      if (values.length === 0) return `${series.name}: no readings`

      const min = Math.min(...values).toFixed(1)
      const max = Math.max(...values).toFixed(1)
      const latest = values[values.length - 1].toFixed(1)
      return `${series.name}: latest ${latest}${unit}, ranging ${min} to ${max}${unit}`
    })

    return `${title}. ${parts.join(". ")}. The current readings are also listed as text above this chart.`
  }
}
