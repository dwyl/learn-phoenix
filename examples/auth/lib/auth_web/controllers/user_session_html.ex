defmodule AuthWeb.UserSessionHTML do
  use AuthWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:auth, Auth.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
