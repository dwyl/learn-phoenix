defmodule HelloWeb.UserSessionHTML do
  use HelloWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:hello, Hello.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
