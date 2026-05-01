// Import jQuery setup first - this exposes jQuery globally before other plugins load
import './jquery-global'

// Plugins that depend on global jQuery
import "jquery-slimscroll"

// Load all the stimulus controllers
import "../controllers"

// And other shared modules
import "../sweetalert"

import { Turbo } from "@hotwired/turbo-rails";
Turbo.session.drive = false;

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

