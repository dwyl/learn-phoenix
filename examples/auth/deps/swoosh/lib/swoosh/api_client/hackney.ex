defmodule Swoosh.ApiClient.Hackney do
  @moduledoc """
  Built-in hackney-based ApiClient.
  """

  require Logger

  @behaviour Swoosh.ApiClient
  @user_agent {"User-Agent", "swoosh/#{Swoosh.version()}"}

  @impl true
  def init do
    unless Code.ensure_loaded?(:hackney) do
      Logger.error("""
      Could not find hackney dependency.

      Please add :hackney to your dependencies:

          {:hackney, "~> 1.9"}

      Or set your own Swoosh.ApiClient:

          config :swoosh, :api_client, MyAPIClient
      """)

      raise "missing hackney dependency"
    end

    _ = Application.ensure_all_started(:hackney)
    :ok
  end

  @impl true
  def post(url, headers, body, %Swoosh.Email{} = email) do
    hackney_options = email.private[:hackney_options] || email.private[:client_options] || []

    :hackney.post(
      url,
      [@user_agent | headers],
      body,
      [:with_body | hackney_options]
    )
  end
end
