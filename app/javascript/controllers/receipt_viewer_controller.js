import { Controller } from "@hotwired/stimulus"

// In-page receipt viewer: a strip of thumbnail buttons plus one large pane that
// shows a single receipt at a time (see shared/_receipt_viewer.html.erb).
//
// Lazy by design. Every <img>/<iframe> in the pane ships with data-src and no
// src, and the source is copied across the first time that receipt is shown, so
// a twenty-claim review queue fetches no receipt documents until an operator
// asks for one — and reopening a receipt does not refetch it.
//
// Visibility is toggled through the `hidden` attribute, never a class, so the
// markup can stay free of display utilities that would outrank it.
export default class extends Controller {
  static targets = ["pane", "thumb", "frame", "status"]

  // Show the receipt whose thumbnail was activated. Activating the receipt that
  // is already on screen closes the pane again, so one control both opens and
  // closes it.
  show(event) {
    const index = Number(event.currentTarget.dataset.receiptIndex)

    if (this.#index === index && !this.paneTarget.hidden) {
      this.hide()
      return
    }

    this.#index = index
    this.paneTarget.hidden = false

    this.frameTargets.forEach((frame, position) => {
      frame.hidden = position !== index
      if (position === index) this.#load(frame)
    })
    this.thumbTargets.forEach((thumb, position) => {
      thumb.setAttribute("aria-expanded", position === index ? "true" : "false")
    })

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = event.currentTarget.dataset.receiptStatus ?? ""
    }
  }

  hide() {
    this.paneTarget.hidden = true
    this.thumbTargets.forEach((thumb) => thumb.setAttribute("aria-expanded", "false"))
    if (this.hasStatusTarget) this.statusTarget.textContent = ""

    // The Hide button lives inside the pane it just hid, so hand focus back to
    // the thumbnail that opened it rather than dropping it on <body>.
    this.thumbTargets[this.#index]?.focus()
    this.#index = null
  }

  // A preview that cannot be generated must degrade to the document icon
  // instead of leaving a broken image. ActiveStorage raises PreviewError when
  // the representation is REQUESTED, not at upload, so a malformed PDF (phone
  // cameras and arbitrary suppliers guarantee some) surfaces here as a failed
  // thumbnail request.
  imageFailed(event) {
    const image = event.target
    image.hidden = true

    const fallback = image.closest("[data-receipt-slot]")?.querySelector("[data-receipt-fallback]")
    if (fallback) fallback.hidden = false
  }

  #load(frame) {
    frame.querySelectorAll("[data-src]").forEach((element) => {
      element.src = element.dataset.src
      delete element.dataset.src
    })
  }

  #index = null
}
