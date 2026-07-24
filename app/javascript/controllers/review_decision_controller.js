import { Controller } from "@hotwired/stimulus"

// Guards a finance review card's Approve/Reject/override decision against
// silently dropping unsaved edits.
//
// The card's Save form is a SEPARATE <form> from each decision form, so hitting
// Approve or Reject used to submit the decision without the edits typed into the
// Save form. This controller snapshots the Save form on connect; when a decision
// button is clicked with the form dirty, it intercepts and opens a <dialog> with
// three choices (Cancel / Save Changes / Discard Changes). A pristine form is
// left alone, so any existing turbo-confirm on the decision form still fires.
//
// Progressive enhancement: with JS off, none of this runs and the buttons keep
// their server default (approve/reject without saving) — the server also accepts
// the edits + a save_changes flag in one request when "Save Changes" is chosen,
// so a save that fails validation aborts the decision server-side.
//
// Every save/decision here triggers a full navigation (the server redirects), so
// the snapshot is always fresh on the next connect; no in-page re-snapshot after
// a save is needed.
const SKIP_FIELDS = new Set(["_method", "authenticity_token", "utf8"])

export default class extends Controller {
  static targets = ["editForm", "dialog", "title"]

  #pendingForm = null

  connect() {
    this.#snapshot = this.#serialize()
  }

  // Click handler on each decision submit control. Pristine form -> let the
  // click submit as usual (and any turbo-confirm run). Dirty -> stop the submit
  // and open the dialog, remembering which form to run afterwards.
  guard(event) {
    if (!this.hasEditFormTarget || !this.#dirty) return

    event.preventDefault()
    this.#pendingForm = event.currentTarget.form
    if (this.hasTitleTarget) {
      const verb = event.currentTarget.dataset.decisionVerb || "continuing"
      this.titleTarget.textContent = `Do you want to save the changes before ${verb}?`
    }
    this.dialogTarget.showModal()
  }

  // Cancel: close the dialog and stay on the page with the edits intact.
  cancel() {
    this.dialogTarget.close()
    this.#pendingForm = null
  }

  // Clicking the backdrop (the dialog element itself, outside its content box)
  // is treated as Cancel.
  backdropClose({ target }) {
    if (target === this.dialogTarget) this.cancel()
  }

  // Save Changes: carry the Save form's fields (plus a save_changes flag) into
  // the decision form and submit it, so the server saves then decides in one
  // request.
  saveThenDecide() {
    if (!this.#pendingForm) return

    this.#injectEditFields(this.#pendingForm)
    this.#submitPending()
  }

  // Discard Changes: run the decision as-is, without the unsaved edits.
  discardThenDecide() {
    this.#submitPending()
  }

  #submitPending() {
    const form = this.#pendingForm
    this.#pendingForm = null
    this.dialogTarget.close()
    // requestSubmit fires a submit event (not a click), so it bypasses #guard
    // and lets any turbo-confirm on the decision form still run.
    form.requestSubmit()
  }

  #injectEditFields(form) {
    form.querySelectorAll("[data-injected-edit]").forEach((el) => el.remove())
    for (const [name, value] of new FormData(this.editFormTarget).entries()) {
      if (SKIP_FIELDS.has(name)) continue
      form.appendChild(this.#hiddenInput(name, value))
    }
    form.appendChild(this.#hiddenInput("save_changes", "1"))
  }

  #hiddenInput(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    input.dataset.injectedEdit = ""
    return input
  }

  get #dirty() {
    return this.#serialize() !== this.#snapshot
  }

  #serialize() {
    const parts = []
    for (const [name, value] of new FormData(this.editFormTarget).entries()) {
      if (SKIP_FIELDS.has(name)) continue
      parts.push(`${name}=${value}`)
    }
    return parts.join("&")
  }

  #snapshot = ""
}
