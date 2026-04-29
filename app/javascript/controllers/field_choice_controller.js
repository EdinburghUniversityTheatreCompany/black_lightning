import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const radio = event.target
    const fieldKey = radio.name.match(/\[(.+)\]/)[1]
    const hiddenField = document.getElementById("hidden_" + fieldKey)

    if (radio.value === "source") {
      if (!hiddenField) {
        const hidden = document.createElement("input")
        hidden.type = "hidden"
        hidden.name = "keep_from_source[]"
        hidden.value = fieldKey
        hidden.id = "hidden_" + fieldKey
        radio.parentNode.appendChild(hidden)
      }
    } else {
      if (hiddenField) {
        hiddenField.remove()
      }
    }
  }
}
