import { Controller } from "@hotwired/stimulus"
import { createPopper } from "@popperjs/core"

// Accessible click popover. A real <button> trigger toggles a panel that Popper
// positions (with flip + overflow handling), so the reasons that used to hide in
// a title= tooltip are now reachable by keyboard and screen readers.
//
// The trigger carries aria-expanded + aria-controls; opens on click / Enter /
// Space (native button semantics), closes on Escape and outside-click. The panel
// is portaled to <body> on connect so a table's overflow-x-auto (or any
// transformed/clipping ancestor) can't cut it off.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.open = false
    // Keep a direct reference: once the panel is moved out of this controller's
    // subtree, `this.panelTarget` can no longer resolve it.
    this.panel = this.panelTarget
    this.panel.remove()
    document.body.appendChild(this.panel)

    this.onDocumentClick = this.onDocumentClick.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
  }

  disconnect() {
    // TURBO GOTCHA: the panel lives on <body>, outside this element's subtree, so
    // Turbo's cache/restore won't remove it. Tear it down here or it leaks.
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
