import { Controller } from "@hotwired/stimulus"
import { buildWidget } from "../lib/pretix"

// Opens the pretix ticket widget in a dialog, loading pretix's assets on first use.
//
// The base URL defaults to the shop's own domain and must stay in step with
// PretixHelper::SHOP_URL — pretix.eu serves no widget stylesheet (v1.en.css there redirects to
// a 404), so both the script and the CSS come from the shop itself.
export default class extends Controller {
  static targets = ["dialog", "widgetContainer", "title"]
  static values = {
    baseUrl: { type: String, default: "https://tickets.bedlamtheatre.co.uk/" },
    listType: { type: String, default: "list" }
  }

  #eventUrl = null

  open({ params: { slug, name } }) {
    if (this.hasTitleTarget && name) this.titleTarget.textContent = name

    const eventUrl = `${this.baseUrlValue}${slug}/`
    if (eventUrl === this.#eventUrl) {
      this.widgetContainerTarget.scrollTop = 0
    } else {
      // The show is only remembered once its widget is actually up: a build that failed has to
      // be retried on the next open, not answered with the empty dialog it left behind.
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
