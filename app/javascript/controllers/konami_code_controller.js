import { Controller } from "@hotwired/stimulus"
import cornify_add from "../src/vendor/cornify"

// Easter egg: listens for the Konami code sequence on window keydown events.
// Once the full sequence is entered, calls into the locally-vendored cornify
// library to add a unicorn/rainbow to the page. Subsequent keypresses add more
// cornifications.
//
// Cornify is bundled locally (see app/javascript/src/vendor/cornify.js) rather
// than loaded from cornify.com so the page can run under a strict CSP without
// allowing remote script-src.
//
// Usage:
//   <body data-controller="konami-code"
//         data-action="keydown@window->konami-code#keyDown">
export default class extends Controller {
  static values = { index: Number }

  connect() {
    this.indexValue = 0
    this.konamiKeys = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"]
    this.cornified = false
  }

  disconnect() {
    this.indexValue = 0
    this.cornified = false
  }

  keyDown(event) {
    const key = event.key

    // Once cornified, every subsequent keypress adds another unicorn/rainbow.
    if (this.cornified) {
      cornify_add()
      return
    }

    if (key === this.konamiKeys[this.indexValue]) {
      this.indexValue++
      if (this.indexValue === this.konamiKeys.length) {
        cornify_add()
        this.cornified = true
      }
    } else {
      this.indexValue = 0
    }
  }
}
