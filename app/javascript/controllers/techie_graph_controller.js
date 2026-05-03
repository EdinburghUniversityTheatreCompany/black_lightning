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
      ],
      userZoomingEnabled: true,
      userPanningEnabled: true,
      boxSelectionEnabled: false,
      minZoom: 0.1,
      maxZoom: 3,
    })

    this.#cy.on("tap", "node", evt => {
      const root = evt.target
      this.#cy.elements().removeClass("focused")
      root.addClass("focused")

      const distances = {}
      this.#cy.elements().bfs({
        roots: root,
        visit: (v, _e, _u, _i, depth) => { distances[v.id()] = depth },
        directed: false,
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
