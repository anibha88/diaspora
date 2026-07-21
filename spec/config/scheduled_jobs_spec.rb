# frozen_string_literal: true

require "yaml"
require "tempfile"

# Coverage for config/initializers/good_job.rb (the cron portion).
#
# The initializer defines helper methods (default_job_config,
# valid_config?, regenerate_config) at the top level; loading the file
# in the spec exposes those helpers. The runtime `Rails.application.configure`
# block at the bottom is also re-executed on load — that's harmless in the
# test env, and only overwrites config we don't assert on here.

describe "good_job initializer (cron schedule)", type: :initializer do
  before(:all) do
    load Rails.root.join("config", "initializers", "good_job.rb").to_s
  end

  let(:config) { default_job_config }

  describe "default_job_config" do
    it "registers exactly the seven expected recurring jobs" do
      expect(config.keys).to match_array(%i[
        check_birthday
        clean_cached_files
        cleanup_old_exports
        cleanup_pending_photos
        queue_users_for_removal
        recheck_scheduled_pods
        recurring_pod_check
      ])
    end

    it "maps each job to its Workers class" do
      expect(config[:check_birthday][:class]).to          eq("Workers::CheckBirthday")
      expect(config[:clean_cached_files][:class]).to      eq("Workers::CleanCachedFiles")
      expect(config[:cleanup_old_exports][:class]).to     eq("Workers::CleanupOldExports")
      expect(config[:cleanup_pending_photos][:class]).to  eq("Workers::CleanupPendingPhotos")
      expect(config[:queue_users_for_removal][:class]).to eq("Workers::QueueUsersForRemoval")
      expect(config[:recheck_scheduled_pods][:class]).to  eq("Workers::RecheckScheduledPods")
      expect(config[:recurring_pod_check][:class]).to     eq("Workers::RecurringPodCheck")
    end

    it "runs check_birthday at midnight UTC" do
      expect(config[:check_birthday][:cron]).to eq("0 0 * * *")
    end

    it "runs recheck_scheduled_pods every 30 minutes" do
      expect(config[:recheck_scheduled_pods][:cron]).to eq("*/30 * * * *")
    end

    describe "randomized nightly jobs" do
      # These five must run at a random hour/minute so all pods don't wake up
      # (and DDoS each other via recurring_pod_check) at the same UTC moment.
      %i[clean_cached_files
         cleanup_old_exports
         cleanup_pending_photos
         queue_users_for_removal
         recurring_pod_check].each do |job|
        it "generates a valid daily cron string for #{job}" do
          cron = config[job][:cron]
          # "<0-59> <0-23> * * *"
          expect(cron).to match(/\A(?<min>\d{1,2}) (?<hour>\d{1,2}) \* \* \*\z/)
          minute, hour = cron.split.first(2).map(&:to_i)
          expect(minute).to be_between(0, 59)
          expect(hour).to be_between(0, 23)
        end
      end

      it "does not schedule recurring_pod_check at midnight UTC (guarded against)" do
        # Formally random; the guard in valid_config? treats a persisted
        # midnight cron as evidence of a stale, pre-random config that must
        # be regenerated. Freshly generated configs must never look stale.
        # We take a handful of samples to make the check meaningful.
        20.times do
          expect(default_job_config[:recurring_pod_check][:cron]).not_to eq("0 0 * * *")
        end
      end
    end
  end

  describe "valid_config?" do
    let(:tmp) { Tempfile.new(["schedule", ".yml"]) }

    after do
      # Tempfile#close! nils out `path`, so capture it first.
      path = tmp.path
      tmp.close!
      File.delete(path) if path && File.exist?(path)
    end

    it "returns false when the file does not exist" do
      missing_path = "#{tmp.path}.definitely-missing"
      expect(valid_config?(missing_path)).to be false
    end

    it "returns false when the persisted keys don't match the current defaults" do
      # Drop a key so the set no longer matches.
      partial = default_job_config.dup
      partial.delete(:recurring_pod_check)
      File.write(tmp.path, partial.to_yaml)

      expect(valid_config?(tmp.path)).to be false
    end

    it "returns false when recurring_pod_check is stuck at midnight UTC" do
      stale = default_job_config.dup
      stale[:recurring_pod_check] = {"cron": "0 0 * * *", "class": "Workers::RecurringPodCheck"}
      File.write(tmp.path, stale.to_yaml)

      expect(valid_config?(tmp.path)).to be false
    end

    it "returns true for a freshly-written config" do
      File.write(tmp.path, default_job_config.to_yaml)
      expect(valid_config?(tmp.path)).to be true
    end
  end

  describe "regenerate_config" do
    let(:tmp) { Tempfile.new(["schedule", ".yml"]) }

    after do
      # Tempfile#close! nils out `path`, so capture it first.
      path = tmp.path
      tmp.close!
      File.delete(path) if path && File.exist?(path)
    end

    it "writes a YAML file whose keys match the default config" do
      regenerate_config(tmp.path)
      written = YAML.load_file(tmp.path)
      expect(written.keys).to match_array(default_job_config.keys)
    end

    it "produces output that passes valid_config?" do
      regenerate_config(tmp.path)
      expect(valid_config?(tmp.path)).to be true
    end
  end
end
