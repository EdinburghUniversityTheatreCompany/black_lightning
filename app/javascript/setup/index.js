import "../controllers"

import "../sweetalert"

import { Turbo } from "@hotwired/turbo-rails";
import { confirmDialog } from "../lib/confirm"

Turbo.config.forms.confirm = confirmDialog

// The message is text unless the stream opts in with an `html` attribute: names and titles
// are interpolated into it, and getAttribute hands back the entity-decoded string.
Turbo.StreamActions.toast = function () {
  const message = this.getAttribute("message")
  window.Toast.fire({
    icon: this.getAttribute("type"),
    ...(this.hasAttribute("html") ? { html: message } : { text: message }),
  })
}

Turbo.StreamActions.dismissMergeModal = function () {
  const dialog = document.getElementById("merge-modal-dialog")
  if (dialog?.open) dialog.close()
}

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

