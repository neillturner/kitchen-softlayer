# frozen_string_literal: true

require 'simplecov'

# Filter out our tests from code coverage
SimpleCov.start do
  add_filter '/spec/'
end
