import { Controller } from "@hotwired/stimulus"

// Auto-generates a URL-friendly slug from a name field as the user types.
// Stops auto-generating once the user manually edits the slug field.
//
// Usage:
//   <div data-controller="slug-generator">
//     <input data-slug-generator-target="name"
//            data-action="input->slug-generator#nameChanged">
//     <input data-slug-generator-target="slug"
//            data-action="input->slug-generator#slugChanged">
//   </div>
export default class extends Controller {
  static targets = ["name", "slug"]
  static values = { manuallyEdited: Boolean }

  connect() {
    this.manuallyEditedValue = false
    // Initialize slug if name is populated and slug is empty (e.g. on edit page reload)
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
    // Detect manual editing: if slug differs from what the name would generate,
    // the user has taken control of the slug field.
    const generatedSlug = this.#generateSlug(this.nameTarget.value)
    const currentSlug = this.slugTarget.value

    if (currentSlug !== generatedSlug && currentSlug !== "") {
      this.manuallyEditedValue = true
    } else if (currentSlug === generatedSlug || currentSlug === "") {
      this.manuallyEditedValue = false
    }
  }

  // Private

  #updateSlug() {
    this.slugTarget.value = this.#generateSlug(this.nameTarget.value)
  }

  #generateSlug(text) {
    if (!text) return ""

    return text
      .toLowerCase()
      .trim()
      // Replace accented characters with basic equivalents
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      // Replace spaces and common punctuation with hyphens
      .replace(/[\s._]+/g, "-")
      // Remove any character that isn't alphanumeric or hyphen
      .replace(/[^a-z0-9-]/g, "")
      // Collapse consecutive hyphens
      .replace(/-{2,}/g, "-")
      // Trim leading/trailing hyphens
      .replace(/^-+|-+$/g, "")
  }
}
