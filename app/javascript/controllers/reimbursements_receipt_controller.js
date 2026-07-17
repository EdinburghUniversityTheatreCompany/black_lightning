import { Controller } from "@hotwired/stimulus"
import { getMetaValue } from "../helpers"

// A file input can't be re-populated from markup after a failed submit, so a
// server 422 re-render would lose the receipt the user picked. Hold it in JS
// instead — module scope survives Turbo's body swap on a 422 render — and
// restore it via DataTransfer (the one browser-sanctioned way to set
// input.files). Cleared on a successful submit or a fresh (non-resubmit) form.
let stashedFiles = null

// Receipt-first expense form: when files are picked, posts them to the
// extract endpoint and prefills the form fields from the AI's reading.
// Extraction failing (or JS being off) leaves a perfectly usable manual form.
export default class extends Controller {
  static targets = ["files", "status", "amount", "amountExclVat", "budget",
    "description", "reference", "referenceCounter", "vatItemised", "vatWarning",
    "reattachNotice", "largeAmountWarning"]
  static values = { extractUrl: String, resubmit: Boolean, largeAmountThreshold: { type: Number, default: 1000 } }

  connect() {
    this.updateCounter()
    this.#restoreOrClearStash()
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
    this.#setStatus("Kept the receipt you attached — check the errors above and submit again.")
  }

  async extract() {
    const files = this.filesTarget.files
    if (!files.length) return

    this.#setStatus("Reading your receipt…")
    const body = new FormData()
    for (const file of files) body.append("receipts[]", file)

    try {
      const response = await fetch(this.extractUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": getMetaValue("csrf-token"), "Accept": "application/json" },
        body,
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const extraction = await response.json()
      if (!extraction.ok) throw new Error(extraction.error || "extraction failed")

      this.#fill(extraction)
      this.#setStatus("Prefilled from your receipt. Please check everything before submitting.")
    } catch {
      this.#setStatus("We couldn't read the receipt automatically, so please fill in the form yourself.")
    }
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

  #fill(extraction) {
    this.#setValue(this.amountTarget, extraction.total_amount)
    this.#setValue(this.amountExclVatTarget, extraction.amount_excl_vat)
    this.#setValue(this.descriptionTarget, extraction.suggested_description)
    this.#setValue(this.referenceTarget, extraction.suggested_payment_reference)
    if (extraction.suggested_budget_record_id) {
      this.budgetTarget.value = extraction.suggested_budget_record_id
    }
    this.vatItemisedTarget.value = String(extraction.vat_itemised)
    this.vatWarningTarget.classList.toggle("hidden", extraction.vat_itemised !== false)
    this.updateCounter()
    this.checkAmount()
  }

  #setValue(target, value) {
    if (value === null || value === undefined || value === "") return
    target.value = value
    target.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #setStatus(message) {
    this.statusTarget.textContent = message
  }
}
