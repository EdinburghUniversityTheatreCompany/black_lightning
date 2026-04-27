import { application } from "./application"

// Auto-discover local controllers from the controllers folder
const context = require.context(".", true, /.*_controller\.js$/)
context.keys().forEach(key => {
  const matches = key.match(/\.\/(.+)_controller\.js$/)
  if (matches) {
    const controllerName = matches[1].replace(/\//g, "--")
    const controllerModule = context(key)
    application.register(controllerName, controllerModule.default)
  }
})

// Register external Stimulus component libraries for nested forms
import NestedForm from "stimulus-rails-nested-form"
application.register("nested-form", NestedForm)
