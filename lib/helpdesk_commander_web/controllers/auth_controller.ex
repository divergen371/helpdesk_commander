defmodule HelpdeskCommanderWeb.AuthController do
  use HelpdeskCommanderWeb, :controller
  import Phoenix.Component, only: [to_form: 2]

  alias HelpdeskCommander.Accounts.Auth

  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params) do
    render(conn, :sign_in, form: to_form(%{}, as: "session"))
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"session" => params}) do
    company_code = Map.get(params, "company_code", "")
    login_or_email = Map.get(params, "login", "")
    password = Map.get(params, "password", "")

    case Auth.authenticate(company_code, login_or_email, password) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> redirect(to: ~p"/tickets")

      {:error, :pending_approval} ->
        conn
        |> put_flash(:error, "承認待ちのためログインできません")
        |> render(:sign_in, form: to_form(params, as: "session"))

      {:error, :email_login_disabled} ->
        conn
        |> put_flash(:error, "メールでのログインは初回のみです。login_idでログインしてください。")
        |> render(:sign_in, form: to_form(params, as: "session"))

      {:error, :invalid_company_code} ->
        conn
        |> put_flash(:error, "会社IDの形式が正しくありません")
        |> render(:sign_in, form: to_form(params, as: "session"))

      {:error, :company_not_found} ->
        conn
        |> put_flash(:error, "会社が見つかりません")
        |> render(:sign_in, form: to_form(params, as: "session"))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "ログインに失敗しました")
        |> render(:sign_in, form: to_form(params, as: "session"))
    end
  end

  @spec new_registration(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new_registration(conn, _params) do
    render(conn, :sign_up, form: to_form(%{}, as: "registration"))
  end

  @spec create_registration(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_registration(conn, %{"registration" => params}) do
    company_code = Map.get(params, "company_code", "")
    email = Map.get(params, "email", "")
    display_name = Map.get(params, "display_name", "")
    password = Map.get(params, "password", "")
    password_confirmation = Map.get(params, "password_confirmation", "")

    case Auth.register_pending_user(company_code, email, password, password_confirmation, display_name) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "登録を受け付けました。管理者の承認をお待ちください。")
        |> redirect(to: ~p"/sign-in")

      {:error, :invalid_company_code} ->
        conn
        |> put_flash(:error, "会社IDの形式が正しくありません")
        |> render(:sign_up, form: to_form(params, as: "registration"))

      {:error, :company_not_found} ->
        conn
        |> put_flash(:error, "会社が見つかりません")
        |> render(:sign_up, form: to_form(params, as: "registration"))

      {:error, :user_not_found} ->
        conn
        |> put_flash(:error, "該当する仮ユーザーが見つかりません")
        |> render(:sign_up, form: to_form(params, as: "registration"))

      {:error, :already_active} ->
        conn
        |> put_flash(:error, "既に登録済みです。ログインしてください。")
        |> redirect(to: ~p"/sign-in")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "登録に失敗しました。入力内容をご確認ください。")
        |> render(:sign_up, form: to_form(params, as: "registration"))
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/sign-in")
  end
end
