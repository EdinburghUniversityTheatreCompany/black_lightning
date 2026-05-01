import { Controller } from "@hotwired/stimulus"
import itify_add, { itify_init } from "../lib/itify"

// Easter egg: listens for the Konami code sequence on window keydown events.
// Image URLs are resolved server-side by ItifyHelper and passed in via
// data-konami-code-heads-value / data-konami-code-pineapple-value so images
// are handled by Sprockets (correct fingerprinting) and not fetched until
// the easter egg is triggered.
//
// Usage:
//   <body data-controller="konami-code"
//         data-action="keydown@window->konami-code#keyDown"
//         data-konami-code-heads-value="<%= itify_head_urls.to_json %>"
//         data-konami-code-pineapple-value="<%= asset_path('easter_egg/pineapple.png') %>">
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
