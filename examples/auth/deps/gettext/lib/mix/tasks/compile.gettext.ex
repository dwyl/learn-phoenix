defmodule Mix.Tasks.Compile.Gettext do
  @moduledoc false

  def run(_args) do
    IO.warn("""
    the :gettext compiler is no longer required in your mix.exs.

    Please find the following line in your mix.exs and remove the :gettext entry:

        compilers: [..., :gettext, ...] ++ Mix.compilers(),
    """)

    {:noop, []}
  end
end
