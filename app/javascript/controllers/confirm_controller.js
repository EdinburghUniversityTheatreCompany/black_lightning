import { Controller } from "@hotwired/stimulus"

// SweetAlert confirmation for button_to forms, then a native (non-Turbo) submit.
export default class extends Controller {
  static values = { message: String }

  async confirm(event) {
    if (!this.messageValue) return

    event.preventDefault()

    if (!window.Swal) {
      HTMLFormElement.prototype.submit.call(this.element)
      return
    }

    const swalWithBootstrap = window.Swal.mixin({ buttonsStyling: true })
    const result = await swalWithBootstrap.fire({
      icon: "warning",
      html: this.messageValue,
      title: "Are you sure?",
      showCancelButton: true,
      confirmButtonText: "Yes",
      cancelButtonText: "Cancel",
    })

    if (result.value) {
      // Native submit bypasses the Stimulus and Turbo listeners.
      HTMLFormElement.prototype.submit.call(this.element)
    }
  }
}
