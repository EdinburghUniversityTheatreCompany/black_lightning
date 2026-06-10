import { Controller } from "@hotwired/stimulus"

// Suggests a Department for an opportunity role from its position text, unless the user has
// already chosen one. Reads the departments + their match terms (embedded as a JSON value) and
// sets the department tom-select silently so the suggestion doesn't count as a manual choice.
export default class extends Controller {
  static targets = ["position", "department"]
  static values = { departments: Array }

  connect() {
    // Respect a pre-filled department (e.g. when editing an existing role).
    this.userChosen = this.#hasValue()
  }

  positionChanged() {
    if (this.userChosen) return

    const text = this.positionTarget.value.toLowerCase()
    if (!text) return

    const match = this.departmentsValue.find(
      (department) => department.terms.some((term) => term && text.includes(term))
    )
    if (match) this.#setDepartment(match.name)
  }

  departmentChanged() {
    // Programmatic changes below are silent, so reaching here means the user picked something.
    this.userChosen = this.#hasValue()
  }

  #hasValue() {
    return Boolean(this.departmentTarget.value)
  }

  #setDepartment(name) {
    const select = this.departmentTarget
    if (select.tomselect) {
      // silent = true: doesn't fire change, so it isn't treated as a manual choice.
      select.tomselect.setValue(name, true)
    } else {
      select.value = name
    }
  }
}
