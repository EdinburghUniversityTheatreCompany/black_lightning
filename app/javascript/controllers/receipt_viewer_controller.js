import { Controller } from "@hotwired/stimulus"

// Thumbnail buttons and one pane showing one receipt at a time. Sources load from
// data-src on first show, so a review queue fetches no receipt until asked.
// Visibility uses the `hidden` attribute, not a class, so display utilities in
// the markup cannot outrank it.
export default class extends Controller {
  static targets = ["pane", "thumb", "frame", "status"]

  // Activating the receipt already on screen closes the pane.
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

    // The Hide button is inside the pane it hid, so focus returns to the thumbnail.
    this.thumbTargets[this.#index]?.focus()
    this.#index = null
  }

  // ActiveStorage raises PreviewError when a preview is requested, not at upload,
  // so a malformed PDF arrives here as a failed thumbnail: show the document icon.
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
