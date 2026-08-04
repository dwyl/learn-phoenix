defmodule MyAppWeb.PostLive.Form do
  use MyAppWeb, :live_view

  alias MyApp.Blog
  alias MyApp.Blog.Post

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage post records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:body]} type="textarea" label="Body" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Post</.button>
          <.button navigate={return_path(@current_scope, @return_to, @post)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Post")
    |> assign(:post, post)
    |> assign(:form, to_form(Blog.change_post(socket.assigns.current_scope, post)))
  end

  defp apply_action(socket, :new, _params) do
    post = %Post{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Post")
    |> assign(:post, post)
    |> assign(:form, to_form(Blog.change_post(socket.assigns.current_scope, post)))
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    changeset = Blog.change_post(socket.assigns.current_scope, socket.assigns.post, post_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"post" => post_params}, socket) do
    save_post(socket, socket.assigns.live_action, post_params)
  end

  defp save_post(socket, :edit, post_params) do
    case Blog.update_post(socket.assigns.current_scope, socket.assigns.post, post_params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, post)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_post(socket, :new, post_params) do
    case Blog.create_post(socket.assigns.current_scope, post_params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, post)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _post), do: ~p"/posts"
  defp return_path(_scope, "show", post), do: ~p"/posts/#{post}"
end
