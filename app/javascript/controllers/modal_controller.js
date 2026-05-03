import { Controller } from "@hotwired/stimulus"

// Generic controller for native <dialog> elements.
//
// Usage:
//   <dialog data-controller="modal">
//     <button data-action="click->modal#close">Close</button>
//   </dialog>
//
//   <!-- trigger button, anywhere in the ancestor scope: -->
//   <button data-action="click->modal#open">Open</button>
//
// For triggers outside the controller scope, use Stimulus outlets or
// the template-loader controller's open/close actions as a pattern.
export default class extends Controller {
  open() {
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  // Close when the user clicks the backdrop (the dialog element itself,
  // outside the rendered dialog content box).
  backdropClose({ target }) {
    if (target === this.element) this.element.close()
  }
}
