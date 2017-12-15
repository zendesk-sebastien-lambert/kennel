# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Monitor do
  class TestMonitor < Kennel::Models::Monitor
  end

  # generate readables diffs when things are not equal
  def assert_json_equal(a, b)
    JSON.pretty_generate(a).must_equal JSON.pretty_generate(b)
  end

  def monitor(options = {})
    Kennel::Models::Monitor.new(
      options.delete(:project) || project,
      {
        kennel_id: -> { "m1" },
        query: -> { "(last_5m) > #{critical}" },
        critical: -> { 123.0 }
      }.merge(options)
    )
  end

  let(:project) { TestProject.new }
  let(:expected_basic_json) do
    {
      name: "Kennel::Models::Monitor\u{1F512}",
      type: "query alert",
      query: +"(last_5m) > 123.0",
      message: "@slack-foo",
      tags: ["service:test_project"],
      multi: false,
      options: {
        timeout_h: 0,
        notify_no_data: true,
        no_data_timeframe: 60,
        notify_audit: true,
        require_full_window: true,
        new_host_delay: 300,
        include_tags: true,
        escalation_message: nil,
        evaluation_delay: nil,
        locked: false,
        renotify_interval: 120,
        thresholds: { critical: 123.0 }
      }
    }
  end

  describe "#initialize" do
    it "stores project" do
      TestMonitor.new(111).project.must_equal 111
    end

    it "stores options" do
      TestMonitor.new(111, name: -> { "XXX" }).name.must_equal "XXX"
    end
  end

  describe "#kennel_id" do
    it "cannot be called for 1-off base class since it would be weird" do
      e = assert_raises(RuntimeError) { Kennel::Models::Monitor.new(111).kennel_id }
      e.message.must_equal "Need to set :kennel_id when defining monitors from Kennel::Models::Monitor"
    end

    it "can call on regular monitor" do
      TestMonitor.new(111).kennel_id.must_equal "test_monitor"
    end
  end

  describe "#as_json" do
    it "creates a basic json" do
      assert_json_equal(
        monitor.as_json,
        expected_basic_json
      )
    end

    it "can set warning" do
      monitor(warning: -> { 123.0 }).as_json.dig(:options, :thresholds, :warning).must_equal 123.0
    end

    it "adds project tags" do
      monitor(project: TestProject.new(tags: -> { ["foo"] })).as_json[:tags].must_equal(["foo"])
    end

    it "sets 0 when re-notify is disabled" do
      monitor(renotify_interval: -> { false }).as_json[:options][:renotify_interval].must_equal 0
    end

    it "sets multi true on multi query alerts" do
      monitor(query: -> { "(last_5m) by foo > 123.0" }).as_json[:multi].must_equal true
    end

    it "converts threshold values to floats to avoid api diff" do
      monitor(critical: -> { 234 }).as_json
        .dig(:options, :thresholds, :critical).must_equal 234.0
    end

    it "does not converts threshold values to floats for types that store integers" do
      monitor(critical: -> { 234 }, type: -> { "service check" }).as_json
        .dig(:options, :thresholds, :critical).must_equal 234
    end

    it "fails when using invalid type for service type thresholds" do
      e = assert_raises(RuntimeError) { monitor(critical: -> { 234.1 }, type: -> { "service check" }).as_json }
      e.message.must_equal "test_project:m1 :ok, :warning and :critical must be integers for service check type"
    end

    it "fails when using invalid interval for query alert type" do
      e = assert_raises(RuntimeError) { monitor(critical: -> { 234.1 }, query: -> { "avg(last_20m).count() < #{critical}" }).as_json }
      e.message.must_equal "test_project:m1 query interval was 20m, but must be one of 1m, 5m, 10m, 15m, 30m, 1h, 2h, 4h, 24h"
    end

    it "does not allow mismatching query and critical" do
      e = assert_raises(RuntimeError) { monitor(critical: -> { 123.0 }, query: -> { "foo < 12" }).as_json }
      e.message.must_equal "test_project:m1 critical and value used in query must match"
    end

    it "fails on invalid renotify intervals" do
      e = assert_raises(RuntimeError) { monitor(renotify_interval: -> { 123 }).as_json }
      e.message.must_include "test_project:m1 renotify_interval must be one of 0, 10, 20,"
    end

    it "sets no_data_timeframe to `nil` when notify_no_data is false" do
      monitor(notify_no_data: -> { false }).as_json[:options][:no_data_timeframe].must_be_nil
    end

    it "is cached so we can modify it in syncer" do
      m = monitor
      m.as_json[:foo] = 1
      m.as_json[:foo].must_equal 1
    end

    it "fails on deprecated metric alert type" do
      e = assert_raises(RuntimeError) { monitor(type: -> { "metric alert" }).as_json }
      e.message.must_include "metric alert"
    end
  end

  describe "#diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      a = expected_basic_json.merge(a)
      a[:options] = expected_basic_json[:options].merge(a[:options] || {})
      monitor(e).diff(a)
    end

    it "calls super" do
      diff_resource({}, deleted: true).must_be_nil
    end

    it "ignores silenced" do
      diff_resource({}, options: { silenced: true }).must_be_nil
    end

    it "ignores missing escalation_message" do
      expected_basic_json[:options].delete(:escalation_message)
      diff_resource({}, {}).must_be_nil
    end

    it "ignores missing evaluation_delay" do
      expected_basic_json[:options].delete(:evaluation_delay)
      diff_resource({}, {}).must_be_nil
    end

    it "ignores include_tags/require_full_window for service alerts" do
      assert expected_basic_json[:query].sub!("123.0", "123")
      expected_basic_json[:options].delete(:include_tags)
      expected_basic_json[:options].delete(:require_full_window)
      expected_basic_json[:options][:thresholds][:critical] = 123
      diff_resource(
        {
          type: -> { "service check" },
          critical: -> { 123 },
          warning: -> { 1 },
          ok: -> { 1 }
        },
        type: "service check",
        multi: true
      ).must_be_nil
    end

    it "ignores missing critical from event alert" do
      assert expected_basic_json[:query].sub!("123.0", "0")
      expected_basic_json[:options].delete(:thresholds)
      diff_resource(
        {
          type: -> { "event alert" },
          critical: -> { 0 }
        },
        type: "event alert",
        multi: true
      ).must_be_nil
    end

    it "ignores type diff between metric and query since datadog uses both randomly" do
      diff_resource({ type: -> { "query alert" } }, {}).must_be_nil
    end
  end

  describe "#url" do
    it "shows path" do
      monitor.url(111).must_equal "/monitors#111/edit"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        monitor.url(111).must_equal "https://foobar.datadoghq.com/monitors#111/edit"
      end
    end
  end

  describe ".api_resource" do
    it "is set" do
      Kennel::Models::Monitor.api_resource.must_equal "monitor"
    end
  end
end
