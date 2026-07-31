import { Controller } from "@hotwired/stimulus"

// A file input can't be re-populated from markup after a failed submit, so a
// server 422 re-render would lose the receipt the user picked. Hold it in JS
// instead — module scope survives Turbo's body swap on a 422 render — and
// restore it via DataTransfer (the one browser-sanctioned way to set
// input.files). Cleared on a successful submit or a fresh (non-resubmit) form.
let stashedFiles = null

// Receipt-first expense form. Everything here is a progressive enhancement over
// a form that already works with JavaScript off: it keeps the picked receipt
// across a failed submit, and surfaces the payee and large-amount rules inline
// rather than only at submit time. The server validates all of it regardless.
export default class extends Controller {
  static targets = ["files", "status", "amount", "reference", "referenceCounter",
    "reattachNotice", "largeAmountWarning", "expenseType", "payeeOptional",
    "payeeRequired"]
  static values = {
    resubmit: Boolean,
    largeAmountThreshold: { type: Number, default: 1000 },
    invoiceType: String,
  }

  connect() {
    this.updateCounter()
    this.#restoreOrClearStash()
    this.typeChanged()
  }

  // Says the payee trio is required on an Invoice before the submit does; the
  // server both enforces the rule and renders the labels for the no-JS case.
  typeChanged() {
    if (!this.hasExpenseTypeTarget || !this.hasPayeeOptionalTarget) return
    const invoice = this.expenseTypeTarget.value === this.invoiceTypeValue
    this.payeeOptionalTarget.classList.toggle("hidden", invoice)
    this.payeeRequiredTarget.classList.toggle("hidden", !invoice)
  }

  // Keep a reference to the picked files so a failed submit doesn't lose them.
  stash() {
    if (this.hasFilesTarget && this.filesTarget.files.length) {
      stashedFiles = this.filesTarget.files
    }
  }

  submitEnd(event) {
    if (event.detail?.success) stashedFiles = null
  }

  #restoreOrClearStash() {
    if (!this.hasFilesTarget) return
    // A fresh form (not a re-render after a validation error) should start
    // clean — don't resurrect a file from an abandoned earlier attempt.
    if (!this.resubmitValue) {
      stashedFiles = null
      return
    }
    if (!stashedFiles || this.filesTarget.files.length) return

    const data = new DataTransfer()
    for (const file of stashedFiles) data.items.add(file)
    this.filesTarget.files = data.files
    // The file survived, so the "please re-attach" fallback no longer applies.
    if (this.hasReattachNoticeTarget) this.reattachNoticeTarget.classList.add("hidden")
    this.#setStatus("Kept the receipt you attached. Check the errors above and submit again.")
  }

  // Reveal the large-amount confirmation as soon as the amount crosses the
  // threshold, so the producer isn't surprised by it only at submit time.
  checkAmount() {
    if (!this.hasLargeAmountWarningTarget || !this.hasAmountTarget) return
    const value = this.#parseAmount(this.amountTarget.value)
    const large = Number.isFinite(value) && value >= this.largeAmountThresholdValue
    this.largeAmountWarningTarget.classList.toggle("hidden", !large)
  }

  // Mirror the server's ExpenseForm#parse_decimal: a trailing "," with 1-2
  // digits and no "." is a decimal comma ("999,99" -> 999.99), otherwise
  // commas are thousands separators. Without this "999,99" parsed as 99999
  // and falsely tripped the large-amount warning the server wouldn't require.
  #parseAmount(raw) {
    const cleaned = raw.replace(/[£\s]/g, "")
    const normalised = /,\d{1,2}$/.test(cleaned) && !cleaned.includes(".")
      ? cleaned.replace(",", ".")
      : cleaned.replace(/,/g, "")
    return parseFloat(normalised)
  }

  updateCounter() {
    if (!this.hasReferenceTarget || !this.hasReferenceCounterTarget) return
    const max = this.referenceTarget.maxLength
    const used = this.referenceTarget.value.length
    this.referenceCounterTarget.textContent = `${max - used} of ${max} characters left (EUSA cuts off anything longer)`
  }

  #setStatus(message) {
    this.statusTarget.textContent = message
  }
}
