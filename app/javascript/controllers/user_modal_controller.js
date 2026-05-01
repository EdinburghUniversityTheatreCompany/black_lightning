import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, name: String }

  async open(event) {
    event.preventDefault()

    const result = await window.Swal.fire({
      icon: "question",
      title: this.nameValue,
      text: "You're currently logged in. Click view user profile to change your name, password, see shows that you're involved in, and more.",
      showConfirmButton: true,
      confirmButtonText: "View User Profile",
      showCloseButton: true,
      showCancelButton: true,
      cancelButtonText: "Close"
    })

    if (result.isConfirmed) {
      location.assign(this.urlValue)
    }
  }
}
