# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Project do
  describe ".file_location" do
    let(:plain_project_class) do
      Class.new(Kennel::Models::Project) do
        def self.to_s
          "PlainProject" # to make debugging less confusing
        end
      end
    end

    it "finds the file" do
      TestProject.file_location.must_equal "test/test_helper.rb"
    end

    it "cannot detect if there are no methods" do
      Class.new(Kennel::Models::Project).file_location.must_be_nil
    end

    it "detects the file location when defaults-plain is used" do
      project_class = plain_project_class
      eval <<~EVAL, nil, "dir/foo.rb", 1
        project_class.instance_eval do
          defaults(name: 'bar')
        end
      EVAL
      project_class.file_location.must_equal("dir/foo.rb")
    end

    it "detects the file location when defaults-proc is used" do
      project_class = plain_project_class
      eval <<~EVAL, nil, "dir/foo.rb", 1
        project_class.instance_eval do
          defaults(name: -> { 'bar' })
        end
      EVAL
      project_class.file_location.must_equal("dir/foo.rb")
    end

    it "detects the file location when a custom method is used" do
      project_class = plain_project_class
      eval <<~EVAL, nil, "dir/foo.rb", 1
        project_class.define_method(:my_method) { }
      EVAL
      project_class.file_location.must_equal("dir/foo.rb")
    end
  end

  describe "#tags" do
    it "adds itself by default" do
      TestProject.new.tags.must_equal ["service:test_project", "team:test_team"]
    end
  end

  describe "#mention" do
    it "uses teams mention" do
      TestProject.new.mention.must_equal "@slack-foo"
    end
  end

  describe "#validated_parts" do
    it "returns parts" do
      TestProject.new.validated_parts.size.must_equal 0
    end
  end
end
