if Code.ensure_loaded?(:cowboy_websocket) do
  defmodule WebSockAdapter.CowboyAdapter do
    @moduledoc false

    @behaviour :cowboy_websocket

    # Cowboy never actually calls this implementation due to the way that Plug.Cowboy signals
    # upgrades; it's just here to quell compiler warnings
    @impl true
    def init(req, state), do: {:cowboy_websocket, req, state}

    @impl true
    def websocket_init({handler, process_flags, state}) do
      for {key, value} <- process_flags do
        :erlang.process_flag(key, value)
      end

      handler.init(state)
      |> handle_reply(handler)
    end

    @impl true
    def websocket_handle({opcode, payload}, {handler, state}) when opcode in [:text, :binary] do
      handler.handle_in({payload, opcode: opcode}, state)
      |> handle_reply(handler)
    end

    def websocket_handle({opcode, payload}, {handler, state}) when opcode in [:ping, :pong] do
      if function_exported?(handler, :handle_control, 2) do
        handler.handle_control({payload, opcode: opcode}, state)
      else
        {:ok, state}
      end
      |> handle_reply(handler)
    end

    def websocket_handle(opcode, handler_state) when opcode in [:ping, :pong] do
      websocket_handle({opcode, nil}, handler_state)
    end

    def websocket_handle(_other, handler_state) do
      {:ok, handler_state}
    end

    @impl true
    def websocket_info(message, {handler, state}) do
      handler.handle_info(message, state)
      |> handle_reply(handler)
    end

    @impl true
    def terminate({:remote, code, _}, _req, {handler, state})
        when code in 1000..1003 or code in 1005..1011 or code == 1015 do
      if function_exported?(handler, :terminate, 2) do
        handler.terminate(:remote, state)
      end
    end

    def terminate({:remote, :closed}, _req, {handler, state}) do
      if function_exported?(handler, :terminate, 2) do
        handler.terminate(:closed, state)
      end
    end

    def terminate(:stop, _req, {handler, state}) do
      if function_exported?(handler, :terminate, 2) do
        handler.terminate(:normal, state)
      end
    end

    def terminate(reason, _req, {handler, state}) do
      if function_exported?(handler, :terminate, 2) do
        handler.terminate(reason, state)
      end
    end

    # If websocket_init (or the handler's init) raises an error, state may still
    # be the 3-element tuple that we get at initialization time. Since we have
    # not yet initialized the websock at this point, just terminate and let
    # Cowboy do its usual logging
    def terminate(_reason, _req, {_handler, _process_flags, _state}), do: :ok

    defp handle_reply({:ok, state}, handler), do: {:ok, {handler, state}}
    defp handle_reply({:push, data, state}, handler), do: {:reply, data, {handler, state}}

    defp handle_reply({:reply, _status, data, state}, handler),
      do: {:reply, data, {handler, state}}

    defp handle_reply({:stop, {:shutdown, :restart}, state}, handler),
      do: {:reply, {:close, _restart_code = 1012, <<>>}, {handler, state}}

    defp handle_reply({:stop, _reason, state}, handler), do: {:stop, {handler, state}}

    defp handle_reply({:stop, _reason, close_detail, state}, handler),
      do: {:reply, close_frame_for_detail(close_detail), {handler, state}}

    defp handle_reply({:stop, _reason, close_detail, messages, state}, handler),
      do: {:reply, messages ++ [close_frame_for_detail(close_detail)], {handler, state}}

    defp close_frame_for_detail(code) when is_integer(code),
      do: {:close, code, <<>>}

    defp close_frame_for_detail({code, nil}) when is_integer(code),
      do: {:close, code, <<>>}

    defp close_frame_for_detail({code, detail}) when is_integer(code) and is_binary(detail),
      do: {:close, code, detail}
  end
end
