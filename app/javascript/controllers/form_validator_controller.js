import { Controller } from "@hotwired/stimulus"

// Marks inputs is-valid / is-invalid from HTML5 constraint validation, on connect
// and as the user types. Inputs the server marked .is-invalid are left alone
// until touched; nojsvalidation inputs and search forms are skipped.
export default class extends Controller {
  connect() {
    this.#markServerErrors()
    this.#validateExistingInputs()

    this.boundDelegatedInput = this.#handleDelegatedInput.bind(this)
    this.element.addEventListener("input", this.boundDelegatedInput, true)
  }

  disconnect() {
    if (this.boundDelegatedInput) {
      this.element.removeEventListener("input", this.boundDelegatedInput, true)
    }
  }

  #handleDelegatedInput(event) {
    const input = event.target
    if (!(input instanceof HTMLInputElement)) return
    if (this.#shouldSkip(input)) return

    this.#validate(input)
  }

  #markServerErrors() {
    this.element.querySelectorAll("input.is-invalid").forEach((input) => {
      input.setAttribute("data-server-error", "true")
    })
  }

  #validateExistingInputs() {
    this.element.querySelectorAll("input").forEach((input) => {
      if (this.#shouldSkip(input)) return
      if (input.hasAttribute("data-server-error")) return

      this.#validate(input)
    })
  }

  #shouldSkip(input) {
    if (input.hasAttribute("nojsvalidation")) return true

    const form = input.closest("form")
    if (form && form.classList.contains("search-form")) return true

    return false
  }

  #validate(input) {
    if (input.hasAttribute("data-server-error")) {
      input.removeAttribute("data-server-error")
    }

    if (input.checkValidity()) {
      input.classList.remove("is-invalid")
      input.classList.add("is-valid")
    } else {
      input.classList.remove("is-valid")
      input.classList.add("is-invalid")
    }
  }
}
