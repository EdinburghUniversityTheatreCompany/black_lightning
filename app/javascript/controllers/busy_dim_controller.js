import { Controller } from "@hotwired/stimulus"

// Dims the dimmable targets while a form in scope submits, until fresh results
// replace them.
export default class extends Controller {
  static targets = ["dimmable"]

  start() { this.#toggle(true) }
  end() { this.#toggle(false) }

  #toggle(busy) {
    for (const el of this.dimmableTargets) {
      el.classList.add("transition-opacity")
      el.classList.toggle("opacity-40", busy)
      el.setAttribute("aria-busy", busy ? "true" : "false")
    }
  }
}
