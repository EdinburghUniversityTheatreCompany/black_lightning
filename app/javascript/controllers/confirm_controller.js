import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "../lib/confirm"

// SweetAlert confirmation, then a native (non-Turbo) submit, for a form whose redirect lands on
// another layout: sign-out, and get_link's buttons on the public site. Everywhere else use
// data-turbo-confirm. A Turbo submit follows the redirect in a fetch, which uses up the flash, then
// reloads because the next page has another layout: the message is lost.
export default class extends Controller {
  static values = { message: String }

  async confirm(event) {
    if (!this.messageValue) return

    event.preventDefault()

    if (await confirmDialog(this.messageValue)) {
      // Native submit bypasses the Stimulus and Turbo listeners.
      HTMLFormElement.prototype.submit.call(this.element)
    }
  }
}
