require "pathname"
require "fileutils"
require "net/http"
require "git_commands/prompt"
require "git_commands/branch"
require "git_commands/repository"

module GitCommands
  class Computer
    include Prompt

    class GitError < StandardError; end

    attr_reader :out

    def initialize(repo:, branches:, repo_klass: Repository, branch_klass: Branch, out: STDOUT)
      @out = out
      @repo = repo_klass.new(repo)
      Dir.chdir(@repo) do
        @branches = branch_klass.factory(branches)
        @timestamp = Time.new.strftime("%Y-%m-%d")
        print_branches
      end
    end

    def purge
      enter_repo do
        confirm("Proceed removing these branches") do
          @branches.each do |branch|
            warning("Removing branch: #{branch}")
            `git branch -D #{branch}` if branch.exists?(false)
            `git push origin :#{branch}`
          end
        end
      end
    end

    def rebase
      confirm("Proceed rebasing these branches with master") do
        enter_repo do
          @branches.each do |branch|
            warning("Rebasing branch: #{branch}")
            `git checkout #{branch}`
            `git pull origin #{branch}`
            next unless rebase_with_master
            `git push -f origin #{branch}`
            success("Rebased successfully!")
          end
          remove_locals
        end
      end
    end

    def aggregate
      temp = "temp/#{@timestamp}"
      release = "release/#{@timestamp}"
      confirm("Aggregate branches into #{release}") do
        enter_repo do
          `git branch #{release}`
          @branches.each do |branch|
            warning("Merging branch: #{branch}")
            `git checkout -b #{temp} origin/#{branch} --no-track`
            remove_locals([temp, release]) && exit unless rebase_with_master
            `git rebase #{release}`
            `git checkout #{release}`
            `git merge #{temp}`
            `git branch -D #{temp}`
          end      
        end
        success("#{release} branch created")
      end
    end

    private def print_branches
      fail GitError, "No branches loaded!" if @branches.empty?
      size = @branches.to_a.size
      plural = size > 1 ? "es" : ""
      success("Successfully loaded #{size} branch#{plural}:")
      @out.puts @branches.each_with_index.map { |branch, i| "#{(i+1).to_s.rjust(2, "0")}. #{branch}" } + [""]
    end

    private def pull_master
      `git checkout #{Branch::MASTER}`
      `git pull`
    end

    private def rebase_with_master
      `git rebase origin/#{Branch::MASTER}`
      return true unless @repo.locked?
      @repo.unlock
      error("Got conflicts, aborting rebase!")
    end

    private def enter_repo
      Dir.chdir(@repo) do
        pull_master
        yield
      end
    end

    private def remove_locals(branches = @branches)
      `git checkout #{Branch::MASTER}`
      branches.each do |branch|
        `git branch -D #{branch}`
      end
    end
  end
end
