defmodule HelpdeskCommanderWeb.Api.V1.SpecController do
  @moduledoc """
  OpenAPI 3.0 仕様を返す。
  """

  use HelpdeskCommanderWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    json(conn, spec())
  end

  defp spec do
    %{
      openapi: "3.0.3",
      info: %{
        title: "Helpdesk Commander API",
        version: "1.0.0",
        description: "チケット運用のための JSON API。Bearer トークンで認証する。"
      },
      servers: [%{url: "/api/v1"}],
      components: %{
        securitySchemes: %{
          bearerAuth: %{type: :http, scheme: :bearer}
        },
        schemas: %{
          Error: %{
            type: :object,
            properties: %{
              error: %{
                type: :object,
                properties: %{
                  code: %{type: :string},
                  message: %{type: :string},
                  fields: %{type: :object}
                }
              }
            }
          },
          Ticket: %{
            type: :object,
            properties: %{
              public_id: %{type: :string},
              subject: %{type: :string},
              description: %{type: :string, nullable: true},
              type: %{type: :string, enum: ["question", "incident", "request"]},
              status: %{
                type: :string,
                enum: ["new", "triage", "in_progress", "waiting", "resolved", "verified", "closed"]
              },
              priority: %{type: :string, enum: ["p1", "p2", "p3", "p4"]},
              priority_source: %{type: :string, enum: ["auto", "manual"]},
              impact: %{type: :string, nullable: true},
              urgency: %{type: :string, nullable: true},
              visibility_scope: %{type: :string},
              lock_version: %{type: :integer},
              product_id: %{type: :integer},
              requester_id: %{type: :integer},
              assignee_id: %{type: :integer, nullable: true},
              inserted_at: %{type: :string, format: :datetime},
              updated_at: %{type: :string, format: :datetime}
            }
          }
        }
      },
      security: [%{bearerAuth: []}],
      paths: %{
        "/sign-in" => %{
          post: %{
            summary: "サインインしてトークンを取得する",
            security: [],
            requestBody: %{
              required: true,
              content: %{
                "application/json" => %{
                  schema: %{
                    type: :object,
                    required: ["company_code", "login", "password"],
                    properties: %{
                      company_code: %{type: :string, example: "A-000001"},
                      login: %{type: :string},
                      password: %{type: :string}
                    }
                  }
                }
              }
            },
            responses: %{
              "200" => %{description: "トークンとユーザー"},
              "401" => %{"$ref": "#/components/schemas/Error"},
              "403" => %{"$ref": "#/components/schemas/Error"}
            }
          }
        },
        "/me" => %{
          get: %{
            summary: "自分の情報",
            responses: %{"200" => %{description: "ユーザー"}, "401" => %{"$ref": "#/components/schemas/Error"}}
          }
        },
        "/products" => %{
          get: %{
            summary: "製品一覧",
            responses: %{"200" => %{description: "製品一覧"}, "401" => %{"$ref": "#/components/schemas/Error"}}
          }
        },
        "/tickets" => %{
          get: %{
            summary: "チケット一覧",
            parameters: [
              %{name: "q", in: :query, schema: %{type: :string}},
              %{name: "status", in: :query, schema: %{type: :string}},
              %{name: "priority", in: :query, schema: %{type: :string}},
              %{name: "type", in: :query, schema: %{type: :string}},
              %{name: "sort", in: :query, schema: %{type: :string, enum: ["newest", "oldest", "priority", "status"]}},
              %{name: "page", in: :query, schema: %{type: :integer, minimum: 1}}
            ],
            responses: %{"200" => %{description: "チケット一覧"}, "401" => %{"$ref": "#/components/schemas/Error"}}
          },
          post: %{
            summary: "チケットを作成する",
            requestBody: %{
              required: true,
              content: %{
                "application/json" => %{
                  schema: %{
                    type: :object,
                    required: ["subject", "product_id"],
                    properties: %{
                      subject: %{type: :string},
                      description: %{type: :string},
                      type: %{type: :string},
                      priority: %{type: :string},
                      impact: %{type: :string},
                      urgency: %{type: :string},
                      product_id: %{type: :integer},
                      requester_id: %{type: :integer},
                      assignee_id: %{type: :integer}
                    }
                  }
                }
              }
            },
            responses: %{
              "201" => %{description: "作成されたチケット"},
              "401" => %{"$ref": "#/components/schemas/Error"},
              "422" => %{"$ref": "#/components/schemas/Error"}
            }
          }
        },
        "/tickets/{public_id}" => %{
          get: %{
            summary: "チケット詳細",
            parameters: [%{name: "public_id", in: :path, required: true, schema: %{type: :string}}],
            responses: %{
              "200" => %{description: "チケット"},
              "403" => %{"$ref": "#/components/schemas/Error"},
              "404" => %{"$ref": "#/components/schemas/Error"}
            }
          },
          patch: %{
            summary: "チケットを更新する",
            parameters: [%{name: "public_id", in: :path, required: true, schema: %{type: :string}}],
            requestBody: %{
              content: %{
                "application/json" => %{
                  schema: %{
                    type: :object,
                    properties: %{
                      subject: %{type: :string},
                      description: %{type: :string},
                      type: %{type: :string},
                      priority: %{type: :string},
                      impact: %{type: :string},
                      urgency: %{type: :string},
                      assignee_id: %{type: :integer},
                      lock_version: %{type: :integer}
                    }
                  }
                }
              }
            },
            responses: %{
              "200" => %{description: "更新されたチケット"},
              "403" => %{"$ref": "#/components/schemas/Error"},
              "409" => %{"$ref": "#/components/schemas/Error"},
              "422" => %{"$ref": "#/components/schemas/Error"}
            }
          }
        },
        "/tickets/{public_id}/status" => %{
          put: %{
            summary: "ステータスを変更する",
            parameters: [%{name: "public_id", in: :path, required: true, schema: %{type: :string}}],
            requestBody: %{
              required: true,
              content: %{
                "application/json" => %{
                  schema: %{
                    type: :object,
                    required: ["status"],
                    properties: %{status: %{type: :string}}
                  }
                }
              }
            },
            responses: %{
              "200" => %{description: "更新されたチケット"},
              "403" => %{"$ref": "#/components/schemas/Error"},
              "422" => %{"$ref": "#/components/schemas/Error"}
            }
          }
        },
        "/tickets/{public_id}/messages" => %{
          get: %{
            summary: "公開コメント一覧",
            parameters: [
              %{name: "public_id", in: :path, required: true, schema: %{type: :string}},
              %{name: "limit", in: :query, schema: %{type: :integer, maximum: 100}}
            ],
            responses: %{"200" => %{description: "メッセージ一覧"}, "403" => %{"$ref": "#/components/schemas/Error"}}
          }
        }
      }
    }
  end
end
