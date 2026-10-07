import { Controller } from "@hotwired/stimulus"

// A file input can't be re-populated from markup, so a 422 re-render would lose
// the picked receipt. Module scope survives Turbo's body swap, and DataTransfer
// is the only way to set input.files. Cleared on a successful submit or a fresh
// form.
let stashedFiles = null

// Receipt-first expense form. A progressive enhancement over a form that works
// without JavaScript; the server validates everything regardless.
export default class extends Controller {
  static targets = ["files", "status", "amount", "amountExclVat", "reference",
    "referenceCounter", "reattachNotice", "largeAmountWarning", "vatWarning",
    "expenseType", "payeeOptional", "payeeRequired", "payeeInternational",
    "ukPayeeCopy", "internationalPayeeCopy",
    "paymentMethod", "ukFields", "internationalFields", "ukAmount", "internationalAmount"]
  static values = {
    resubmit: Boolean,
    largeAmountThreshold: { type: Number, default: 1000 },
    invoiceType: String,
    internationalMethod: String,
  }

  connect() {
    this.updateCounter()
    this.#restoreOrClearStash()
    this.paymentMethodChanged()
  }

  // Swaps the bank and amount fields for the rail's own. With JavaScript off the
  // form still shows everything and the server enforces the rail's fields.
  paymentMethodChanged() {
    if (!this.hasPaymentMethodTarget || !this.hasUkFieldsTarget) return
    const international = this.#isInternational()
    this.#updatePayeeLabels()
    this.ukFieldsTarget.classList.toggle("hidden", international)
    this.internationalFieldsTarget.classList.toggle("hidden", !international)
    if (this.hasUkAmountTarget) this.#showSection(this.ukAmountTarget, !international)
    if (this.hasInternationalAmountTarget) {
      this.#showSection(this.internationalAmountTarget, international)
    }
  }

  // `required` moves with visibility: a hidden input carrying it silently blocks
  // the whole submit. It comes from data-rail-required, never a snapshot: the
  // server renders the inactive rail's fields as not-required, so a snapshot
  // would record false and never restore it.
  #showSection(section, visible) {
    section.classList.toggle("hidden", !visible)
    section.querySelectorAll("input, select, textarea").forEach((field) => {
      field.required = visible && field.dataset.railRequired === "true"
    })
  }

  // Says the payee trio is required before the submit does.
  typeChanged() {
    this.#updatePayeeLabels()
  }

  // The payee is optional on a UK reimbursement, required on a UK invoice and
  // ALWAYS required on the international rail (no IBAN is on file to fall back
  // to). Type and rail both change the answer, so one method sets the labels
  // rather than each toggling a subset.
  #updatePayeeLabels() {
    if (!this.hasExpenseTypeTarget || !this.hasPayeeOptionalTarget) return
    const international = this.#isInternational()
    const invoice = !international && this.expenseTypeTarget.value === this.invoiceTypeValue

    this.payeeOptionalTarget.classList.toggle("hidden", invoice || international)
    this.payeeRequiredTarget.classList.toggle("hidden", !invoice)
    this.payeeInternationalTarget.classList.toggle("hidden", !international)
    this.ukPayeeCopyTarget.classList.toggle("hidden", international)
    this.internationalPayeeCopyTarget.classList.toggle("hidden", !international)
  }

  #isInternational() {
    return this.hasPaymentMethodTarget &&
      this.paymentMethodTarget.value === this.internationalMethodValue
  }

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
    // A fresh form must not resurrect a file from an abandoned earlier attempt.
    if (!this.resubmitValue) {
      stashedFiles = null
      return
    }
    if (!stashedFiles || this.filesTarget.files.length) return

    const data = new DataTransfer()
    for (const file of stashedFiles) data.items.add(file)
    this.filesTarget.files = data.files
    if (this.hasReattachNoticeTarget) this.reattachNoticeTarget.classList.add("hidden")
    this.statusTarget.textContent = "Kept the receipt you attached. Check the errors above and submit again."
  }

  checkAmount() {
    if (!this.hasLargeAmountWarningTarget || !this.hasAmountTarget) return
    const value = this.#parseAmount(this.amountTarget.value)
    const large = Number.isFinite(value) && value >= this.largeAmountThresholdValue
    this.largeAmountWarningTarget.classList.toggle("hidden", !large)
  }

  // Mirrors ExpenseForm#vat_missing?: both amounts present, and the ex-VAT one
  // not below the total.
  checkVat() {
    if (!this.hasVatWarningTarget || !this.hasAmountTarget || !this.hasAmountExclVatTarget) return
    const total = this.#parseAmount(this.amountTarget.value)
    const exclVat = this.#parseAmount(this.amountExclVatTarget.value)
    const missing = Number.isFinite(total) && Number.isFinite(exclVat) && exclVat >= total
    this.vatWarningTarget.classList.toggle("hidden", !missing)
  }

  // Mirrors ExpenseForm#parse_decimal: a trailing "," with 1-2 digits and no "."
  // is a decimal comma ("999,99" -> 999.99), otherwise commas are thousands
  // separators. Else 999,99 falsely trips the large-amount warning.
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
}
