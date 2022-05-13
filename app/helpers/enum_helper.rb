module EnumHelper
  def enum_options_for_select(klass, attribute, instance = nil)
    enum_hash = klass.try!(attribute.pluralize)

    return options_for_select(enum_hash.map { |key, value| [key.titleize, enum_hash.key(value)] }, instance)
  end

  def enum_collection(klass, attribute)
    enum_hash = klass.try!(attribute.pluralize)

    return enum_hash.map { |key, _value| [key.titleize, key] }
  end
end
