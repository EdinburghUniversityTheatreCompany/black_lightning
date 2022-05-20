# == Schema Information
#
# Table name: users
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *email*::                  <tt>string(255), default(""), not null</tt>
# *encrypted_password*::     <tt>string(255), default(""), not null</tt>
# *reset_password_token*::   <tt>string(255)</tt>
# *reset_password_sent_at*:: <tt>datetime</tt>
# *remember_created_at*::    <tt>datetime</tt>
# *sign_in_count*::          <tt>integer, default(0)</tt>
# *current_sign_in_at*::     <tt>datetime</tt>
# *last_sign_in_at*::        <tt>datetime</tt>
# *current_sign_in_ip*::     <tt>string(255)</tt>
# *last_sign_in_ip*::        <tt>string(255)</tt>
# *first_name*::             <tt>string(255)</tt>
# *last_name*::              <tt>string(255)</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *phone_number*::           <tt>string(255)</tt>
# *public_profile*::         <tt>boolean, default(TRUE)</tt>
# *bio*::                    <tt>text(65535)</tt>
# *avatar_file_name*::       <tt>string(255)</tt>
# *avatar_content_type*::    <tt>string(255)</tt>
# *avatar_file_size*::       <tt>integer</tt>
# *avatar_updated_at*::      <tt>datetime</tt>
# *username*::               <tt>string(255)</tt>
# *remember_token*::         <tt>string(255)</tt>
# *consented*::              <tt>date</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :user do
    first_name            { Faker::Name.first_name }
    last_name             { Faker::Name.last_name  }
    email                 { Faker::Internet.email  }
    phone_number          { '12345' }
    password              { :random_password }
    password_confirmation { password }
    consented             { 5.day.ago.to_fs(:db) }
  
    factory :member do
      after(:create) do |user, _evaluator|
        user.add_role :member
      end

      factory :member_with_phone_number do
        phone_number { rand(10**9..10**10).to_s }
      end
    end

    factory :committee do
      after(:create) do |user, _evaluator|
        user.add_role :member
        user.add_role 'Committee'
      end
    end

    factory :admin do
      after(:create) do |user, _evaluator|
        user.add_role :admin
      end
    end
  end
end
