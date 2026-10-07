import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "../lib/confirm"

// SweetAlert confirmation for button_to forms, then a native (non-Turbo) submit.
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
