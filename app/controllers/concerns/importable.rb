# frozen_string_literal: true

##
# Shared functionality for bulk import controllers.
# Provides common methods for parsing, caching, and user creation.
##
module Importable
  extend ActiveSupport::Concern

  private

  # Parse the import data from params (either paste or xlsx upload)
  # @return [Array] [data, input_type] where input_type is :paste or :xlsx
  def parse_import_params
    data = params[:paste_data].presence || params[:xlsx_file]
    input_type = params[:paste_data].present? ? :paste : :xlsx
    [ data, input_type ]
  end

  # Serialize categorized import data for cache storage
  # Converts ActiveRecord objects to IDs to avoid serialization issues
  def serialize_import(categorized)
    categorized.transform_values do |items|
      items.map do |item|
        {
          "row" => item[:row],
          "existing_user_id" => item[:existing_user]&.id,
          "index" => item[:index]
        }
      end
    end
  end

  # Read and clear cache entry for import data
  # @return [Hash, nil] The cached data or nil if not found
  def read_and_clear_cache(cache_key)
    return nil if cache_key.blank?

    data = Rails.cache.read(cache_key)
    Rails.cache.delete(cache_key) if data.present?
    data
  end

  # Generate a unique cache key for storing import data
  # @param prefix [String] Prefix for the cache key (e.g., "user_import", "crew_import")
  def generate_import_cache_key(prefix)
    "#{prefix}_#{SecureRandom.uuid}"
  end

  # Write import data to cache with standard expiration
  def write_import_cache(cache_key, data)
    Rails.cache.write(cache_key, data.with_indifferent_access, expires_in: 1.hour)
  end

  # Generate a placeholder email for users without one
  def generate_placeholder_email
    "unknown_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk"
  end

  # Create a new user from import row data
  # @param row [Hash] The normalized row data with :email, :first_name, :last_name, etc.
  # @return [User] The created user
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
