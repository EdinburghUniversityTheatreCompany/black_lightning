import { Controller } from "@hotwired/stimulus"
import Cytoscape from "cytoscape"
import CytoscapeDagre from "cytoscape-dagre"

Cytoscape.use(CytoscapeDagre)

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
        data: { id, label, entry_year },
        style: {
          "background-color": colorMap[entry_year] ?? "#9ca3af",
        },
      })),
      ...this.edgesValue.map(({ from, to }) => ({
        data: { id: `${from}-${to}`, source: from, target: to },
      })),
    ]

    this.#cy = Cytoscape({
      container: this.element,
      elements,
      layout: {
        name: "dagre",
        rankDir: "TB",
        nodeSep: 50,
        rankSep: 80,
        animate: false,
      },
      style: [
        {
          selector: "node",
          style: {
            label: "data(label)",
            "text-valign": "center",
            "text-halign": "center",
            "font-size": "12px",
            width: "label",
            height: "label",
            padding: "8px",
            shape: "roundrectangle",
            color: "#1f2937",
            "text-wrap": "wrap",
            "text-max-width": "120px",
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
      const node = evt.target
      this.#cy.elements().removeClass("focused")
      node.addClass("focused")
      this.#cy.animate({ center: { eles: node }, zoom: 1.2 }, { duration: 400 })
    })
  }

  disconnect() {
    this.#cy?.destroy()
    this.#cy = null
  }

  #cy = null
}
