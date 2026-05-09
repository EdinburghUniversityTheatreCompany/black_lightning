import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]

  frameLoaded() {
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  backdropClose({ target }) {
    if (target === this.element) this.close()
  }
}
