$(function () {
    var counter = 0;

    $('#add_date').click(function () {
        // Clone the blueprint, show it, and remove the blueprint id.
        var new_date_fields = $('#date_blueprint').clone();
        $(new_date_fields).show();
        $(new_date_fields).removeAttr('id');

        // Rename the newly-added item so the params are formatted correctly.
        new_date_fields.find('#start_datetime').attr('name', 'start_times[' + counter + ']');
        new_date_fields.find('#end_time').attr('name', 'end_times[' + counter + ']');

        // Remove the current row if clicked.
        new_date_fields.find('a').click(function () {
            $(new_date_fields).remove();
        });
        // Add one to the counter for the ids
        counter++;

        // Add the newly-generated item right before the add_date button.
        $('#add_date').before(new_date_fields);
    });
});
