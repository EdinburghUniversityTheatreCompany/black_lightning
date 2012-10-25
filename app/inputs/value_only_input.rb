class ValueOnlyInput < SimpleForm::Inputs::Base
  # This method usually returns input's html like <input ... />
  # but in this case it returns just a value of the attribute.
  def input
    @builder.object.send(attribute_name)
  end
end