import { Controller } from "@hotwired/stimulus"
import itify_add, { itify_init } from "../lib/itify"

// Easter egg: the Konami code adds IT-committee heads (lib/itify.js). Image URLs
// come from ItifyHelper via data values, so nothing is fetched until it triggers.
export default class extends Controller {
  static values = { index: Number, heads: Array, pineapple: String }

  connect() {
    this.indexValue = 0
    this.konamiKeys = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"]
    this.cornified = false
    itify_init(this.headsValue, this.pineappleValue)
  }

  disconnect() {
    this.indexValue = 0
    this.cornified = false
  }

  keyDown(event) {
    const key = event.key

    if (this.cornified) {
      itify_add()
      return
    }

    if (key === this.konamiKeys[this.indexValue]) {
      this.indexValue++
      if (this.indexValue === this.konamiKeys.length) {
        itify_add()
        this.cornified = true
      }
    } else {
      this.indexValue = 0
    }
  }
}
