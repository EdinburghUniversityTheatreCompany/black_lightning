import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "admin-sidebar-open"

export default class extends Controller {
  static targets = ["sidebar"]

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const isOpen = stored === null ? true : stored === "true"
    this.#applyState(isOpen)
  }

  toggle() {
    const isOpen = !this.sidebarTarget.classList.contains("sidebar-collapsed")
    localStorage.setItem(STORAGE_KEY, String(!isOpen))
    this.#applyState(!isOpen)
  }

  #applyState(open) {
    this.sidebarTarget.classList.toggle("sidebar-collapsed", !open)
  }
}
