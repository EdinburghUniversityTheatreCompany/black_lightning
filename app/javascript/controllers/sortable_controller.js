import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: "[data-sortable-handle]",
      draggable: "[data-sortable-item]",
      animation: 150,
      onEnd: () => this.#updateOrder()
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  #updateOrder() {
    this.element.querySelectorAll("[data-sortable-item]").forEach((el, index) => {
      const input = el.querySelector("input[data-display-order]")
      if (input) input.value = index
    })
  }
}
