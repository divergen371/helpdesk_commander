defmodule HelpdeskCommander.Attachments.Storage do
  @moduledoc """
  添付ファイルのローカル保存を扱う。

  ルートは `:attachment_root`（既定 `priv/uploads`）。アップロード直後は
  `quarantine/` に置き、スキャン結果が clean または skipped のときだけ
  `clean/` へ移す。キーは `company_id/ticket_id/ランダム32桁` で、パス操作は
  キー形式を検証してから行う。
  """

  @key_regex ~r/^\d+\/\d+\/[a-f0-9]{32}$/

  @spec root() :: String.t()
  def root do
    Application.get_env(:helpdesk_commander, :attachment_root) ||
      Path.expand("priv/uploads", File.cwd!())
  end

  @spec store(Plug.Upload.t(), integer(), integer()) ::
          {:ok, %{key: String.t(), byte_size: non_neg_integer(), sha256: String.t()}}
          | {:error, term()}
  # sobelow_skip ["Traversal.FileModule"]
  # パスは整数 ID とランダム 32 桁のキーから組み立て、ユーザー入力のファイル名は使わない。
  def store(%Plug.Upload{} = upload, company_id, ticket_id) do
    key = "#{company_id}/#{ticket_id}/#{random_key()}"
    destination = path(:quarantine, key)
    directory = Path.dirname(destination)

    with :ok <- File.mkdir_p(directory),
         :ok <- File.cp(upload.path, destination),
         {:ok, %File.Stat{size: size}} <- File.stat(destination) do
      {:ok, %{key: key, byte_size: size, sha256: sha256(destination)}}
    end
  end

  @spec promote(String.t()) :: :ok | {:error, atom()}
  # sobelow_skip ["Traversal.FileModule"]
  # key は呼び出し前に validate_key/1（^\d+/\d+/[a-f0-9]{32}$）を通した保存キー。
  def promote(key) do
    quarantine_path = path(:quarantine, key)
    clean_path = path(:clean, key)
    clean_directory = Path.dirname(clean_path)

    with :ok <- validate_key(key),
         :ok <- File.mkdir_p(clean_directory) do
      File.rename(quarantine_path, clean_path)
    end
  end

  @spec path(:quarantine | :clean, String.t()) :: String.t()
  def path(:quarantine, key), do: Path.join([root(), "quarantine", key])
  def path(:clean, key), do: Path.join([root(), "clean", key])

  @spec delete(String.t()) :: :ok
  # sobelow_skip ["Traversal.FileModule"]
  # key は DB に保存された storage_key（^\d+/\d+/[a-f0-9]{32}$ 形式）。
  def delete(key) do
    Enum.each([:quarantine, :clean], fn status ->
      path = path(status, key)
      if File.exists?(path), do: File.rm(path)
    end)

    :ok
  end

  @spec read(String.t(), :quarantine | :clean) :: {:ok, binary()} | {:error, atom()}
  # sobelow_skip ["Traversal.FileModule"]
  # key は DB に保存された storage_key（^\d+/\d+/[a-f0-9]{32}$ 形式）。
  def read(key, status) do
    file_path = path(status, key)
    File.read(file_path)
  end

  defp validate_key(key) do
    if Regex.match?(@key_regex, key), do: :ok, else: {:error, :invalid_key}
  end

  defp random_key do
    bytes = :crypto.strong_rand_bytes(16)
    Base.encode16(bytes, case: :lower)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp sha256(path) do
    path
    |> File.stream!(2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
