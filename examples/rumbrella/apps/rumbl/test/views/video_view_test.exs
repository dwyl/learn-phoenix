defmodule Rumbl.VideoViewTest do
  use Rumbl.ConnCase, asnyc: true
  import Phoenix.View

  test "renders index.html", %{conn: conn} do
    videos = [%Rumbl.Video{id: "1", title: "dogs"},
              %Rumbl.Video{id: "2", title: "cats"}]
    content = render_to_string(Rumbl.VideoView, "index.html",
              conn: conn, videos: videos)

    assert String.contains?(content, "Listing videos")
    for video <- videos do
      assert String.contains?(content, video.title)
    end
  end

  test "renders new.html", %{conn: conn} do
    changeset = Rumbl.Video.changeset(%Rumbl.Video{})
    categories = [{"cats", 123}]
    content = render_to_string(Rumbl.VideoView, "new.html",
      conn: conn, changeset: changeset, categories: categories)
    # IO.puts content
    assert String.contains?(content, "New Video")
  end
end
