# frozen_string_literal: true

require 'formula'
require 'utils/pypi'

class Object
  def false?
    nil?
  end
end

class String
  def false?
    empty? || strip == 'false'
  end
end

module Homebrew
  module_function

  def print_command(*cmd)
    puts "[command]#{cmd.join(' ').gsub("\n", ' ')}"
  end

  def brew(*args)
    print_command ENV["HOMEBREW_BREW_FILE"], *args
    safe_system ENV["HOMEBREW_BREW_FILE"], *args
  end

  def git(*args)
    print_command ENV["HOMEBREW_GIT"], *args
    safe_system ENV["HOMEBREW_GIT"], *args
  end

  def read_brew(*args)
    print_command ENV["HOMEBREW_BREW_FILE"], *args
    output = `#{ENV["HOMEBREW_BREW_FILE"]} #{args.join(' ')}`.chomp
    odie output if $CHILD_STATUS.exitstatus != 0
    output
  end

  # Get inputs
  message = ENV['HOMEBREW_BUMP_MESSAGE']
  org = ENV['HOMEBREW_BUMP_ORG']
  tap = ENV['HOMEBREW_BUMP_TAP']
  formula = ENV['HOMEBREW_BUMP_FORMULA']
  tag = ENV['HOMEBREW_BUMP_TAG']
  revision = ENV['HOMEBREW_BUMP_REVISION']
  force = ENV['HOMEBREW_BUMP_FORCE']
  livecheck = ENV['HOMEBREW_BUMP_LIVECHECK']
  user_name = ENV['HOMEBREW_USER_NAME']
  user_email = ENV['HOMEBREW_USER_EMAIL']

  # Check inputs
  if livecheck.false?
    odie "Need 'formula' input specified" if formula.blank?
    odie "Need 'tag' input specified" if tag.blank?
  end

  # Tell git who you are
  git 'config', '--global', 'user.name', user_name
  git 'config', '--global', 'user.email', user_email

  # Tap the tap if desired
  brew 'tap', tap unless tap.blank?

  # Append additional PR message
  message = if message.blank?
              ''
            else
              message + "\n\n"
            end
  message += '[`action-homebrew-bump-formula`](https://github.com/dawidd6/action-homebrew-bump-formula)'

  # Do the livecheck stuff or not
  if livecheck.false?
    # Change formula name to full name
    formula = tap + '/' + formula if !tap.blank? && !formula.blank?

    # Get info about formula
    stable = Formula[formula].stable
    is_git = stable.downloader.is_a? GitDownloadStrategy

    # Prepare tag and url
    tag = tag.delete_prefix 'refs/tags/'
    version = Version.parse tag
    url = stable.url.gsub stable.version, version

    # Check if formula is originating from PyPi
    pypi_url = PyPI.update_pypi_url(stable.url, version)
    if pypi_url
      # Substitute url
      url = pypi_url
      # Install pipgrip utility so resources from PyPi get updated too
      brew 'install', 'pipgrip'
    end

    # Finally bump the formula
    brew 'bump-formula-pr',
         '--no-audit',
         '--no-browse',
         "--message=#{message}",
         *("--fork-org=#{org}" unless org.blank?),
         *("--version=#{version}" unless is_git),
         *("--url=#{url}" unless is_git),
         *("--tag=#{tag}" if is_git),
         *("--revision=#{revision}" if is_git),
         *('--force' unless force.false?),
         formula
  else
    # Support multiple formulae in input and change to full names if tap
    unless formula.blank?
      formula = formula.split(/[ ,\n]/).reject(&:blank?)
      formula = formula.map { |f| tap + '/' + f } unless tap.blank?
    end

    # Get livecheck info
    json = read_brew 'livecheck',
                     '--formula',
                     '--quiet',
                     '--newer-only',
                     '--full-name',
                     '--json',
                     *("--tap=#{tap}" if !tap.blank? && formula.blank?),
                     *(formula unless formula.blank?)
    json = JSON.parse json

    # Define error
    err = nil

    # Loop over livecheck info
    json.each do |info|
      # Skip if there is no version field
      next unless info['version']

      # Get info about formula
      formula = info['formula']
      version = info['version']['latest']

      # Get stable software spec of the formula
      stable = Formula[formula].stable

      # Check if formula is originating from PyPi
      if !Formula["pipgrip"].any_version_installed? && PyPI.update_pypi_url(stable.url, version)
        # Install pipgrip utility so resources from PyPi get updated too
        brew 'install', 'pipgrip'
      end

      begin
        # Finally bump the formula
        brew 'bump-formula-pr',
             '--no-audit',
             '--no-browse',
             "--message=#{message}",
             "--version=#{version}",
             *("--fork-org=#{org}" unless org.blank?),
             *('--force' unless force.false?),
             formula
      rescue ErrorDuringExecution => e
        # Continue execution on error, but save the exeception
        err = e
      end
    end

    # Die if error occured
    odie err if err
  end
end
