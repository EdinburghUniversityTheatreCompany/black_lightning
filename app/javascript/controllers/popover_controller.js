import { Controller } from "@hotwired/stimulus"
import { createPopper } from "@popperjs/core"

// Accessible click popover: a <button> trigger toggles a Popper-positioned panel,
// closed by Escape or an outside click. The panel moves to <body> so an
// overflow-x-auto or transformed ancestor cannot clip it.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.open = false
    // Keep a reference: panelTarget cannot resolve it once moved.
    this.panel = this.panelTarget
    this.panel.remove()
    document.body.appendChild(this.panel)

    this.onDocumentClick = this.onDocumentClick.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
  }

  disconnect() {
    // TURBO GOTCHA: the panel is on <body>, outside this element, so Turbo will
    // not remove it. Remove it here or it leaks.
    this.hide()
    this.panel?.remove()
  }

  toggle(event) {
    event.preventDefault()
    this.open ? this.hide() : this.show()
  }

  show() {
    if (this.open) return
    this.open = true
    this.panel.classList.remove("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.popper = createPopper(this.triggerTarget, this.panel, {
      placement: "bottom-start",
      modifiers: [
        { name: "offset", options: { offset: [0, 6] } },
        { name: "flip" },
        { name: "preventOverflow", options: { padding: 8 } },
      ],
    })
    // Added during this click's dispatch, so it won't fire for the opening click.
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  hide() {
    if (!this.open) return
    this.open = false
    this.panel.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.popper?.destroy()
    this.popper = null
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
  }

  onDocumentClick(event) {
    if (this.triggerTarget.contains(event.target)) return
    if (this.panel.contains(event.target)) return
    this.hide()
  }

  onKeydown(event) {
    if (event.key !== "Escape") return
    this.hide()
    this.triggerTarget.focus()
  }
}
