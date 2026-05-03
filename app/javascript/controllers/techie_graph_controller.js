import { Controller } from "@hotwired/stimulus"
import Cytoscape from "cytoscape"

// Stable color per year — derived from the year itself so the same year always
// gets the same hue regardless of which other years are in the current dataset.
// The golden angle (137°) spreads consecutive years far apart visually.
function yearToColor(year) {
  return `hsl(${(year * 137) % 360}, 60%, 65%)`
}

const HOP_CLASSES = "hop-1 hop-2 hop-3 hop-far"

export default class extends Controller {
  static values = { nodes: Array, edges: Array, selected: String }
  static targets = ["canvas", "legend"]

  connect() {
    this.#renderLegend()

    const elements = [
      ...this.nodesValue.map(({ id, label, entry_year }) => ({
        data: { id, label, entry_year, color: entry_year != null ? yearToColor(entry_year) : "#9ca3af" },
      })),
      ...this.edgesValue.map(({ from, to }) => ({
        data: { id: `${from}-${to}`, source: from, target: to },
      })),
    ]

    this.#cy = Cytoscape({
      container: this.canvasTarget,
      elements,
      style: [
        {
          selector: "node",
          style: {
            label: "data(label)",
            "background-color": "data(color)",
            "text-valign": "center",
            "text-halign": "center",
            "font-size": "12px",
            shape: "roundrectangle",
            color: "#1f2937",
            "text-wrap": "wrap",
            "text-max-width": "140px",
            width: 140,
            height: 36,
          },
        },
        {
          selector: "edge",
          style: {
            width: 2,
            "line-color": "#d1d5db",
            "target-arrow-color": "#d1d5db",
            "target-arrow-shape": "triangle",
            "mid-target-arrow-shape": "triangle",
            "mid-target-arrow-color": "#d1d5db",
            "arrow-scale": 1.8,
            "curve-style": "bezier",
          },
        },
        {
          selector: "node.focused",
          style: { "border-width": 3, "border-color": "#1d4ed8" },
        },
        // Edge hop highlighting — applied after a node is clicked
        {
          selector: "edge.hop-1",
          style: { "line-color": "#111827", "target-arrow-color": "#111827", "mid-target-arrow-color": "#111827", width: 3, opacity: 1 },
        },
        {
          selector: "edge.hop-2",
          style: { "line-color": "#6b7280", "target-arrow-color": "#6b7280", "mid-target-arrow-color": "#6b7280", width: 2, opacity: 0.8 },
        },
        {
          selector: "edge.hop-3",
          style: { "line-color": "#9ca3af", "target-arrow-color": "#9ca3af", "mid-target-arrow-color": "#9ca3af", width: 1.5, opacity: 0.5 },
        },
        {
          selector: "edge.hop-far",
          style: { opacity: 0.1 },
        },
        {
          selector: "node.hop-far",
          style: { opacity: 0.2 },
        },
      ],
      userZoomingEnabled: true,
      userPanningEnabled: true,
      boxSelectionEnabled: false,
      minZoom: 0.1,
      maxZoom: 3,
    })

    this.#cy.on("tap", "node", evt => this.#selectNode(evt.target))

    const layout = this.#cy.layout({
      name: "cose",
      animate: false,
      randomize: false,
      fit: true,
      padding: 30,
      nodeRepulsion: () => 8000,
      idealEdgeLength: () => 80,
      edgeElasticity: () => 100,
      gravity: 0.25,
      numIter: 2500,
    })

    layout.on("layoutstop", () => {
      if (this.selectedValue) {
        const node = this.#cy.getElementById(this.selectedValue)
        if (node.length) this.#selectNode(node, { zoomIn: true })
      }
    })

    layout.run()
  }

  disconnect() {
    this.#cy?.destroy()
    this.#cy = null
  }

  #cy = null

  #renderLegend() {
    const years = [...new Set(this.nodesValue.map(n => n.entry_year).filter(y => y != null))].sort()
    const hasUnknown = this.nodesValue.some(n => n.entry_year == null)

    const swatch = (color, label) =>
      `<span class="d-flex align-items-center gap-1">` +
      `<span style="width:12px;height:12px;background:${color};border-radius:2px;flex-shrink:0"></span>` +
      `${label}</span>`

    const items = years.map(y => swatch(yearToColor(y), y))
    if (hasUnknown) items.push(swatch("#9ca3af", "No year"))

    this.legendTarget.innerHTML = items.join("")
  }

  #selectNode(root, { zoomIn = false } = {}) {
    if (root.hasClass("focused")) {
      this.#cy.elements().removeClass(`focused ${HOP_CLASSES}`)
      return
    }

    this.#cy.elements().removeClass(`focused ${HOP_CLASSES}`)
    root.addClass("focused")

    const distances = {}
    this.#cy.elements().bfs({
      roots: root,
      visit: (v, _e, _u, _i, depth) => { distances[v.id()] = depth },
      directed: false,
    })

    // Dim nodes beyond 3 hops
    this.#cy.nodes().forEach(n => {
      const d = distances[n.id()]
      if (d === undefined || d > 3) n.addClass("hop-far")
    })

    // Classify edges by the distance of their nearest endpoint to root
    this.#cy.edges().forEach(e => {
      const d = Math.min(
        distances[e.source().id()] ?? Infinity,
        distances[e.target().id()] ?? Infinity
      )
      if (d === 0) e.addClass("hop-1")
      else if (d === 1) e.addClass("hop-2")
      else if (d === 2) e.addClass("hop-3")
      else e.addClass("hop-far")
    })

    // Snapshot positions before layout so we can animate FROM them
    const startPositions = {}
    this.#cy.nodes().forEach(n => {
      startPositions[n.id()] = { x: n.position("x"), y: n.position("y") }
    })

    const maxDepth = Math.max(...Object.values(distances), 1)

    const conLayout = this.#cy.layout({
      name: "concentric",
      concentric: (n) => {
        const d = distances[n.id()]
        return d !== undefined ? maxDepth - d + 1 : 0
      },
      levelWidth: () => 1,
      animate: false,
      fit: false,
    })

    conLayout.on("layoutstop", () => {
      // Translate concentric positions so the root lands on the current viewport centre.
      // cy.extent() is the visible model-space rectangle; its centre never changes when
      // fit:false is used, so we can safely read it after the layout has run.
      const extent = this.#cy.extent()
      const vcx = (extent.x1 + extent.x2) / 2
      const vcy = (extent.y1 + extent.y2) / 2
      const dx = vcx - root.position("x")
      const dy = vcy - root.position("y")

      const endPositions = {}
      this.#cy.nodes().forEach(n => {
        endPositions[n.id()] = { x: n.position("x") + dx, y: n.position("y") + dy }
      })

      // Reset nodes to where they were — animation will carry them to the targets
      this.#cy.nodes().forEach(n => {
        n.position(startPositions[n.id()])
      })

      const animDuration = 600
      this.#cy.nodes().forEach(n => {
        n.animate(
          { position: endPositions[n.id()] },
          { duration: animDuration, easing: "ease-in-out-cubic" }
        )
      })

      if (zoomIn) {
        setTimeout(() => {
          this.#cy.animate(
            { fit: { eles: root.closedNeighborhood(), padding: 80 } },
            { duration: 400 }
          )
        }, animDuration + 50)
      }
    })

    conLayout.run()
  }
}
