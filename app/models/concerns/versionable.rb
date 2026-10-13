# Version diffs and author notes for a has_paper_trail model.
module Versionable
  extend ActiveSupport::Concern

  included do
    attr_accessor :version_note
  end

  # { attribute => [old, new] } for a version. Its `object` is the state BEFORE the change, so the
  # state after is the next version's `object`, or the live record for the latest version.
  def diff_for_version(version)
    old_attributes = deserialize_version_object(version.object)
    return {} if old_attributes.blank?

    next_version = version.next
    new_attributes = if next_version
      deserialize_version_object(next_version.object)
    else
      attributes
    end

    return {} if new_attributes.blank?

    changes = {}
    skip_attributes = %w[id created_at updated_at]

    (old_attributes.keys | new_attributes.keys).each do |key|
      next if skip_attributes.include?(key)

      old_val = old_attributes[key].to_s
      new_val = new_attributes[key].to_s

      changes[key] = [ old_val, new_val ] if old_val != new_val
    end

    changes
  end

  private

  def deserialize_version_object(object_yaml)
    return {} if object_yaml.blank?

    YAML.safe_load(
      object_yaml,
      permitted_classes: [ Time, ActiveSupport::TimeWithZone, BigDecimal, Date, Symbol ]
    ) || {}
  end
end
