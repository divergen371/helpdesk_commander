defmodule HelpdeskCommander.Attachments.Reputation.Provider do
  @moduledoc """
  SHA256 ハッシュのみを外部レピュテーションへ照会するプロバイダ Behaviour（HC-41）。

  ファイル本体やチケット情報は一切受け取らない。
  """

  @type verdict :: :infected | :unknown
  @type result :: {:ok, verdict(), String.t() | nil} | {:error, term()}

  @callback name() :: String.t()
  @callback lookup(sha256 :: String.t(), config :: map()) :: result()
end
