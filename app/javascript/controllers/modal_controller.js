import { Controller } from "@hotwired/stimulus"

// Generic controller for a native <dialog>.
export default class extends Controller {
  open() {
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  // A backdrop click targets the <dialog> itself.
  backdropClose({ target }) {
    if (target === this.element) this.element.close()
  }
}
