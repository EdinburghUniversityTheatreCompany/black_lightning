import { application } from "./application"
import { registerControllers } from "stimulus-vite-helpers"

registerControllers(application, import.meta.glob("./**/*_controller.js", { eager: true }))

// External controllers
import NestedForm from "stimulus-rails-nested-form"
application.register("nested-form", NestedForm)
