import { Controller } from "@hotwired/stimulus"

// Adds Bootstrap is-valid / is-invalid classes to inputs based on the HTML5
// constraint validation API. Replaces the legacy jQuery input_validator.js.
//
// Behaviour:
//   * On connect, every input under this controller's scope is validated
//     immediately so the user can see which required fields they still need
//     to fill in.
//   * Any input event on a descendant input revalidates that input, so the
//     classes update in real time as the user types.
//   * Inputs that already carry the .is-invalid class on connect are assumed
//     to have a server-side error: they are left untouched until the user
//     interacts with them, at which point client validation takes over.
//   * Inputs marked with the `nojsvalidation` attribute, or that live inside
//     a form with the `search-form` class, are skipped entirely.
//   * Event delegation means dynamically inserted inputs (e.g. from
//     stimulus-rails-nested-form) are automatically validated on input
//     without any extra wiring, but they will not be validated proactively
//     until the user interacts with them.
//
// Usage: attach `data-controller="form-validator"` to <body> (or any
// element that wraps the forms you want validated). One controller per page
// is enough — it scopes to its own element.
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

  // Private

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
    // Once the user touches a field with a server error, hand off to client
    // validation so the message updates as they type rather than sticking.
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
