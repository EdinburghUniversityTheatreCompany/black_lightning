// This scripts adds a listener to all inputs on the page that watches for changes to the input field, and runs a validation on every change.
// It respects server-side validation errors and only takes over once the user interacts with the field.

// Add event listeners to all inputs on the page on load.
window.addEventListener('load', function () {
    // Mark fields that have server-side errors before adding validators
    markServerErrors(document);
    addEventListenersToInputs(document);
});

// Make sure event listeners are added for all inputs that are added dynamically.
$(document).on("cocoon:after-insert", function (e, insertedItem, originalEvent) {
    addEventListenersToInputs(insertedItem[0]);
});

// Mark all inputs that currently have server-side errors
function markServerErrors(element) {
    $(element).find('input.is-invalid').each(function () {
        // Mark this field as having a server error
        // Client validation will not override until user interacts with it
        this.setAttribute('data-server-error', 'true');
    });
}

// Add event listeners to all inputs in the passed element.
function addEventListenersToInputs(element) {
    $(element).find('input').each(function () {
        // Do not add validators if the input is marked as not needing validation.
        if ($(this).attr('nojsvalidation')) {
            return;
        };

        // Do not add validators if the input is in a search form.
        if ($(this).closest('form').hasClass('search-form')) {
            return;
        }

        this.addEventListener('input', function () {
            validateInput(this);
        });

        // Validate them immediately to show users which fields they need to fill out or change.
        // BUT: Skip fields with server errors - they'll be validated once user interacts
        if (!this.hasAttribute('data-server-error')) {
            validateInput(this);
        }
    });
};

// Validates the input, adding the is-valid class if it's valid and is-invalid if it's invalid.
export function validateInput(input) {
    // If field has a server error, clear it on first interaction and take over validation
    if (input.hasAttribute('data-server-error')) {
        input.removeAttribute('data-server-error');
    }

    if (input.checkValidity()) {
        input.classList.remove('is-invalid');
        input.classList.add('is-valid');
    } else {
        input.classList.remove('is-valid');
        input.classList.add('is-invalid');
    }
};