# frozen_string_literal: true

# Parsing, caching and user creation shared by the bulk import controllers.
module Importable
  extend ActiveSupport::Concern

  private

  def parse_import_params
    data = params[:paste_data].presence || params[:xlsx_file]
    input_type = params[:paste_data].present? ? :paste : :xlsx
    [ data, input_type ]
  end

  # Stores ids rather than records, which the cache cannot serialise.
  def serialize_import(categorized)
    categorized.transform_values do |items|
      items.map do |item|
        serialized = {
          "row" => item[:row],
          "index" => item[:index]
        }

        # Fuzzy match buckets store multiple candidates
        if item[:existing_users]
          serialized["existing_user_ids"] = item[:existing_users].map(&:id)
        else
          serialized["existing_user_id"] = item[:existing_user]&.id
        end

        serialized
      end
    end
  end

  def read_and_clear_cache(cache_key)
    return nil if cache_key.blank?

    data = Rails.cache.read(cache_key)
    Rails.cache.delete(cache_key) if data.present?
    data
  end

  def generate_import_cache_key(prefix)
    "#{prefix}_#{SecureRandom.uuid}"
  end

  def write_import_cache(cache_key, data)
    Rails.cache.write(cache_key, data.with_indifferent_access, expires_in: 1.hour)
  end

  def generate_placeholder_email
    "unknown_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk"
  end

  def create_user_from_row(row)
    email = row[:email].presence || generate_placeholder_email

    User.create!(
      email: email,
      first_name: row[:first_name],
      last_name: row[:last_name],
      student_id: row[:student_id],
      associate_id: row[:associate_id],
      password: Devise.friendly_token[0, 20]
    )
  end
end
