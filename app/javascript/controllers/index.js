import { application } from "./application"

const controllers = import.meta.glob("./**/*_controller.js", { eager: true })

for (const path in controllers) {
    const controller = controllers[path]

    const identifier = path
        .replace("./", "")
        .replace("_controller.js", "")
        .replace(/\//g, "--")
        .replace(/_/g, "-")

    application.register(identifier, controller.default)
}
// External controllers
import NestedForm from "stimulus-rails-nested-form"
application.register("nested-form", NestedForm)
