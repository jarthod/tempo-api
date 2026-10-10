# tempo-api

Running web server locally:

```sh
bundle install
bundle exec rackup
```

Tests

```sh
bundle exec rspec
```

Deploy (Hatchbox deploys automatically on push to master)
```sh
git push origin master
```

## Local development (Windows)

The project requires Ruby 3.3.x. On Windows, install Ruby 3.3 with RubyInstaller
and its MSYS2 development tools, then open a new PowerShell terminal in this
repository.

Check Ruby and install the locked dependencies:

```powershell
ruby --version
bundle --version
bundle install
```

Start the development server:

```powershell
bundle exec rackup --host 127.0.0.1 --port 9292
```

Open <http://localhost:9292/id> for the device configuration page, or
<http://localhost:9292/admin> for the admin page. The local admin password
defaults to `test`; override it before starting the server if needed:

```powershell
$env:PASSWORD = "local-dev-password"
bundle exec rackup --host 127.0.0.1 --port 9292
```

The development server stores its SQLite database in the ignored `data/`
directory. Tests use an in-memory database and VCR fixtures, so they do not
modify that local database or require live API access. Run the test suite with:

```powershell
bundle exec rspec
```

Stop the server with `Ctrl+C`.