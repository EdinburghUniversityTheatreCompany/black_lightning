import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "widget"]
  static values = { baseUrl: { type: String, default: "https://tickets.bedlamtheatre.co.uk/" } }

  open({ params: { slug } }) {
    this.widgetTarget.setAttribute("event", `${this.baseUrlValue}${slug}/`)
    this.#loadPretix()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose({ target }) {
    if (target === this.dialogTarget) this.dialogTarget.close()
  }

  #loadPretix() {
    if (document.getElementById("pretix-widget-script")) return

    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = "https://pretix.eu/widget/v1.en.css"
    document.head.appendChild(link)

    const script = document.createElement("script")
    script.id = "pretix-widget-script"
    script.src = "https://pretix.eu/widget/v1.en.js"
    script.async = true
    document.head.appendChild(script)
  }
}
