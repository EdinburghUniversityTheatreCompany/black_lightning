const { environment } = require('@rails/webpacker')


const webpack = require('webpack');

environment.plugins.prepend(
  'Provide',
  new webpack.ProvidePlugin({
    $: 'jquery',
    jQuery: 'jquery'
  })
)

environment.config.set('resolve.alias', {jquery: 'jquery/src/jquery'});

module.exports = environment
