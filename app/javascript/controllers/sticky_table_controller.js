import { Controller } from "@hotwired/stimulus"

// Pins a table's rowgroup headings directly below its sticky column header.
//
// The offset cannot be a constant: the header's height depends on how many of
// its labels wrap, which depends on the viewport. The budgets index has 14
// columns, so its header is two lines at 1366px and one line at 1920px — and a
// hardcoded 57px left a 20px gap at the wider size that the rows scrolled
// through, which reads as a half-clipped row rather than as a gap.
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
