// Import jQuery setup first - this exposes jQuery globally before other plugins load
// (needed by the old admin.js/login stack; can be removed once login is migrated)
import './jquery-global'

// Load all the stimulus controllers
import "../controllers"

// And other shared modules
import "../sweetalert"

import { Turbo } from "@hotwired/turbo-rails";
Turbo.session.drive = false;

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

