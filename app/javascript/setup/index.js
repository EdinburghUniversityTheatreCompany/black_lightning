import "../controllers"

import "../sweetalert"

import { Turbo } from "@hotwired/turbo-rails";
import { confirmDialog } from "../lib/confirm"

Turbo.config.forms.confirm = confirmDialog

Turbo.StreamActions.toast = function () {
  window.Toast.fire({ icon: this.getAttribute("type"), html: this.getAttribute("message") })
}

Turbo.StreamActions.dismissMergeModal = function () {
  const dialog = document.getElementById("merge-modal-dialog")
  if (dialog?.open) dialog.close()
}

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

