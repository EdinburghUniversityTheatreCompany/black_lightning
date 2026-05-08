import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "admin-sidebar-open"
const MOBILE_BREAKPOINT = 768

export default class extends Controller {
  static targets = ["sidebar"]

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const isOpen = stored === null ? true : stored === "true"
    this.#applyState(isOpen)
    document.addEventListener("turbo:before-visit", this.#collapseOnNavigate)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.#collapseOnNavigate)
  }

  toggle() {
    const isOpen = !this.sidebarTarget.classList.contains("sidebar-collapsed")
    localStorage.setItem(STORAGE_KEY, String(!isOpen))
    this.#applyState(!isOpen)
  }

  #collapseOnNavigate = () => {
    if (window.innerWidth < MOBILE_BREAKPOINT) {
      this.#applyState(false)
    }
  }

  #applyState(open) {
    this.sidebarTarget.classList.toggle("sidebar-collapsed", !open)
  }
}
