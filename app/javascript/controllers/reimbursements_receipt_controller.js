import { Controller } from "@hotwired/stimulus"

// Receipt-first expense form: when files are picked, posts them to the
// extract endpoint and prefills the form fields from the AI's reading.
// Extraction failing (or JS being off) leaves a perfectly usable manual form.
export default class extends Controller {
  static targets = ["files", "status", "amount", "amountExclVat", "budget",
    "description", "reference", "referenceCounter", "vatItemised", "vatWarning"]
  static values = { extractUrl: String }

  connect() {
    this.updateCounter()
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
        headers: { "X-CSRF-Token": this.#csrfToken(), "Accept": "application/json" },
        body,
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const extraction = await response.json()
      if (!extraction.ok) throw new Error(extraction.error || "extraction failed")

      this.#fill(extraction)
      this.#setStatus("Prefilled from your receipt — please check everything before submitting.")
    } catch {
      this.#setStatus("Couldn't read the receipt automatically — please fill in the form manually.")
    }
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
  }

  #setValue(target, value) {
    if (value === null || value === undefined || value === "") return
    target.value = value
    target.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #setStatus(message) {
    this.statusTarget.textContent = message
  }

  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
