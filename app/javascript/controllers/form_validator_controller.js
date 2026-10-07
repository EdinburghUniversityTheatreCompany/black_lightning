import { Controller } from "@hotwired/stimulus"

// Marks inputs is-valid / is-invalid from HTML5 constraint validation, on connect
// and as the user types. Inputs the server marked .is-invalid are left alone
// until touched; nojsvalidation inputs and search forms are skipped.
export default class extends Controller {
  connect() {
    this.element.querySelectorAll("input").forEach((input) => {
      if (!this.#shouldSkip(input) && !input.classList.contains("is-invalid")) this.#validate(input)
    })

    this.element.addEventListener("input", this.#onInput, true)
  }

  disconnect() {
    this.element.removeEventListener("input", this.#onInput, true)
  }

  #onInput = (event) => {
    const input = event.target
    if (input instanceof HTMLInputElement && !this.#shouldSkip(input)) this.#validate(input)
  }

  #shouldSkip(input) {
    return input.hasAttribute("nojsvalidation") || Boolean(input.closest("form")?.classList.contains("search-form"))
  }

  #validate(input) {
    const valid = input.checkValidity()
    input.classList.toggle("is-valid", valid)
    input.classList.toggle("is-invalid", !valid)
  }
}
