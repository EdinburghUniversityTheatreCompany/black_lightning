import { Controller } from "@hotwired/stimulus"
import Cytoscape from "cytoscape"

function buildColorMap(years) {
  const unique = [...new Set(years.filter(y => y != null))].sort()
  const map = {}
  unique.forEach((year, i) => {
    const hue = Math.round((i / unique.length) * 360)
    map[year] = `hsl(${hue}, 60%, 65%)`
  })
  return map
}

const HOP_CLASSES = "hop-1 hop-2 hop-3 hop-far"

export default class extends Controller {
  static values = { nodes: Array, edges: Array }

  connect() {
    const years = this.nodesValue.map(n => n.entry_year)
    const colorMap = buildColorMap(years)

    const elements = [
      ...this.nodesValue.map(({ id, label, entry_year }) => ({
        data: { id, label, entry_year, color: colorMap[entry_year] ?? "#9ca3af" },
      })),
      ...this.edgesValue.map(({ from, to }) => ({
        data: { id: `${from}-${to}`, source: from, target: to },
      })),
    ]

    this.#cy = Cytoscape({
      container: this.element,
      elements,
      layout: {
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
      },
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
            "curve-style": "bezier",
          },
        },
        {
          selector: "node.focused",
          style: {
            "border-width": 3,
            "border-color": "#1d4ed8",
          },
        },
        // Edge hop highlighting — applied after a node is clicked
        {
          selector: "edge.hop-1",
          style: { "line-color": "#111827", "target-arrow-color": "#111827", width: 3, opacity: 1 },
        },
        {
          selector: "edge.hop-2",
          style: { "line-color": "#6b7280", "target-arrow-color": "#6b7280", width: 2, opacity: 0.8 },
        },
        {
          selector: "edge.hop-3",
          style: { "line-color": "#9ca3af", "target-arrow-color": "#9ca3af", width: 1.5, opacity: 0.5 },
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

    this.#cy.on("tap", "node", evt => {
      const root = evt.target

      // Click the focused node again to reset highlighting
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
        if (d === 0)      e.addClass("hop-1")
        else if (d === 1) e.addClass("hop-2")
        else if (d === 2) e.addClass("hop-3")
        else              e.addClass("hop-far")
      })

      const maxDepth = Math.max(...Object.values(distances), 1)

      this.#cy.layout({
        name: "concentric",
        concentric: (n) => {
          const d = distances[n.id()]
          return d !== undefined ? maxDepth - d + 1 : 0
        },
        levelWidth: () => 1,
        animate: true,
        animationDuration: 600,
        animationEasing: "ease-in-out-cubic",
        fit: true,
        padding: 30,
      }).run()
    })
  }

  disconnect() {
    this.#cy?.destroy()
    this.#cy = null
  }

  #cy = null
}
