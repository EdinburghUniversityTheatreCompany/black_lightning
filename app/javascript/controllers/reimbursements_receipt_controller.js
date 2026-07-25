import { Controller } from "@hotwired/stimulus"
import { getMetaValue } from "../helpers"

// A file input can't be re-populated from markup after a failed submit, so a
// server 422 re-render would lose the receipt the user picked. Hold it in JS
// instead — module scope survives Turbo's body swap on a 422 render — and
// restore it via DataTransfer (the one browser-sanctioned way to set
// input.files). Cleared on a successful submit or a fresh (non-resubmit) form.
let stashedFiles = null

// Which fields the producer has hand-edited, by input name. Module scope for
// the same reason as stashedFiles: it must survive Turbo's 422 body swap, or
// re-extraction after a failed submit would re-clobber the values the user
// already corrected. Reset on a fresh (non-resubmit) form.
const editedFieldNames = new Set()

// Receipt-first expense form. Reading a receipt is opt-in: picking a file
// reveals a consent choice, and only selecting "self" or "invoice" posts the
// file to the extract endpoint to prefill the form. "No" (or JS being off)
// leaves a perfectly usable manual form and sends nothing to Gemini.
export default class extends Controller {
  static targets = ["files", "status", "amount", "amountExclVat", "budget",
    "description", "reference", "referenceCounter", "vatItemised", "vatWarning",
    "reattachNotice", "largeAmountWarning", "consent", "consentOption",
    "payeeName", "sortCode", "accountNumber"]
  static values = { extractUrl: String, resubmit: Boolean, largeAmountThreshold: { type: Number, default: 1000 } }

  connect() {
    this.updateCounter()
    this.#trackUserEdits()
    this.#restoreOrClearStash()
    this.#refreshConsentVisibility()
  }

  // Remember which fields the producer has typed into (by input name), so
  // re-running extraction — they added a second receipt after correcting a
  // field — never clobbers their work, including across a 422 re-render. A real
  // edit fires input (text) or change (select); our own prefill sets .value
  // directly under the #fill isPrefilling guard, so those writes are ignored.
  // vat_itemised is a hidden field driven only by extraction, so it isn't
  // tracked — it always refreshes from the latest reading.
  #trackUserEdits() {
    const fields = [this.amountTarget, this.amountExclVatTarget, this.descriptionTarget,
      this.referenceTarget, this.budgetTarget]
    if (this.hasPayeeNameTarget) fields.push(this.payeeNameTarget)
    if (this.hasSortCodeTarget) fields.push(this.sortCodeTarget)
    if (this.hasAccountNumberTarget) fields.push(this.accountNumberTarget)
    for (const field of fields) {
      const mark = () => { if (!this.isPrefilling) editedFieldNames.add(field.name) }
      field.addEventListener("input", mark)
      field.addEventListener("change", mark)
    }
  }

  // Keep a reference to the picked files so a failed submit doesn't lose them.
  stash() {
    if (this.hasFilesTarget && this.filesTarget.files.length) {
      stashedFiles = this.filesTarget.files
    }
  }

  // A new file was picked (or cleared): reveal (or hide) the consent choice and
  // clear any earlier pick, so the submitter consciously re-consents for the
  // new receipt before anything is sent to Gemini.
  fileChanged() {
    this.#clearConsent()
    this.#refreshConsentVisibility()
  }

  // The submitter picked a scan option. "self"/"invoice" trigger the opt-in
  // upload (in the chosen mode); "no" sends nothing at all. "Now or later" is a
  // promise the server keeps: the answer is saved with the claim, and the finance
  // AI check refuses to run without it (there is no override).
  consentChanged(event) {
    const mode = event.target.value
    if (mode === "self" || mode === "invoice") {
      this.#runExtract(mode)
    } else {
      this.#setStatus("No problem, nothing will be sent to Google, now or later. " +
        "Fill in the details below yourself.")
    }
  }

  // Show the consent choice only once a receipt is attached; hide it otherwise.
  #refreshConsentVisibility() {
    if (!this.hasConsentTarget || !this.hasFilesTarget) return
    const hasFile = this.filesTarget.files.length > 0
    this.consentTarget.classList.toggle("hidden", !hasFile)
  }

  #clearConsent() {
    if (!this.hasConsentOptionTarget) return
    for (const option of this.consentOptionTargets) option.checked = false
  }

  submitEnd(event) {
    if (event.detail?.success) stashedFiles = null
  }

  #restoreOrClearStash() {
    if (!this.hasFilesTarget) return
    // A fresh form (not a re-render after a validation error) should start
    // clean — don't resurrect a file or edited-field memory from an abandoned
    // earlier attempt.
    if (!this.resubmitValue) {
      stashedFiles = null
      editedFieldNames.clear()
      return
    }
    if (!stashedFiles || this.filesTarget.files.length) return

    const data = new DataTransfer()
    for (const file of stashedFiles) data.items.add(file)
    this.filesTarget.files = data.files
    // The file survived, so the "please re-attach" fallback no longer applies.
    if (this.hasReattachNoticeTarget) this.reattachNoticeTarget.classList.add("hidden")
    // A file is present again, so offer the consent choice for it once more.
    this.#refreshConsentVisibility()
    this.#setStatus("Kept the receipt you attached. Check the errors above and submit again.")
  }

  // Opt-in scan, invoked from the consent radios. mode is "self" (reimburse the
  // submitter) or "invoice" (also prefill the payee bank details printed on the
  // invoice). Failure just leaves the manual form usable — never a blocker.
  async #runExtract(mode) {
    const files = this.filesTarget.files
    if (!files.length) return

    this.#setStatus("Reading your receipt…")
    const body = new FormData()
    for (const file of files) body.append("receipts[]", file)
    body.append("mode", mode)

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
    // Guard so the change events our own writes emit aren't mistaken for edits;
    // try/finally so a mid-fill throw can't strand the flag true and silently
    // stop tracking every later edit.
    this.isPrefilling = true
    try {
      this.#setValue(this.amountTarget, extraction.total_amount)
      this.#setValue(this.amountExclVatTarget, extraction.amount_excl_vat)
      this.#setValue(this.descriptionTarget, extraction.suggested_description)
      this.#setValue(this.referenceTarget, extraction.suggested_payment_reference)
      if (extraction.suggested_budget_record_id && !editedFieldNames.has(this.budgetTarget.name)) {
        this.budgetTarget.value = extraction.suggested_budget_record_id
      }
      // Invoice-mode only: prefill the third-party payee trio from the bank
      // details printed on the invoice. Absent in self mode (the keys aren't
      // even in the JSON), so #setValue no-ops there.
      if (this.hasPayeeNameTarget) this.#setValue(this.payeeNameTarget, extraction.payee_name)
      if (this.hasSortCodeTarget) this.#setValue(this.sortCodeTarget, extraction.sort_code)
      if (this.hasAccountNumberTarget) this.#setValue(this.accountNumberTarget, extraction.account_number)
      // vat_itemised is derived from the receipt (a hidden field, never typed),
      // so always refresh it and its soft-block warning from the latest reading.
      this.vatItemisedTarget.value = String(extraction.vat_itemised)
      this.vatWarningTarget.classList.toggle("hidden", extraction.vat_itemised !== false)
    } finally {
      this.isPrefilling = false
    }
    this.updateCounter()
    this.checkAmount()
  }

  // Skip a field the producer has already corrected — re-extraction must never
  // clobber their input.
  #setValue(target, value) {
    if (value === null || value === undefined || value === "") return
    if (editedFieldNames.has(target.name)) return
    target.value = value
    target.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #setStatus(message) {
    this.statusTarget.textContent = message
  }
}
