import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  async send(event) {
    event.preventDefault()
    await fetch(this.urlValue, { method: "POST" })
  }
}
