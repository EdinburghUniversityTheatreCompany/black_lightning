import { Controller } from "@hotwired/stimulus"
import { buildWidget } from "../lib/pretix"

// The ticket widget embedded in a show page: an empty container, refilled on every connect,
// including a Turbo visit, where pretix's own script builds nothing (see lib/pretix.js).
export default class extends Controller {
  static values = { baseUrl: String, eventUrl: String, listType: String }

  connect() {
    // A restore visit renders Turbo's cached snapshot as a preview, then the real body, so this
    // connects twice. pretix keeps every widget it builds with no teardown, so building against
    // the discarded preview leaks a Vue instance and a shop request.
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    buildWidget(this.element, {
      baseUrl: this.baseUrlValue,
      eventUrl: this.eventUrlValue,
      listType: this.listTypeValue
    })
  }
}
