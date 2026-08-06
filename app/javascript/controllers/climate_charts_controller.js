import { Controller } from "@hotwired/stimulus"

// Three stacked time-series charts (temperature, relative humidity, dew point)
// over one shared x-axis, one line per sensor plus the outdoor comparison.
//
// Chart.js is imported lazily inside connect(), matching techie_graph_controller
// and map_controller, so no other admin page pays for it.
export default class extends Controller {
  static targets = ["temperature", "humidity", "dewPoint", "empty"]
  static values = { series: Array }

  // Fixed order, never cycled. Validated for the light surface: worst adjacent
  // CVD ΔE 9.1, normal-vision ΔE 19.6. Three slots fall below 3:1 contrast,
  // which is why every series also carries an end-of-line direct label.
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

    // Turbo can disconnect us mid-import, onto detached canvases.
    if (!this.element.isConnected) return

    this.#charts = [
      this.#build(Chart, this.temperatureTarget, "temperature", "Temperature (°C)", "°C"),
      this.#build(Chart, this.humidityTarget, "humidity", "Relative humidity (%)", "%"),
      this.#build(Chart, this.dewPointTarget, "dew_point", "Dew point (°C)", "°C"),
    ].filter(Boolean)

    // Chart.js is an ES module, so there is no window.Chart. These are the
    // handles for checking what was actually plotted, from the browser tests and
    // from the console when a live page looks wrong.
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
      // Second cue for the outdoor line, so it reads apart without relying on hue.
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
        // Right padding is measured by the end-label plugin below.
        layout: { padding: { right: 0 } },
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

  // Required relief for the palette slots below 3:1 against the surface.
  #endLabelPlugin() {
    const FONT = "600 11px system-ui, sans-serif"
    const GAP = 6
    // Past this the labels eat the plot. Longer names are ellipsised instead.
    const MAX_WIDTH = 150

    const fit = (ctx, text) => {
      if (ctx.measureText(text).width <= MAX_WIDTH) return text

      let truncated = text
      while (truncated.length > 1 && ctx.measureText(`${truncated}…`).width > MAX_WIDTH) {
        truncated = truncated.slice(0, -1)
      }
      return `${truncated}…`
    }

    return {
      id: "climateEndLabels",

      // Measured, not guessed: a fixed padding clips a longer sensor name.
      beforeLayout(chart) {
        const ctx = chart.ctx
        ctx.save()
        ctx.font = FONT
        const widest = chart.data.datasets.reduce(
          (max, dataset, index) =>
            chart.getDatasetMeta(index).hidden
              ? max
              : Math.max(max, ctx.measureText(fit(ctx, dataset.label)).width),
          0,
        )
        ctx.restore()
        chart.options.layout.padding.right = Math.ceil(widest) + GAP * 2
      },

      afterDatasetsDraw(chart) {
        const { ctx } = chart
        ctx.save()
        ctx.font = FONT
        ctx.textBaseline = "middle"

        chart.data.datasets.forEach((dataset, index) => {
          const meta = chart.getDatasetMeta(index)
          if (meta.hidden) return

          const last = [...meta.data].reverse().find((point) => point && !Number.isNaN(point.y))
          if (!last) return

          ctx.fillStyle = dataset.borderColor
          ctx.fillText(fit(ctx, dataset.label), last.x + GAP, last.y)
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
