defmodule MyAppWeb.ErrorJSONTest do
  use MyAppWeb.ConnCase, async: true

  test "renders 404" do
    assert MyAppWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert MyAppWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
