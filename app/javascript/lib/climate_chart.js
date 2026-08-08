// Shared machinery for the climate dashboard's charts: the palette, the lazy
// Chart.js import, the end-of-line labels, and the axis/legend defaults.
//
// Extracted because there are four chart controllers on this page and jscpd
// gates duplication at zero — but also because a sensor has to be the same
// colour and the same shape on every one of them, or they cannot be read
// together.

// Fixed order, never cycled. Validated for the light surface: worst adjacent
// CVD ΔE 9.1, normal-vision ΔE 19.6. Three slots fall below 3:1 contrast,
// which is why every series also carries an end-of-line direct label.
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

// Chart.js is imported lazily, matching techie_graph_controller and
// map_controller, so no other admin page pays for it.
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

// The Chart.js `options` object every line chart on this page shares:
// responsive sizing, reduced-motion, synced hover/tooltip, end-label padding,
// and the axis/legend defaults. Extracted because it is otherwise identical
// token-for-token across controllers, which jscpd's zero-duplication gate
// rejects outright.
export function chartOptions({ title, unit, extra = {} }) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: reducedMotion() ? false : undefined,
    interaction: { mode: "index", intersect: false },
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
        // Spread bands are scenery, not series. Listing them doubles the
        // legend and offers the reader a toggle that half-erases a chart.
        filter: (item, data) => !data.datasets[item.datasetIndex].band,
      },
    },
    tooltip: {
      filter: (item) => !item.dataset.band,
      callbacks: { label: (item) => `${item.dataset.label}: ${item.formattedValue}${unit}` },
    },
  }
}

// Required relief for the palette slots below 3:1 against the surface.
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
