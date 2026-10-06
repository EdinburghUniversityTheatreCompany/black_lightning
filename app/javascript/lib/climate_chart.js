import { Controller } from "@hotwired/stimulus"

// Shared machinery for the climate dashboard's four chart controllers, so a
// sensor is the same colour and shape on every chart.

// Fixed order, never cycled; colour-vision-deficiency validated on the light
// surface (worst adjacent ΔE 9.1). Three slots fall below 3:1 contrast, which
// is why every series also carries an end label.
export const PALETTE = [
  "#2a78d6", // blue
  "#eb6834", // orange
  "#1baf7a", // aqua
  "#eda100", // yellow
  "#e87ba4", // magenta
  "#008300", // green
  "#4a3aa7", // violet
  "#e34948", // red
]

export const AXIS_COLOR = "#52514e"
export const GRID_COLOR = "rgba(0,0,0,0.05)"

export function colorFor(index) {
  return PALETTE[index % PALETTE.length]
}

export function withAlpha(hex, alpha) {
  const value = parseInt(hex.slice(1), 16)
  return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`
}

export function reducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

// pointRadius: 0 lets the line carry the ink, but a point with no line either
// side (an island around a real gap, e.g. Buckets#gap_threshold's two-point
// fallback) would draw as nothing. This gives just that point a dot.
function pointRadiusUnlessIsolated(radius = 3) {
  const hasY = (point) => point && point.y !== null && point.y !== undefined

  return (context) => {
    const data = context.dataset?.data
    if (!data || !hasY(data[context.dataIndex])) return 0

    const isolated = !hasY(data[context.dataIndex - 1]) && !hasY(data[context.dataIndex + 1])
    return isolated ? radius : 0
  }
}

// spanGaps stays false so the server's explicit nulls BREAK the line across an
// outage instead of interpolating through it.
export function lineDataset({ label, points, key, color, borderDash = [] }) {
  return {
    label,
    spanGaps: false,
    data: points.map((point) => ({ x: point.t, y: point[key] })),
    borderColor: color,
    backgroundColor: color,
    borderDash,
    borderWidth: 2,
    pointRadius: pointRadiusUnlessIsolated(),
    pointHoverRadius: 5,
    tension: 0.2,
  }
}

// Lazy import, so no other admin page pays for Chart.js.
export async function loadChartJs({ bars = false } = {}) {
  const [chartjs] = await Promise.all([
    import("chart.js"),
    import("chartjs-adapter-date-fns"),
  ])
  const {
    Chart, LineController, LineElement, PointElement, BarController, BarElement,
    LinearScale, CategoryScale, TimeScale, Tooltip, Legend, Filler,
  } = chartjs

  Chart.register(LineController, LineElement, PointElement, LinearScale, TimeScale,
                 Tooltip, Legend, Filler)
  if (bars) Chart.register(BarController, BarElement, CategoryScale)

  return Chart
}

// Each subclass implements build(Chart), returning its charts.
export class ClimateChartController extends Controller {
  charts = []
  chartJsOptions = {}

  async connect() {
    const Chart = await loadChartJs(this.chartJsOptions)

    // Turbo can disconnect us mid-import, onto detached canvases.
    if (!this.element.isConnected) return

    this.charts = this.build(Chart)

    // Chart.js is an ES module, so there is no window.Chart: these handles are
    // what the browser tests (and a console) read.
    this.element.climateCharts = this.charts
    this.element.setAttribute(`data-${this.identifier}-ready`, String(this.charts.length))
  }

  disconnect() {
    // Or every Turbo navigation back leaks a canvas and its listeners.
    this.charts.forEach((chart) => chart.destroy())
    this.charts = []
    delete this.element.climateCharts
    this.element.removeAttribute(`data-${this.identifier}-ready`)
  }
}

export function timeScaleOptions({ title, unit }) {
  return {
    x: {
      type: "time",
      time: { tooltipFormat: "d MMM yyyy HH:mm" },
      grid: { color: GRID_COLOR },
      ticks: { maxRotation: 0, autoSkipPadding: 24, color: AXIS_COLOR },
    },
    y: {
      title: { display: true, text: title, color: AXIS_COLOR },
      grid: { color: GRID_COLOR },
      ticks: { color: AXIS_COLOR, callback: (value) => `${value}${unit}` },
    },
  }
}

export function chartOptions({ title, unit, extra = {} }) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: reducedMotion() ? false : undefined,
    interaction: { mode: "index", intersect: false },
    // An object, not a number: endLabelPlugin assigns .right on it.
    layout: { padding: { right: 0 } },
    scales: timeScaleOptions({ title, unit }),
    plugins: legendAndTooltip({ unit }),
    ...extra,
  }
}

export function legendAndTooltip({ unit }) {
  return {
    legend: {
      position: "bottom",
      labels: {
        usePointStyle: true,
        color: "#0b0b0b",
        // Bands are scenery, not series: listing them doubles the legend.
        filter: (item, data) => !data.datasets[item.datasetIndex].band,
      },
      // Chart.js's default toggles only the clicked datasetIndex, hiding the
      // line and leaving its band floating with no line or label. Toggle every
      // dataset sharing the label instead.
      onClick(_event, legendItem, legend) {
        const chart = legend.chart
        const label = chart.data.datasets[legendItem.datasetIndex].label
        const visible = chart.isDatasetVisible(legendItem.datasetIndex)

        chart.data.datasets.forEach((dataset, index) => {
          if (dataset.label !== label) return
          if (visible) chart.hide(index)
          else chart.show(index)
        })

        legendItem.hidden = visible
      },
    },
    tooltip: {
      filter: (item) => !item.dataset.band,
      callbacks: { label: (item) => `${item.dataset.label}: ${item.formattedValue}${unit}` },
    },
  }
}

// The relief for palette slots below 3:1 contrast against the surface.
export function endLabelPlugin() {
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

  const visible = (chart, dataset, index) =>
    !dataset.band && !chart.getDatasetMeta(index).hidden

  return {
    id: "climateEndLabels",

    // Measured, not guessed: a fixed padding clips a longer sensor name.
    beforeLayout(chart) {
      const ctx = chart.ctx
      ctx.save()
      ctx.font = FONT
      const widest = chart.data.datasets.reduce(
        (max, dataset, index) =>
          visible(chart, dataset, index)
            ? Math.max(max, ctx.measureText(fit(ctx, dataset.label)).width)
            : max,
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
        if (!visible(chart, dataset, index)) return

        const meta = chart.getDatasetMeta(index)
        const last = [...meta.data].reverse().find((point) => point && !Number.isNaN(point.y))
        if (!last) return

        ctx.fillStyle = dataset.borderColor
        ctx.fillText(fit(ctx, dataset.label), last.x + GAP, last.y)
      })
      ctx.restore()
    },
  }
}

export function seriesAriaLabel({ title, unit, entries, suffix }) {
  const parts = entries.map(({ name, values }) => {
    const present = values.filter((value) => value !== null && value !== undefined)
    if (present.length === 0) return `${name}: no readings`

    const min = Math.min(...present).toFixed(1)
    const max = Math.max(...present).toFixed(1)
    const latest = present[present.length - 1].toFixed(1)
    return `${name}: latest ${latest}${unit}, ranging ${min} to ${max}${unit}`
  })

  return `${title}. ${parts.join(". ")}. ${suffix}`
}
