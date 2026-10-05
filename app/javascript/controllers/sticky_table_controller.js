import { Controller } from "@hotwired/stimulus"

// Sets --sticky-head-height from the column header, so rowgroup headings pin just
// below it. A constant cannot do: how many lines the header wraps to depends on
// the viewport.
export default class extends Controller {
  static targets = ["head"]

  connect() {
    this.#measure()
    this.observer = new ResizeObserver(() => this.#measure())
    this.observer.observe(this.hasHeadTarget ? this.headTarget : this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #measure() {
    const head = this.hasHeadTarget ? this.headTarget : this.element.querySelector("thead")
    if (!head) return

    this.element.style.setProperty("--sticky-head-height", `${Math.round(head.getBoundingClientRect().height)}px`)
  }
}
