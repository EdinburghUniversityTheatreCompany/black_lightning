import { Controller } from "@hotwired/stimulus"

// Scrolls the row a redirect came back for into view.
//
// A fragment in the redirect's Location header does NOT survive a Turbo form
// submission: Turbo submits with fetch, fetch follows the 302 itself, and a
// URL fragment is never transmitted — so `response.url` carries none and the
// visit lands at the top of the page. Measured: approving the fifth card on
// the Review queue came back with main.scrollTop still 0. The redirect keeps
// its fragment (it is what a no-JS navigation honours), and this reads the
// same target from an ordinary query parameter, which does survive.
//
// paramValue names the query parameter; prefixValue is prepended to its value
// to form the element id, so People can reuse the `?person=<id>` it already
// carries rather than growing a second parameter that means the same thing.
export default class extends Controller {
  static values = { param: String, prefix: { type: String, default: "" } }

  connect() {
    const raw = new URLSearchParams(window.location.search).get(this.paramValue)
    if (!raw) return

    // Only ever our own ids, built from a prefix we control plus the record id
    // the server just sent us, so nothing here can be steered at another
    // element by a crafted query string.
    const target = document.getElementById(`${this.prefixValue}${raw}`)
    if (!target) return

    // "start" rather than centring: these rows are tall, and the operator
    // wants the top of the card they acted on under the sticky header, which
    // the element's own scroll-margin already accounts for.
    target.scrollIntoView({ block: "start" })
  }
}
