import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  async submit(event) {
    event.preventDefault()
    const params = new URLSearchParams({ search: this.inputTarget.value }).toString()

    try {
      const response = await fetch(`/admin/membership/check_membership?${params}`)
      const data = await response.json()

      if (data.response === "Member not found") {
        this.#showResult("error", data.response)
      } else {
        this.#showResult("success", data.response, data.image)
      }
    } catch {
      this.#showResult("error", "An error occurred")
    }

    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  #showResult(type, message, imageUrl = null) {
    const options = { icon: type, title: message }
    if (imageUrl) {
      Object.assign(options, { imageUrl, imageWidth: 150, imageHeight: 150, imageAlt: "User Avatar" })
    }
    Swal.fire(options)
  }
}
