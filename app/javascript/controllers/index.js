import { application } from "./application"
import { definitionsFromContext } from "@hotwired/stimulus-webpack-helpers"

// Auto-discover local controllers from the controllers folder
const context = require.context(".", true, /_controller\.js$/)
application.load(definitionsFromContext(context))

// Register external Stimulus component libraries
import NestedForm from "stimulus-rails-nested-form"
application.register("nested-form", NestedForm)
