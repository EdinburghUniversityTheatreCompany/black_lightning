import { Controller } from "@hotwired/stimulus"

// Running total for the split-an-EUSA-credit form: what is left to allocate, with
// Save disabled until the parts add up. The server is what refuses a short
// split; this only saves a round trip.
export default class extends Controller {
  static targets = ["amount", "summary", "submit"]
  static values = { target: String, currency: { type: String, default: "£" } }

  connect() {
    this.recalculate()
  }

  recalculate() {
    const target = this.#round(Number(this.targetValue))
    let allocated = 0
    let unreadable = false

    for (const field of this.amountTargets) {
      const raw = field.value.trim()
      if (raw === "") continue

      const parsed = this.#parse(raw)
      if (parsed === null) {
        unreadable = true
      } else {
        allocated += this.#round(parsed)
      }
    }

    const remaining = this.#round(target - this.#round(allocated))
    this.#render(remaining, unreadable)
  }

  #render(remaining, unreadable) {
    const balanced = remaining === 0 && !unreadable

    if (this.hasSummaryTarget) {
      if (unreadable) {
        this.summaryTarget.textContent = "One of those amounts is not a number"
      } else if (balanced) {
        this.summaryTarget.textContent = "The parts add up"
      } else if (remaining > 0) {
        this.summaryTarget.textContent = `${this.#money(remaining)} left to allocate`
      } else {
        this.summaryTarget.textContent = `${this.#money(-remaining)} over`
      }
      this.summaryTarget.classList.toggle("text-danger", !balanced)
    }

    if (this.hasSubmitTarget) this.submitTarget.disabled = !balanced
  }

  // Mirrors Reimbursements::AmountParser, comma decimal included: "12,50" is
  // 12.50, not 1250. Null when unreadable, so it is reported rather than zero.
  #parse(value) {
    let cleaned = value.replace(/[£\s]/g, "")
    if (cleaned === "") return null

    cleaned = /,\d{1,2}$/.test(cleaned) && !cleaned.includes(".")
      ? cleaned.replace(/,/g, ".")
      : cleaned.replace(/,/g, "")

    if (!/^-?\d*\.?\d+$/.test(cleaned)) return null
    const parsed = Number(cleaned)
    return Number.isFinite(parsed) ? parsed : null
  }

  // To pence, so float drift cannot leave a balanced split disabled.
  #round(value) {
    return Math.round(value * 100) / 100
  }

  // As reimbursements_money prints it. The thousands separator goes on the
  // whole part only.
  #money(value) {
    const [whole, decimals] = value.toFixed(2).split(".")
    return `${this.currencyValue}${whole.replace(/\B(?=(\d{3})+$)/g, ",")}.${decimals}`
  }
}
