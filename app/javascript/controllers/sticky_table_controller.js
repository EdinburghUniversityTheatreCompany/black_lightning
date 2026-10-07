import { Controller } from "@hotwired/stimulus"

// Sets --sticky-head-height from the column header, so rowgroup headings pin just
// below it. A constant cannot do: how many lines the header wraps to depends on
// the viewport.
export default class extends Controller {
  connect() {
    this.#measure()
    this.observer = new ResizeObserver(() => this.#measure())
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #measure() {
    const head = this.element.querySelector("thead")
    if (!head) return

    this.element.style.setProperty("--sticky-head-height", `${Math.round(head.getBoundingClientRect().height)}px`)
  }
}
