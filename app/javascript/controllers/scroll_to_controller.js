import { Controller } from "@hotwired/stimulus"

// Scrolls the row a redirect came back for into view. A redirect's URL fragment
// does not survive a Turbo (fetch) form submission, so the target travels as a
// query parameter: prefixValue plus the param's value is the element id.
export default class extends Controller {
  static values = { param: String, prefix: { type: String, default: "" } }

  connect() {
    const raw = new URLSearchParams(window.location.search).get(this.paramValue)
    if (!raw) return

    const target = document.getElementById(`${this.prefixValue}${raw}`)
    if (!target) return

    // The rows are tall; the element's scroll-margin clears the sticky header.
    target.scrollIntoView({ block: "start" })
  }
}
