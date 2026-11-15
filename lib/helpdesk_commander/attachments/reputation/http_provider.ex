defmodule HelpdeskCommander.Attachments.Reputation.HttpProvider do
  @moduledoc """
  設定可能な汎用 HTTP/JSON ハッシュ照会プロバイダ（HC-41）。

  外部へ送信するのは 64 文字の SHA256 ハッシュのみ。
  """

  @behaviour HelpdeskCommander.Attachments.Reputation.Provider

  alias HelpdeskCommander.Attachments.Reputation.Provider

  @default_timeout_ms 3_000
  @default_infected_statuses [200]
  @default_unknown_statuses [404]

  @impl Provider
  def name, do: "http"

  @impl Provider
  def lookup(sha256, config) when is_binary(sha256) and is_map(config) do
    normalized = String.downcase(sha256)

    with :ok <- validate_sha256(normalized),
         {:ok, url} <- fetch_url(config) do
      do_request(normalized, url, config)
    end
  end

  def lookup(_sha256, _config), do: {:error, :invalid_arguments}

  defp validate_sha256(sha256) do
    if Regex.match?(~r/^[a-f0-9]{64}$/, sha256) do
      :ok
    else
      {:error, :invalid_sha256}
    end
  end

  defp fetch_url(%{url: url}) when is_binary(url) do
    trimmed = String.trim(url)
    if trimmed == "", do: {:error, :reputation_url_not_configured}, else: {:ok, trimmed}
  end

  defp fetch_url(_config), do: {:error, :reputation_url_not_configured}

  defp do_request(sha256, url_template, config) do
    method = Map.get(config, :method, :get)
    timeout_ms = Map.get(config, :timeout_ms, @default_timeout_ms)
    headers = Map.get(config, :headers, [])
    extra_req_opts = Map.get(config, :req_options, [])

    {url, req_payload} = build_target(method, url_template, sha256)

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(req_payload)
      |> Keyword.merge(extra_req_opts)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} ->
        interpret_response(status, body, config)

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  rescue
    exception ->
      {:error, {:request_exception, Exception.message(exception)}}
  end

  defp build_target(method, url_template, sha256) do
    if String.contains?(url_template, "{sha256}") do
      {String.replace(url_template, "{sha256}", sha256), []}
    else
      case method do
        :post -> {url_template, [json: %{sha256: sha256}]}
        _get -> {url_template, [params: [sha256: sha256]]}
      end
    end
  end

  defp interpret_response(status, body, config) do
    infected_statuses = Map.get(config, :infected_statuses, @default_infected_statuses)
    unknown_statuses = Map.get(config, :unknown_statuses, @default_unknown_statuses)
    verdict_path = Map.get(config, :verdict_path)
    detail_path = Map.get(config, :detail_path)

    cond do
      status in unknown_statuses ->
        {:ok, :unknown, nil}

      status in infected_statuses ->
        interpret_body(status, body, verdict_path, detail_path)

      true ->
        {:error, {:http_status, status}}
    end
  end

  defp interpret_body(_status, body, nil, detail_path) do
    {:ok, :infected, extract_detail(body, detail_path)}
  end

  defp interpret_body(_status, body, [], detail_path) do
    {:ok, :infected, extract_detail(body, detail_path)}
  end

  defp interpret_body(status, body, verdict_path, detail_path) when is_map(body) do
    detail = extract_detail(body, detail_path)

    case get_in_path(body, verdict_path) do
      value when value in [true, "infected", "malicious", "malware"] ->
        {:ok, :infected, detail}

      value when is_integer(value) and value > 0 ->
        {:ok, :infected, detail}

      value when value in [false, nil, 0, "clean", "unknown", "benign", "harmless"] ->
        {:ok, :unknown, detail}

      other ->
        {:error, {:unexpected_verdict, status, other}}
    end
  end

  defp interpret_body(status, _body, _verdict_path, _detail_path) do
    {:error, {:invalid_response_body, status}}
  end

  defp extract_detail(body, path) when is_map(body) and is_list(path) and path != [] do
    case get_in_path(body, path) do
      nil -> nil
      value when is_binary(value) -> String.slice(value, 0, 200)
      value -> value |> inspect() |> String.slice(0, 200)
    end
  end

  defp extract_detail(_body, _path), do: nil

  defp get_in_path(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> get_in_path(value, rest)
      :error -> nil
    end
  end

  defp get_in_path(value, []), do: value
  defp get_in_path(_value, _path), do: nil
end
