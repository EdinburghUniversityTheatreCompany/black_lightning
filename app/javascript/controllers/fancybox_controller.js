import { Controller } from "@hotwired/stimulus"
import { Fancybox } from "@fancyapps/ui"

export default class extends Controller {
  connect() {
    Fancybox.bind(this.element, "[data-fancybox]", {})
  }

  disconnect() {
    Fancybox.unbind(this.element)
    Fancybox.close()
  }
}
