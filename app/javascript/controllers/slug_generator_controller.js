import { Controller } from "@hotwired/stimulus"

// Fills the slug from the name as the user types, until they edit the slug.
export default class extends Controller {
  static targets = ["name", "slug"]

  #manuallyEdited = false

  connect() {
    this.#manuallyEdited = false
    if (this.slugTarget.value === "" && this.nameTarget.value !== "") {
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
