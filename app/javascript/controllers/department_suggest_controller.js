import { Controller } from "@hotwired/stimulus"

// Suggests an opportunity role's Department from its position text, until the
// user picks one.
export default class extends Controller {
  static targets = ["position", "department"]
  static values = { departments: Array }

  connect() {
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
    // #setDepartment is silent, so only the user's own pick lands here.
    this.userChosen = this.#hasValue()
  }

  #hasValue() {
    return Boolean(this.departmentTarget.value)
  }

  #setDepartment(name) {
    const select = this.departmentTarget
    if (select.tomselect) {
      // Silent: a suggestion must not count as a manual choice.
      select.tomselect.setValue(name, true)
    } else {
      select.value = name
    }
  }
}
