// This file must be imported first to expose jQuery globally before other plugins load.
import jQuery from 'jquery';

// Expose jQuery in all the ways plugins might look for it
window.$ = window.jQuery = jQuery;
if (typeof globalThis !== 'undefined') {
  globalThis.$ = globalThis.jQuery = jQuery;
}
