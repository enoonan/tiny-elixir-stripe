defmodule Mix.Tasks.PinStripe.SyncApiVersion do
  use Mix.Task

  @shortdoc "Syncs fixture API version with your Stripe account"

  @moduledoc """
  Detects your Stripe account's API version and updates fixtures accordingly.

  When your Stripe account upgrades to a new API version, this task will:

  1. Detect the new API version from your account
  2. Compare with the cached version in `.api_version`
  3. If different, update `.api_version` and clear all fixtures
  4. Fixtures will regenerate with the new version on next test run

  ## Examples

      # Sync API version
      mix pin_stripe.sync_api_version

  ## Requirements

  - Stripe CLI installed and authenticated
  - Test mode API key configured
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Syncing Stripe API version...")
    IO.puts("")

    # Detect current version
    IO.puts("Detecting Stripe account API version...")
    current_version = PinStripe.Test.Fixtures.detect_account_api_version()
    IO.puts("Account API version: #{current_version}")
    IO.puts("")

    # Check cached version
    cached_version = PinStripe.Test.Fixtures.api_version()

    if cached_version do
      IO.puts("Cached fixture version: #{cached_version}")

      if current_version == cached_version do
        IO.puts("")
        IO.puts("✓ Fixtures are already up to date!")
      else
        IO.puts("")
        IO.puts("⚠️  API version changed!")
        IO.puts("")
        IO.puts("Clearing all fixtures...")

        fixture_count = length(PinStripe.Test.Fixtures.list())
        clear_all_fixtures()

        IO.puts("Cleared #{fixture_count} fixture(s)")
        IO.puts("")
        IO.puts("Updating .api_version file...")
        update_api_version_file(current_version)

        IO.puts("")

        IO.puts(
          "✓ Done! Fixtures will regenerate with API version #{current_version} on next test run."
        )
      end
    else
      IO.puts("No cached fixtures found. Initializing...")
      IO.puts("")
      update_api_version_file(current_version)
      IO.puts("✓ Initialized with API version #{current_version}")
    end
  end

  defp update_api_version_file(version) do
    fixtures_dir = "test/fixtures/stripe"
    version_file = Path.join(fixtures_dir, ".api_version")

    File.mkdir_p!(fixtures_dir)
    File.write!(version_file, version)
  end

  defp clear_all_fixtures do
    fixtures_dir = "test/fixtures/stripe"

    if File.exists?(fixtures_dir) do
      File.ls!(fixtures_dir)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.each(fn file ->
        File.rm!(Path.join(fixtures_dir, file))
      end)
    end
  end
end
