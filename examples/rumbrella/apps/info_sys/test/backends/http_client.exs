defmodule InfoSys.Test.HTTPClient do
  @wolfram_xml File.read!("test/fixtures/wolfram.xml")
  def request(url) do
    url = to_string(url)
    cond do
      String.contains?(url, "1+%2B+1") -> {:ok, {[], [], @wolfram_xml}}
      true -> {:ok, {[], [], "<queryresult></queryresult>"}}
    end
  end
end
