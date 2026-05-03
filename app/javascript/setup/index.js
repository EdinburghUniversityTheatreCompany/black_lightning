// Load all the stimulus controllers
import "../controllers"

// And other shared modules
import "../sweetalert"

import { Turbo } from "@hotwired/turbo-rails";

Turbo.config.forms.confirm = (message) => {
  return window.Swal.fire({
    icon: "warning",
    html: message,
    title: "Are you sure?",
    showCancelButton: true,
    confirmButtonText: "Yes",
    cancelButtonText: "Cancel",
    buttonsStyling: true,
  }).then(result => result.isConfirmed)
}

Turbo.StreamActions.toast = function () {
  window.Toast.fire({ icon: this.getAttribute("type"), html: this.getAttribute("message") })
}

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

