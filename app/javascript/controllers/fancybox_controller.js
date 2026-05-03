import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async connect() {
    const [{ Fancybox }] = await Promise.all([
      import("@fancyapps/ui"),
      import("@fancyapps/ui/dist/fancybox/fancybox.css"),
    ])
    this.#Fancybox = Fancybox
    Fancybox.bind(this.element, "[data-fancybox]", {})
  }

  disconnect() {
    this.#Fancybox?.unbind(this.element)
    this.#Fancybox?.close()
  }

  #Fancybox = null
}
