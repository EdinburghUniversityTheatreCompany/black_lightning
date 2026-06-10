import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["blueprint", "addButton"]

  #counter = 0

  addDate() {
    const newFields = this.blueprintTarget.cloneNode(true)
    newFields.style.display = "block"
    newFields.removeAttribute("data-staffing-date-fields-target")

    newFields.querySelector("#start_datetime").setAttribute("name", `start_times[${this.#counter}]`)
    newFields.querySelector("#end_time").setAttribute("name", `end_times[${this.#counter}]`)

    this.#counter++
    this.addButtonTarget.before(newFields)
  }

  removeDate(event) {
    event.preventDefault()
    event.currentTarget.closest(".control-group.datetime").remove()
  }
}
