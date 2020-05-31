#
# This script looks for all fields called user_name on the page, so be careful when including it.
#

users = []
user_names = []
user_ids = {}

fetchUsers = ->
  loader =  $("""
              <span style="position: fixed; right: 0px; bottom: 0px; background: #fff; border: 1px solid #000; border-radius: 5px; padding: 10px;">
                Loading users list...
              </span>
              """).hide()
  $("body").append(loader)
  loader.fadeIn();

  base_url = "/admin/users/autocomplete_list.json"

  all_users_meta = $('meta[name="all-users"]')

  if all_users_meta.length
    all_users = all_users_meta.attr("content");
    url = base_url + "?all_users=" + all_users
  else
    url = base_url

  $.getJSON(url, null, (data) ->
    users = data

    updateUserNames()

    loader.fadeOut()

    return
  )

updateUserNames = ->
  $.each users, (i, user) ->
    user_name = "#{user.first_name} #{user.last_name}"

    user_names.push user_name
    user_ids[user_name] = user.id

  return

userUpdater = (item) ->
  # Update user id
  this.$element.parent().find('.user_id').val(user_ids[item])

  return item

addUserAutocomplete = ->
  $('.user_name').typeahead
    source:  user_names
    updater: userUpdater
  .change ->
    $container = $(this).parent()
    value = $(this).val()
    if user_names.indexOf(value) == -1
      $container.find('.user_id').val(null)

      return if value == ""

      $container.find('.no-such-user').slideDown()
      $container.addClass('error')
    else
      $container.find('.no-such-user').slideUp()
      $container.removeClass('error')

  return

jQuery ->
  return if $('[name="autocomplete_users_list"]').length == 0

  fetchUsers()

  addUserAutocomplete()
  return

$(document).on "nested:fieldAdded", (event) ->
  addUserAutocomplete()
  return