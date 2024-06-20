import jQuery from 'jquery';
global.$ = global.jQuery = jQuery;

import "./sweetalert"

import 'jquery-slimscroll'

import './src/shared/konami_code'
import './src/shared/md_editor'
import './src/shared/select2'
import './src/shared/input_validator'

// Load all the stimulus controllers
import "./controllers"

require("@rails/activestorage").start()

// Requires jQuery. There are vanilla js packages, but not as frequently maintained or downloaded.
require("@nathanvda/cocoon")
