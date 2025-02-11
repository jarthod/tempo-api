require 'app_helper'

RSpec.describe Device do
  describe "#settings" do
    it "can be set and retrieve as a generic Ruby Hash (excluding symbols)" do
      test_settings = {integer: 1, 'string' => 'b', array: [1, 2, 3], hash: {true: true, false: false, nil: nil}}
      Device.create! id: 1, settings: test_settings
      expect(Device.find(1).settings).to eq(test_settings.deep_stringify_keys)
    end
  end
end