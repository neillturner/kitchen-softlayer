# Encoding: UTF-8

require_relative '../../spec_helper'
require_relative '../../../lib/kitchen/driver/softlayer'

require 'logger'
require 'stringio'
require 'rspec'
require 'kitchen'

describe Kitchen::Driver::Softlayer do
  let(:logged_output) { StringIO.new }
  let(:logger) { Logger.new(logged_output) }
  let(:config) { Hash.new }
  let(:state) { Hash.new }
  let(:driver) { Kitchen::Driver::Softlayer.new(config) }

  describe '#disable_ssl_validation' do
    it 'turns off Excon SSL cert validation' do
      expect(driver.send(:disable_ssl_validation)).to eq(false)
    end
  end
end
