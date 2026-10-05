import { Controller } from "@hotwired/stimulus"

// The exchange rate implied by the GBP figure finance types for an international
// claim. It knows no real rate, so it warns only at a factor of 100 either way:
// a slipped decimal, or a foreign figure pasted into the pounds box.
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

  // Four places: a weak currency's rate rounds to nothing at two.
  #round(value) {
    return value.toFixed(4).replace(/0+$/, "").replace(/\.$/, "")
  }
}
