import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "toggle", "chevron"]

  #mediaQuery
  #boundUpdate = this.#update.bind(this)

  connect() {
    this.#mediaQuery = window.matchMedia("(min-width: 768px)")
    this.#update(this.#mediaQuery)
    this.#mediaQuery.addEventListener("change", this.#boundUpdate)
  }

  disconnect() {
    this.#mediaQuery.removeEventListener("change", this.#boundUpdate)
  }

  toggle() {
    const isHidden = this.bodyTarget.hidden = !this.bodyTarget.hidden
    if (this.hasChevronTarget) {
      this.chevronTarget.classList.toggle("rotate-180", !isHidden)
    }
  }

  #update(mq) {
    if (mq.matches) {
      // Desktop: body always visible, toggle hidden
      this.bodyTarget.hidden = false
      this.toggleTarget.hidden = true
    } else {
      // Mobile: body hidden (collapsed), toggle visible
      this.bodyTarget.hidden = true
      this.toggleTarget.hidden = false
    }
  }
}
