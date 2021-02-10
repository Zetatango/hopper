# frozen_string_literal: true

# rubocop:disable RSpec/FilePath
RSpec.describe Hopper do
  it "has a version number" do
    expect(described_class::VERSION).not_to be nil
  end
end
# rubocop:enable RSpec/FilePath
