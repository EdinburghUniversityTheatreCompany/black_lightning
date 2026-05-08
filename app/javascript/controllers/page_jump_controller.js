import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  jump() {
    const page = parseInt(this.element.value, 10)
    if (!page || page < 1) return

    const url = new URL(window.location.href)
    url.searchParams.set("page", page)
    window.location.href = url.toString()
  }
}
