
# Black Lightning - Claude Code Guidelines


## Packages
Ruby on Rails 8.1 

Use yarn for package management rather than npm or bun.

The public facing website uses Bootstrap 5. The admin website currently uses Bootstrap 4.3 with AdminLTE but the plan is to migrate away.

Use stimulus for all JavaScript sprinkles. We remain on jsbundling rather than importmaps

## Maintain Documentation

If you learn something about the project that would be useful context for other agents looking at the codebase, add it to this file at the end of your to do list.

## URL as state
Always maintain the URL as state with readable parameters where possible for GET actions.

## Link Helper

Always use the link helper for links, including external and non-model links. this keeps styling consistent

**Use `get_link` from `LinkHelper` for button-style links to model resources.**

The `get_link` helper provides:
- Consistent Bootstrap styling based on action type
- Automatic CanCanCan permission checking
- Automatic path generation for model resources

### Usage Examples

```erb
<%# For model class actions (index, new) - pass the Class %>
<%= get_link(User, :index, link_text: "Back to Users") %>
<%= get_link(User, :new) %>
<%= get_link(Admin::Questionnaires::Questionnaire, :new) %>

<%# For model instance actions (show, edit, destroy) - pass the instance %>
<%= get_link(@user, :edit) %>
<%= get_link(@user, :destroy) %>
<%= get_link(@user, :show) %>

<%# With custom options %>
<%= get_link(@user, :show, link_text: "View Profile", html_class: "btn btn-lg btn-primary") %>

<%# With custom link target (for nested routes or non-standard paths) %>
<%= get_link(Admin::Feedback, :new, link_text: "Submit Feedback", link_target: new_admin_show_feedback_path(@show)) %>
```

### When to use plain `link_to`


```erb
<%# Non-model controller - use link_to with explicit path and class %>
<%= link_to "Bulk Membership Import", new_admin_membership_import_path, class: "btn btn-primary" %>
<%= link_to "Cancel", new_admin_membership_import_path, class: "btn btn-secondary" %>
```

# Testing
Start the test database using `docker start /mysql8` before running any tests.