import { Controller } from "@hotwired/stimulus"

// Running total for the split-an-EUSA-credit form: says how much of the row is
// still unallocated and holds Save disabled until the parts add up.
//
// The SERVER is what refuses a short split (ActualsController#total_rule_error
// and DatabaseStore#apportion_actual! both do). This only saves the operator a
// round trip, and states the gap while they type — an arithmetic error found
// after the redirect is one they have to reconstruct.
//
// Amounts are read the way Reimbursements::AmountParser reads them, including
// the comma decimal: naively stripping the comma from "12,50" records 1250.
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

  // Mirrors AmountParser: strip the currency symbol and spaces, treat a
  // trailing ",dd" with no "." as a decimal comma, otherwise drop commas.
  // Returns null for anything that is not a number, so the caller can say so
  // rather than silently counting it as zero.
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

  // Pence, so floating-point drift can never leave a balanced split reading
  // as a fraction of a penny out and the button stuck disabled.
  #round(value) {
    return Math.round(value * 100) / 100
  }

  // Matches reimbursements_money's number_to_currency output, so the running
  // total and the figure on the card beside it read the same. The separator
  // goes into the whole part only — running it over "1500.00" would comma the
  // decimals too.
  #money(value) {
    const [whole, decimals] = value.toFixed(2).split(".")
    return `${this.currencyValue}${whole.replace(/\B(?=(\d{3})+$)/g, ",")}.${decimals}`
  }
}
