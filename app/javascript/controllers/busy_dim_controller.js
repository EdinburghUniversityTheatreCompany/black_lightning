import { Controller } from "@hotwired/stimulus"

// Dim a region while a form inside this controller's scope is submitting, so
// stale content visibly recedes until fresh results replace it. Wire it on a
// wrapper around the form and the region:
//
//   data-controller="busy-dim"
//   data-action="turbo:submit-start->busy-dim#start turbo:submit-end->busy-dim#end"
//   ...with data-busy-dim-target="dimmable" on the region to fade.
export default class extends Controller {
  static targets = ["dimmable"]

  start() { this.#toggle(true) }
  end() { this.#toggle(false) }

  #toggle(busy) {
    for (const el of this.dimmableTargets) {
      el.classList.add("transition-opacity")
      el.classList.toggle("opacity-40", busy)
      el.setAttribute("aria-busy", busy ? "true" : "false")
    }
  }
}
