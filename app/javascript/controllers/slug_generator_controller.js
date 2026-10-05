import { Controller } from "@hotwired/stimulus"

// Fills the slug from the name as the user types, until they edit the slug.
export default class extends Controller {
  static targets = ["name", "slug"]
  static values = { manuallyEdited: Boolean }

  connect() {
    this.manuallyEditedValue = false
    if (this.slugTarget.value === "" && this.nameTarget.value !== "") {
      this.#updateSlug()
    }
  }

  nameChanged() {
    if (!this.manuallyEditedValue) {
      this.#updateSlug()
    }
  }

  slugChanged() {
    const generatedSlug = this.#generateSlug(this.nameTarget.value)
    const currentSlug = this.slugTarget.value

    if (currentSlug !== generatedSlug && currentSlug !== "") {
      this.manuallyEditedValue = true
    } else if (currentSlug === generatedSlug || currentSlug === "") {
      this.manuallyEditedValue = false
    }
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
