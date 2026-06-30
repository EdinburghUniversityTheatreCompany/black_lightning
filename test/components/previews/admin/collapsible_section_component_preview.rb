# The admin and public previews of CollapsibleSectionComponent are identical;
# inherit the public preview's examples so they live in one place. The "admin"
# layout is applied by ComponentPreviewsController, not by the base class, so
# subclassing the public preview here keeps the admin rendering unchanged.
class Admin::CollapsibleSectionComponentPreview < CollapsibleSectionComponentPreview
end
