# frozen_string_literal: true

# Copyright (c) 2010-2011, Diaspora Inc.  This file is
# licensed under the Affero General Public License version 3 or later.  See
# the COPYRIGHT file.

namespace :migrations do
  task :upload_photos_to_s3 do
    require File.join(File.dirname(__FILE__), '..', '..', 'config', 'environment')
    puts AppConfig.environment.s3.key

    connection = Aws::S3.new( AppConfig.environment.s3.key, AppConfig.environment.s3.secret)
    bucket = connection.bucket(AppConfig.environment.s3.bucket)
    dir_name = File.dirname(__FILE__) + "/../../public/uploads/images/"

    count = Dir.foreach(dir_name).count
    current = 0

    Dir.foreach(dir_name){|file_name| puts file_name;
      if file_name != '.' && file_name != '..';
        begin
          key = Aws::S3::Key.create(bucket, 'uploads/images/' + file_name);
          key.put(File.open(dir_name+ '/' + file_name).read, 'public-read');
          key.public_link();
          puts "Uploaded #{current} of #{count}"
          current += 1
        rescue => e
          puts "error #{e} on #{current} (#{file_name}), retrying"
          retry
        end
      end
    }
  end

  desc "Removed: this used to move Sidekiq jobs between legacy queues. " \
       "GoodJob (DB-backed) is now the job runner and has no equivalent " \
       "concept — retry queued jobs from the /good_job dashboard instead."
  task :legacy_queues do
    warn "rake migrations:legacy_queues is a no-op since the GoodJob migration."
  end

  desc "Run uncompleted account deletions"
  task run_account_deletions: :environment do
    if AccountDeletion.uncompleted.count > 0
      puts "Running account deletions..."
      AccountDeletion.uncompleted.find_each do |account_deletion|
        print "Deleting #{account_deletion.person.diaspora_handle} ..."
        progress = Thread.new {
          loop {
            sleep 10
            print "."
          }
        }
        account_deletion.perform!
        progress.kill
        puts " Done"
      end
      puts "OK."
    else
      puts "No account deletions to run."
    end
  end
end
