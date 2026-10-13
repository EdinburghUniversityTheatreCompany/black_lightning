import { Controller } from "@hotwired/stimulus"

// Fills the slug from the name as the user types, until they edit the slug.
// A saved record's slug is its URL, so renaming one leaves it alone.
export default class extends Controller {
  static targets = ["name", "slug"]
  static values = { persisted: Boolean }

  #manuallyEdited = false

  connect() {
    // An unsaved record re-rendered after a failed save keeps following its name.
    const slug = this.slugTarget.value
    this.#manuallyEdited = slug !== "" &&
      (this.persistedValue || slug !== this.#generateSlug(this.nameTarget.value))
    if (!this.#manuallyEdited && this.nameTarget.value !== "") {
      this.#updateSlug()
    }
  }

  nameChanged() {
    if (!this.#manuallyEdited) {
      this.#updateSlug()
    }
  }

  slugChanged() {
    const slug = this.slugTarget.value
    this.#manuallyEdited = slug !== "" && slug !== this.#generateSlug(this.nameTarget.value)
  }

  #updateSlug() {
    this.slugTarget.value = this.#generateSlug(this.nameTarget.value)
  }

  #generateSlug(text) {
    if (!text) return ""

    return text
      .toLowerCase()
      .trim()
      // NFD splits off accents as combining marks, which this drops
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[\s._]+/g, "-")
      .replace(/[^a-z0-9-]/g, "")
      .replace(/-{2,}/g, "-")
      .replace(/^-+|-+$/g, "")
  }
}
