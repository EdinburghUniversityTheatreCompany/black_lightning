jQuery(function () {
  var slugWasManuallyEdited = false;
  var nameField = $('#event_name');
  var slugField = $('#event_slug');

  function generateSlug(text) {
    if (!text) return '';

    return text
      .toLowerCase()
      .trim()
      // Replace accented characters with basic equivalents
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      // Replace spaces and common punctuation with hyphens
      .replace(/[\s\._]+/g, '-')
      // Remove any character that isn't alphanumeric or hyphen
      .replace(/[^a-z0-9\-]/g, '')
      // Remove consecutive hyphens
      .replace(/\-{2,}/g, '-')
      // Remove leading and trailing hyphens
      .replace(/^-+|-+$/g, '');
  }

  function updateSlugFromName() {
    if (!slugWasManuallyEdited && nameField.length && slugField.length) {
      var newSlug = generateSlug(nameField.val());
      slugField.val(newSlug);
    }
  }

  // Track manual editing of slug field
  slugField.on('input keyup change', function () {
    var currentNameSlug = generateSlug(nameField.val());
    var currentSlugValue = slugField.val();

    // If the current slug doesn't match what would be auto-generated from the name,
    // then it was manually edited
    if (currentSlugValue !== currentNameSlug && currentSlugValue !== '') {
      slugWasManuallyEdited = true;
    } else if (currentSlugValue === currentNameSlug || currentSlugValue === '') {
      slugWasManuallyEdited = false;
    }
  });

  // Update slug when name changes
  nameField.on('input keyup change', updateSlugFromName);

  console.log('name_to_slug.js loaded');
  console.log(nameField.val());
  console.log(slugField.val());

  // Initialize on page load if slug is empty
  if (slugField.val() === '' && nameField.val() !== '') {
    console.log('initializing on page load');
    updateSlugFromName();
  }
});