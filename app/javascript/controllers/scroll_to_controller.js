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
    const box = target.closest(".table-scroll")
    if (!box) {
      target.scrollIntoView({ block: "start" })
      return
    }

    // Inside a table's own scroll box, scrollIntoView also scrolls the page until the box's
    // sticky column headers leave the screen. Bring the box into view, then scroll only the box.
    box.scrollIntoView({ block: "start" })
    const margin = parseFloat(getComputedStyle(target).scrollMarginTop) || 0
    box.scrollTop += target.getBoundingClientRect().top - box.getBoundingClientRect().top - margin
  }
}
