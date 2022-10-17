const { environment } = require('@rails/webpacker')


const webpack = require('webpack');

environment.plugins.prepend(
  'Provide',
  new webpack.ProvidePlugin({
    $: 'jquery',
    jQuery: 'jquery',
    Popper: ['popper.js', 'default']  // Not a typo, we're still using popper.js here
    // BOOTSTRAP CHECK: Should this be
    // Popper: ['@popperjs/core', 'default']
  })
)

environment.config.set('resolve.alias', {jquery: 'jquery/src/jquery'});

module.exports = environment
