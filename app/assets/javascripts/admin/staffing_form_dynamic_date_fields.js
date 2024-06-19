document.addEventListener('DOMContentLoaded', function() {
    var counter = 0;
    var addDateButton = document.getElementById('add_date');
    var dateBlueprint = document.getElementById('date_blueprint');
  
    addDateButton.addEventListener('click', function() {
      // Clone the blueprint, show it, and remove the blueprint id.
      var newDateFields = dateBlueprint.cloneNode(true);
      newDateFields.style.display = 'block';
      newDateFields.removeAttribute('id');
  
      // Rename the newly-added item so the parameters are formatted correctly.
      var startDatetime = newDateFields.querySelector('#start_datetime');
      startDatetime.setAttribute('name', 'start_times[' + counter + ']');
  
      var endTime = newDateFields.querySelector('#end_time');
      endTime.setAttribute('name', 'end_times[' + counter + ']');
  
      // Remove the current row if clicked.
      var removeButton = newDateFields.querySelector('a');
      removeButton.addEventListener('click', function() {
        newDateFields.remove();
      });
  
      // Add one to the counter for the ids
      counter++;
  
      // Add the newly-generated item right before the add_date button.
      addDateButton.parentNode.insertBefore(newDateFields, addDateButton);
    });
  });