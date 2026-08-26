import { Controller } from "@hotwired/stimulus"
import { buildWidget } from "../lib/pretix"

// The ticket widget embedded in a show page: an empty container, refilled on every connect —
// including a Turbo visit, where pretix's own script builds nothing (see lib/pretix.js).
export default class extends Controller {
  static values = { baseUrl: String, eventUrl: String, listType: String }

  connect() {
    // On a restore visit Turbo renders its cached snapshot as a preview and then the real body,
    // connecting this twice. pretix keeps every widget it builds and offers no teardown, so a
    // build against the discarded preview costs a Vue instance and a shop request for good.
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    buildWidget(this.element, {
      baseUrl: this.baseUrlValue,
      eventUrl: this.eventUrlValue,
      listType: this.listTypeValue
    })
  }
}
