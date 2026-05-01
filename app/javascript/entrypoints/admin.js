import "../setup"

import 'popper.js'

// The customisations are just two lines: https://www.diffchecker.com/LT8Mt2Hd/
// Line 1855: $preloader.css('height', 0); -> $preloader.css('opacity', 0);
// Between line 1857 and 1858, insert: $preloader.hide(); // Also hide the preloader itself, and not just the children.
import '../vendor/adminlte.customised.js'

// This is a Bootstrap 4 install, which is still needed for adminlte. Once you upgrade to Bootstrap 5, remove it, and just load Bootstrap 5 in shared.
import '../vendor/bootstrap.bundle.min.js'

import 'moment'
