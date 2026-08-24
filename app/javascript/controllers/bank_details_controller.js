import { Controller } from "@hotwired/stimulus"

// Reveals bank details that are masked by default. Two kinds of target,
// because the two places they appear need opposite treatment:
//
//   value — read-only text. Swapped between the data-masked and data-revealed
//           strings the server rendered.
//   field — an <input> the operator is about to EDIT (the People registry). Its
//           value has to be the real one for editing to work, so it is hidden
//           with type="password" rather than masked — masking the value itself
//           would invite saving "****4958" as an account number.
//
// Without JavaScript the masked form stays on screen, which is still the useful
// half: the last four digits are what finance eyeball-matches against a bank
// statement.
export default class extends Controller {
    static targets = ["value", "field", "toggle"]

    connect() {
        this.revealed = false
        this.fieldTargets.forEach((field) => { field.type = "password" })
    }

    toggle() {
        this.revealed = !this.revealed

        this.valueTargets.forEach((value) => {
            value.textContent = value.dataset[this.revealed ? "revealed" : "masked"]
        })
        this.fieldTargets.forEach((field) => {
            field.type = this.revealed ? "text" : "password"
        })
        this.toggleTargets.forEach((toggle) => {
            toggle.setAttribute("aria-pressed", String(this.revealed))
            toggle.textContent = this.revealed ? "Hide" : "Reveal"
        })
    }
}
