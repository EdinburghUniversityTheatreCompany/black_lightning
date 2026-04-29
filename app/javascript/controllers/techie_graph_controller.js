import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    nodes: Array,
    edges: Array
  }

  connect() {
    // Graph, Graph.Layout.Spring, Graph.Renderer.Raphael are globals from Raphael/Dracula
    /* global Graph */
    if (typeof Graph === "undefined") {
      console.error("techie-graph: Raphael/Dracula libraries not loaded")
      return
    }

    const g = new Graph()

    const render = (renderer, node) => {
      const text = renderer.text(node.point[0] + 10, node.point[1] + 10, node.label)
      const dimensions = text.getBBox()
      const set = renderer.set().push(
        renderer.rect(
          node.point[0] - dimensions.width / 2,
          node.point[1],
          dimensions.width + 20,
          dimensions.height + 10
        ).attr({ fill: "#feb", r: "12px", "stroke-width": node.distance === 0 ? "3px" : "1px" })
      ).push(text)
      text.toFront()
      return set
    }

    this.nodesValue.forEach(({ id, label }) => {
      g.addNode(id, { render, label })
    })

    this.edgesValue.forEach(({ from, to }) => {
      g.addEdge(from, to, { directed: true })
    })

    const layouter = new Graph.Layout.Spring(g)
    layouter.layout()

    const renderer = new Graph.Renderer.Raphael(this.element.id, g, 940, 1500)
    renderer.draw()
  }
}
