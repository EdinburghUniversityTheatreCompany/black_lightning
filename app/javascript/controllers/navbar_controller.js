import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "toggler"]

  toggle() {
    const expanded = this.menuTarget.classList.toggle("show")
    this.togglerTarget.setAttribute("aria-expanded", String(expanded))
  }
}
