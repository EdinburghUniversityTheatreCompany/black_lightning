const { environment } = require('@rails/webpacker')


const webpack = require('webpack');

environment.plugins.prepend(
  'Provide',
  new webpack.ProvidePlugin({
    $: 'jquery',
    jQuery: 'jquery',
    Popper: ['popper.js', 'default']  
    // Not a typo, we're still using popper.js here because that is what adminlte requires.
    // BOOTSTRAP 5: Replace with the below once upgrading adminlte
    // Popper: ['@popperjs/core', 'default']
  })
)

environment.config.set('resolve.alias', {jquery: 'jquery/src/jquery'});

module.exports = environment
