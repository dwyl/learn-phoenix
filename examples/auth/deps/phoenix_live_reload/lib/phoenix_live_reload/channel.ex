defmodule Phoenix.LiveReloader.Channel do
  @moduledoc """
  Phoenix's live-reload channel.
  """
  use Phoenix.Channel
  require Logger

  alias Phoenix.LiveReloader.WebConsoleLogger

  @logs :logs

  def join("phoenix:live_reload", _msg, socket) do
    {:ok, _} = Application.ensure_all_started(:phoenix_live_reload)

    if Process.whereis(:phoenix_live_reload_file_monitor) do
      FileSystem.subscribe(:phoenix_live_reload_file_monitor)

      if web_console_logger_enabled?(socket) do
        WebConsoleLogger.subscribe(@logs)
      end

      config = socket.endpoint.config(:live_reload)

      socket =
        socket
        |> assign(:patterns, config[:patterns] || [])
        |> assign(:debounce, config[:debounce] || 0)
        |> assign(:notify_patterns, config[:notify] || [])

      {:ok, join_info(), socket}
    else
      {:error, %{message: "live reload backend not running"}}
    end
  end

  def handle_info({:file_event, _pid, {path, _event}}, socket) do
    %{
      patterns: patterns,
      debounce: debounce,
      notify_patterns: notify_patterns
    } = socket.assigns

    if matches_any_pattern?(path, patterns) do
      ext = Path.extname(path)

      for {path, ext} <- [{path, ext} | debounce(debounce, [ext], patterns)] do
        asset_type = remove_leading_dot(ext)
        Logger.debug("Live reload: #{Path.relative_to_cwd(path)}")
        push(socket, "assets_change", %{asset_type: asset_type})
      end
    end

    for {topic, patterns} <- notify_patterns do
      if matches_any_pattern?(path, patterns) do
        Phoenix.PubSub.broadcast(
          socket.pubsub_server,
          to_string(topic),
          {:phoenix_live_reload, topic, path}
        )
      end
    end

    {:noreply, socket}
  end

  def handle_info({@logs, %{level: level, msg: msg, file: file, line: line}}, socket) do
    push(socket, "log", %{
      level: to_string(level),
      msg: msg,
      file: file,
      line: line
    })

    {:noreply, socket}
  end

  def handle_in("full_path", %{"rel_path" => rel_path, "app" => app}, socket) do
    case :persistent_term.get(:phoenix_live_reload_deps_paths) do
      %{^app => dep_path} ->
        {:reply, {:ok, %{full_path: Path.join(dep_path, rel_path)}}, socket}

      %{} ->
        {:reply, {:ok, %{full_path: Path.join(File.cwd!(), rel_path)}}, socket}
    end
  end

  defp debounce(0, _exts, _patterns), do: []

  defp debounce(time, exts, patterns) when is_integer(time) and time > 0 do
    Process.send_after(self(), :debounced, time)
    debounce(exts, patterns)
  end

  defp debounce(exts, patterns) do
    receive do
      :debounced ->
        []

      {:file_event, _pid, {path, _event}} ->
        ext = Path.extname(path)

        if matches_any_pattern?(path, patterns) and ext not in exts do
          [{path, ext} | debounce([ext | exts], patterns)]
        else
          debounce(exts, patterns)
        end
    end
  end

  defp matches_any_pattern?(path, patterns) do
    path = to_string(path)

    Enum.any?(patterns, fn pattern ->
      String.match?(path, pattern) and not String.match?(path, ~r{(^|/)_build/})
    end)
  end

  defp remove_leading_dot("." <> rest), do: rest
  defp remove_leading_dot(rest), do: rest

  defp web_console_logger_enabled?(socket) do
    socket.endpoint.config(:live_reload)[:web_console_logger] == true
  end

  defp join_info do
    if url = System.get_env("PLUG_EDITOR") do
      %{editor_url: url}
    else
      %{}
    end
  end
end
