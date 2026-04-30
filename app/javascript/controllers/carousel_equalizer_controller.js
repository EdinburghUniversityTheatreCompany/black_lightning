import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["caption"]

  connect() {
    this.#equalizeHeights()
  }

  #equalizeHeights() {
    const captions = this.captionTargets
    if (captions.length === 0) return

    captions.forEach(el => el.style.minHeight = "")
    const maxHeight = Math.max(...captions.map(el => el.offsetHeight))
    captions.forEach(el => el.style.minHeight = `${maxHeight}px`)
  }
}
