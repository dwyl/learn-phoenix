defmodule ElixirMake.Downloader.Httpc do
  @moduledoc false

  @behaviour ElixirMake.Downloader

  @impl ElixirMake.Downloader
  def download(url) do
    url_charlist = String.to_charlist(url)

    # TODO: Remove me when we require Elixir v1.15
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:public_key)

    if proxy = System.get_env("HTTP_PROXY") || System.get_env("http_proxy") do
      Mix.shell().info("Using HTTP_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)

      :httpc.set_options([{:proxy, {{String.to_charlist(host), port}, []}}])
    end

    if proxy = System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      Mix.shell().info("Using HTTPS_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:https_proxy, {{String.to_charlist(host), port}, []}}])
    end

    # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/inets
    # TODO: This may no longer be necessary from Erlang/OTP 25.0 or later.
    https_options = [
      ssl:
        [
          verify: :verify_peer,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ] ++ cacerts_options()
    ]

    options = [body_format: :binary]

    case :httpc.request(:get, {url_charlist, []}, https_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      other ->
        {:error, "couldn't fetch NIF from #{url}: #{inspect(other)}"}
    end
  end

  defp cacerts_options do
    cond do
      path = System.get_env("HEX_CACERTS_PATH") ->
        [cacertfile: path]

      path = System.get_env("ELIXIR_MAKE_CACERT") ->
        IO.warn("Setting ELIXIR_MAKE_CACERT is deprecated, please set HEX_CACERTS_PATH instead")
        [cacertfile: path]

      certs = otp_cacerts() ->
        [cacerts: certs]

      true ->
        warn_no_cacerts()
        []
    end
  end

  defp otp_cacerts do
    if System.otp_release() >= "25" do
      # cacerts_get/0 raises if no certs found
      try do
        :public_key.cacerts_get()
      rescue
        _ -> nil
      end
    end
  end

  defp warn_no_cacerts do
    Mix.shell().error("""
    No certificate trust store was found.

    A certificate trust store is required in
    order to download locales for your configuration.
    Since elixir_make could not detect a system
    installed certificate trust store one of the
    following actions may be taken:

    1. Specify the location of a certificate trust store
       by configuring it in environment variable:

         export HEX_CACERTS_PATH="/path/to/cacerts.pem"

    2. Use OTP 25+ on an OS that has built-in certificate
       trust store.
    """)
  end
end
