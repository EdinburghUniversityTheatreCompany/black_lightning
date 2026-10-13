import { Controller } from "@hotwired/stimulus"
import { buildWidget } from "../lib/pretix"

// Opens the pretix ticket widget in a dialog, loading pretix's assets on first use. The
// base URL is the shop's (PretixHelper): pretix.eu serves no widget stylesheet, so script
// and CSS both come from the shop.
export default class extends Controller {
  static targets = ["dialog", "widgetContainer", "title"]
  static values = {
    baseUrl: String,
    listType: { type: String, default: "list" }
  }

  #eventUrl = null

  open({ params: { slug, name } }) {
    if (this.hasTitleTarget && name) this.titleTarget.textContent = name

    const eventUrl = `${this.baseUrlValue}${slug}/`
    if (eventUrl === this.#eventUrl) {
      this.widgetContainerTarget.scrollTop = 0
    } else {
      // Remembered only once its widget is up: a failed build must be retried on the next
      // open, not answered with the empty dialog it left behind.
      this.#eventUrl = null
      buildWidget(this.widgetContainerTarget, {
        baseUrl: this.baseUrlValue,
        eventUrl,
        listType: this.listTypeValue
      }).then((built) => { if (built) this.#eventUrl = eventUrl })
    }

    this.dialogTarget.showModal()
  }
}
