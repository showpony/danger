require "danger/ci_source/ci_source"
require "danger/request_sources/request_source"

module Danger
  class EnvironmentManager
    attr_accessor :ci_source, :request_source, :scm, :ui

    # Finds a Danger::CI class based on the ENV
    def self.local_ci_source(env)
      CI.available_ci_sources.find { |ci| ci.validates_as_ci? env }
    end

    # Uses the current Danger::CI subclass, and sees if it is a PR
    def self.pr?(env)
      local_ci_source(env).validates_as_pr?(env)
    end

    # @return [String] danger's default head branch
    def self.danger_head_branch
      "danger_head".freeze
    end

    # @return [String] danger's default base branch
    def self.danger_base_branch
      "danger_base".freeze
    end

    def initialize(env, ui = nil)
      ci_klass = self.class.local_ci_source(env)
      self.ci_source = ci_klass.new(env)
      self.ui = ui || Cork::Board.new(silent: false, verbose: false)

      RequestSources::RequestSource.available_request_sources.each do |klass|
        next unless self.ci_source.supports?(klass)

        request_source = klass.new(self.ci_source, env)
        next unless request_source.validates_as_ci?
        next unless request_source.validates_as_api_source?
        self.request_source = request_source
      end

      raise_error_for_no_request_source(env, self.ui) unless self.request_source
      self.scm = self.request_source.scm
    end

    def pr?
      self.ci_source != nil
    end

    def fill_environment_vars
      request_source.fetch_details
    end

    def ensure_danger_branches_are_setup
      clean_up

      self.request_source.setup_danger_branches
    end

    def clean_up
      [EnvironmentManager.danger_base_branch, EnvironmentManager.danger_head_branch].each do |branch|
        scm.exec("branch -D #{branch}") unless scm.exec("rev-parse --quiet --verify #{branch}").empty?
      end
    end

    def meta_info_for_head
      scm.exec("--no-pager log #{EnvironmentManager.danger_head_branch} -n1")
    end

    def meta_info_for_base
      scm.exec("--no-pager log #{EnvironmentManager.danger_base_branch} -n1")
    end

    def raise_error_for_no_request_source(env, ui)
      title, subtitle = extract_title_and_subtitle_from_source(ci_source.repo_url)
      subtitle += travis_note if env["TRAVIS_SECURE_ENV_VARS"] == "true"

      ui_display_no_request_source_error_message(ui, env, title, subtitle)

      exit(1)
    end

    private

    def get_repo_source()
      # if ENV["DANGER_GITHUB_API_TOKEN"]
        RequestSources::GitHub
      # elsif ENV["DANGER_GITLAB_API_TOKEN"]
      #   RequestSources::GitLab
      # elsif ENV["DANGER_BITBUCKETCLOUD_USERNAME"] && ENV["DANGER_BITBUCKETCLOUD_PASSWORD"]
      #   RequestSources::BitbucketCloud
      # elsif ENV["DANGER_BITBUCKETSERVER_USERNAME"] && ENV["DANGER_BITBUCKETSERVER_PASSWORD"] && ENV["DANGER_BITBUCKETSERVER_HOST"]
      #   RequestSources::BitbucketServer
      # end
    end

    def extract_title_and_subtitle_from_source(repo_url)
      source = get_repo_source()

      if source
        title = "For your #{source.source_name} repo, you need to expose: " + source.env_vars.join(", ").yellow
        subtitle = "You may also need: #{source.optional_env_vars.join(', ')}" if source.optional_env_vars.any?
      else
        title = "-M&M was here- For Danger to run on this project, you need to expose a set of following the ENV vars:\n#{RequestSources::RequestSource.available_source_names_and_envs.join("\n")}"
      end

      [title, (subtitle || "")]
    end

    def ui_display_no_request_source_error_message(ui, env, title, subtitle)
      ui.title "Could not set up API to Code Review site for Danger\n".freeze
      ui.puts title
      ui.puts subtitle
      ui.puts "\nFound these keys in your ENV: #{env.keys.join(', '.freeze)}."
      ui.puts "\nFailing the build, Danger cannot run without API access.".freeze
      ui.puts "You can see more information at http://danger.systems/guides/getting_started.html".freeze
    end

    def travis_note
      "\nTravis note: If you have an open source project, you should ensure 'Display value in build log' enabled for these flags, so that PRs from forks work." \
      "\nThis also means that people can see this token, so this account should have no write access to repos."
    end
  end
end
