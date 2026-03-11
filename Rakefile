require 'sinatra/activerecord/rake'

namespace :db do
  task :load_config do
    require "./tempo-api"
  end

  task :annotate do
    `bundle exec annotate --position before`
  end

  task :pull do
    system("cp data/db.sqlite3 data/db.save.sqlite3")
    system("scp root@dokku.rootbox.fr:/mnt/dokku_data/tempo-api/data/db.sqlite3 data/db.sqlite3")
  end

  task :push do
    system("scp deploy@hatch.rootbox.fr:/data/tempo-api/db.sqlite3 data/production.backup.sqlite3")
    system("scp data/db.sqlite3 deploy@hatch.rootbox.fr:/data/tempo-api/db.sqlite3")
  end
end
