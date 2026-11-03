defmodule HelpdeskCommander.Helpdesk.TicketSimilarity do
  @moduledoc """
  チケットの件名と本文から関連・重複候補を算出する。

  形態素解析や外部モデルを使わず、正規化した文字 2-gram（日本語）と単語
  （英数字）の重み付きコサイン類似度で判定する。件名は本文の 3 倍の重みを持つ。
  決定的で説明しやすく、PII を外部送信しない。将来セマンティックな類似度へ
  差し替える場合も、このモジュールの `suggest/2` の返り値を保てばよい。

  しきい値は既定 0.30。誤検知を避けるため自動リンクはせず、候補提示に留める。
  """

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @default_threshold 0.30
  @default_limit 5
  @max_candidates 200
  @subject_weight 3.0

  @stop_tokens MapSet.new(~w(
    です ます した して から ので こと よう でき ません いる ある なる
    ため もの それ これ どこ なに たい について および または
    the and for with this that from have
  ))

  @doc """
  関連候補を返す。

  `opts`:
  - `:threshold` - 候補に残す最低スコア（既定 0.30）
  - `:limit` - 返す件数（既定 5）
  """
  @spec suggest(Ticket.t(), keyword()) ::
          {:ok, [%{ticket: Ticket.t(), score: float()}]} | {:error, term()}
  def suggest(%Ticket{} = ticket, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    limit = Keyword.get(opts, :limit, @default_limit)

    query =
      Ticket
      |> filter(company_id == ^ticket.company_id and id != ^ticket.id)
      |> sort(inserted_at: :desc)
      |> Ash.Query.limit(@max_candidates)

    with {:ok, candidates} <-
           Ash.read(query, domain: Helpdesk, tenant: ticket.company_id) do
      base = profile(ticket)

      suggestions =
        candidates
        |> Enum.map(fn candidate ->
          %{ticket: candidate, score: similarity(base, profile(candidate))}
        end)
        |> Enum.filter(&(&1.score >= threshold))
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      {:ok, suggestions}
    end
  end

  @doc "2 つのテキストの類似度（0.0〜1.0）。テストと調整用。"
  @spec text_similarity(String.t(), String.t(), String.t(), String.t()) :: float()
  def text_similarity(subject_a, description_a, subject_b, description_b) do
    similarity(
      profile(%Ticket{subject: subject_a, description: description_a}),
      profile(%Ticket{subject: subject_b, description: description_b})
    )
  end

  defp profile(ticket) do
    subject = scale(tokenize(ticket.subject), @subject_weight)
    description = scale(tokenize(ticket.description || ""), 1.0)
    tokens = Map.merge(subject, description, fn _token, a, b -> a + b end)
    %{tokens: tokens, norm: norm(tokens)}
  end

  defp tokenize(nil), do: %{}

  defp tokenize(text) when is_binary(text) do
    text
    |> String.normalize(:nfkc)
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split(" ", trim: true)
    |> Enum.flat_map(&tokens_for/1)
    |> Enum.reject(&MapSet.member?(@stop_tokens, &1))
    |> Enum.frequencies()
    |> Map.new(fn {token, count} -> {token, count * 1.0} end)
  end

  defp tokens_for(token) do
    cond do
      Regex.match?(~r/^[a-z0-9]+$/u, token) ->
        if String.length(token) >= 2, do: ["w:#{token}"], else: []

      String.length(token) == 1 ->
        ["c:#{token}"]

      true ->
        token
        |> String.graphemes()
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(&("b:" <> Enum.join(&1)))
    end
  end

  defp scale(tokens, weight), do: Map.new(tokens, fn {token, count} -> {token, count * weight} end)

  defp norm(tokens) do
    tokens
    |> Map.values()
    |> Enum.reduce(0.0, fn weight, acc -> acc + weight * weight end)
    |> :math.sqrt()
  end

  defp similarity(base, candidate)
       when base.norm == 0.0 or candidate.norm == 0.0,
       do: 0.0

  defp similarity(base, candidate) do
    dot =
      Enum.reduce(base.tokens, 0.0, fn {token, weight}, acc ->
        case Map.get(candidate.tokens, token) do
          nil -> acc
          candidate_weight -> acc + weight * candidate_weight
        end
      end)

    min(1.0, dot / (base.norm * candidate.norm))
  end
end
