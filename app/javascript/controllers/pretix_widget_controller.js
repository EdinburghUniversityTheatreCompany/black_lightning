import { Controller } from "@hotwired/stimulus"
import { buildWidget } from "../lib/pretix"

// The ticket widget embedded in a show page: an empty container, refilled on every connect —
// including a Turbo visit, where pretix's own script builds nothing (see lib/pretix.js).
//
// pretix keeps every widget it builds in a private list and offers no teardown, so each build
// costs a Vue instance the page can never reclaim. That is why the redundant ones are avoided
// here rather than cleaned up afterwards.
export default class extends Controller {
  static values = { baseUrl: String, eventUrl: String, listType: String }

  connect() {
    // On a restore visit Turbo renders its cached snapshot as a preview and then the real body,
    // connecting this twice. Building against the preview spends a widget — and a request to
    // the shop — on markup that is discarded a moment later.
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    buildWidget(this.element, {
      baseUrl: this.baseUrlValue,
      eventUrl: this.eventUrlValue,
      listType: this.listTypeValue
    })
  }
}
