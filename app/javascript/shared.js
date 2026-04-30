// Import jQuery setup first - this exposes jQuery globally before other plugins load
import './src/jquery-global'

import "./sweetalert"

// Use imports-loader to explicitly inject jQuery into slimscroll
require('imports-loader?imports=default|jquery|jQuery!jquery-slimscroll')

// Load all the stimulus controllers
import "./controllers"

import { Turbo } from "@hotwired/turbo-rails";
Turbo.session.drive = false;

require("@rails/activestorage").start()

