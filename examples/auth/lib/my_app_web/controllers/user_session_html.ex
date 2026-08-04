defmodule MyAppWeb.UserSessionHTML do
  use MyAppWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:my_app, MyApp.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
