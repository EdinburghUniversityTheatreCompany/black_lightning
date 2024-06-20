const path    = require("path")
const webpack = require("webpack")

const mode = process.env.NODE_ENV === 'development' ? 'development' : 'production';

module.exports = {
  mode,
  optimization: {
    moduleIds: 'deterministic',
  },
  entry: {
    application: "./app/javascript/application.js",
    admin: "./app/javascript/admin.js",
    shared: "./app/javascript/shared.js"
  },
  output: {
    filename: "[name].js",
    sourceMapFilename: "[file].map",
    chunkFormat: "module",
    path: path.resolve(__dirname, "app/assets/builds"),
  },
  plugins: [
    new webpack.optimize.LimitChunkCountPlugin({
      maxChunks: 1
    }),
    new webpack.ProvidePlugin({
      $: 'jquery',
      jQuery: 'jquery',
      Popper: ['popper.js', 'default']  
      // Not a typo, we're still using popper.js here because that is what adminlte requires.
      // BOOTSTRAP 5: Replace with the below once upgrading adminlte
      // Popper: ['@popperjs/core', 'default']
    })
  ]
}

//TODO
/*
const { environment } = require('@rails/webpacker')

environment.plugins.prepend(
)

environment.config.set('resolve.alias', {jquery: 'jquery/src/jquery'});

module.exports = environment*/

// TODO: Maybe need to setup babel?
