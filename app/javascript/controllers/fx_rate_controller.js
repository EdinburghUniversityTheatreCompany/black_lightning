import { Controller } from "@hotwired/stimulus"

// The implied exchange rate behind the GBP figure finance types for an
// international claim.
//
// The submitter enters the invoice amount; finance types what it is expected
// to cost in pounds, and the budget counts THAT figure until reconciliation
// corrects it to what the bank charged. Nothing on the form helped with the
// arithmetic, so a decimal slip or a currency pasted straight into the pounds
// box went in as real money against a budget.
//
// The portal does not know today's rate and does not pretend to: it shows the
// rate the typed pair IMPLIES, which an operator who knows roughly what EUR
// buys will read at a glance, and warns only when that rate is absurd on any
// day — a factor of 100 either way, which is what a misplaced decimal or a
// pasted foreign figure looks like. A band tight enough to be "today's rate"
// would be wrong the week after it was written.
export default class extends Controller {
  static targets = ["amount", "output"]
  static values = {
    foreignAmount: Number,
    currency: { type: String, default: "" },
    // Outside this, the pair cannot be a real conversion in any market.
    minRate: { type: Number, default: 0.01 },
    maxRate: { type: Number, default: 100 }
  }

  connect() {
    this.render()
  }

  render() {
    if (!this.hasOutputTarget) return

    const gbp = this.#gbp()
    const foreign = this.foreignAmountValue

    if (!(foreign > 0) || !(gbp > 0)) {
      this.outputTarget.textContent = ""
      this.outputTarget.classList.remove("text-warning")
      return
    }

    const rate = foreign / gbp
    const implausible = rate < this.minRateValue || rate > this.maxRateValue
    const unit = this.currencyValue || "unit"

    this.outputTarget.textContent = implausible
      ? `That works out at 1 ${unit} = £${this.#round(1 / rate)}, which is not a real rate — check the figure.`
      : `That works out at 1 ${unit} = £${this.#round(1 / rate)}.`
    this.outputTarget.classList.toggle("text-warning", implausible)
  }

  #gbp() {
    if (!this.hasAmountTarget) return 0
    return Number.parseFloat(this.amountTarget.value)
  }

  // Four places, because a weak currency's rate is a small number and two
  // would round it to nothing.
  #round(value) {
    return value.toFixed(4).replace(/0+$/, "").replace(/\.$/, "")
  }
}
