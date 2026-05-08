import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "admin-sidebar-open"
const MOBILE_BREAKPOINT = 768

export default class extends Controller {
  static targets = ["sidebar", "backdrop"]

  connect() {
    const isMobile = window.innerWidth < MOBILE_BREAKPOINT
    const stored = localStorage.getItem(STORAGE_KEY)
    const isOpen = isMobile ? false : (stored === null ? true : stored === "true")
    this.#applyState(isOpen)
    document.addEventListener("turbo:before-visit", this.#collapseOnNavigate)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.#collapseOnNavigate)
  }

  toggle() {
    const isOpen = !this.sidebarTarget.classList.contains("sidebar-collapsed")
    if (window.innerWidth >= MOBILE_BREAKPOINT) {
      localStorage.setItem(STORAGE_KEY, String(!isOpen))
    }
    this.#applyState(!isOpen)
  }

  #collapseOnNavigate = () => {
    if (window.innerWidth < MOBILE_BREAKPOINT) {
      this.#applyState(false)
    }
  }

  #applyState(open) {
    this.sidebarTarget.classList.toggle("sidebar-collapsed", !open)
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.toggle("hidden", !(open && window.innerWidth < MOBILE_BREAKPOINT))
    }
  }
}
