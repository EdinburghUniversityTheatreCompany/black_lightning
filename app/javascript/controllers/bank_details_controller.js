import { Controller } from "@hotwired/stimulus"

// Reveals masked bank details. `value` targets swap between the server's
// data-masked and data-revealed text. `field` targets are inputs being edited, so
// they hold the real value behind type="password": a masked value would get
// saved as "****4958".
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
