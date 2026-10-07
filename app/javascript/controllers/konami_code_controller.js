import { Controller } from "@hotwired/stimulus"
import itify_add, { itify_init } from "../lib/itify"

const KONAMI = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"]

// Easter egg: the Konami code adds IT-committee heads (lib/itify.js). Image URLs
// come from ItifyHelper via data values, so nothing is fetched until it triggers.
export default class extends Controller {
  static values = { heads: Array, pineapple: String }

  #index = 0
  #cornified = false

  connect() {
    this.#index = 0
    this.#cornified = false
    itify_init(this.headsValue, this.pineappleValue)
  }

  keyDown(event) {
    if (this.#cornified) {
      itify_add()
      return
    }

    if (event.key === KONAMI[this.#index]) {
      this.#index++
      if (this.#index === KONAMI.length) {
        itify_add()
        this.#cornified = true
      }
    } else {
      this.#index = 0
    }
  }
}
