// Import jQuery setup first - this exposes jQuery globally before other plugins load
import './src/jquery-global'

require("@popperjs/core")

import "bootstrap"

import "./sweetalert"

// Use imports-loader to explicitly inject jQuery into slimscroll
require('imports-loader?imports=default|jquery|jQuery!jquery-slimscroll')

import './src/shared/konami_code'
import './src/shared/md_editor'
import './src/shared/select2'
import './src/shared/input_validator'

// Load all the stimulus controllers
import "./controllers"

import Rails from '@rails/ujs';
Rails.start();

require("@rails/activestorage").start()

// Requires jQuery. There are vanilla js packages, but not as frequently maintained or downloaded.
require("@nathanvda/cocoon")
