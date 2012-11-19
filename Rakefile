#!/usr/bin/env rake
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require File.expand_path('../config/application', __FILE__)

ChaosRails::Application.load_tasks

require 'rake/dsl_definition'
require 'rubygems'

gem 'ci_reporter'
require 'ci/reporter/rake/minitest'