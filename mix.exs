defmodule HelpdeskCommander.MixProject do
  use Mix.Project

  @spec project() :: keyword()
  def project do
    env = mix_env()

    [
      app: :helpdesk_commander,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(env),
      erlc_paths: erlc_paths(env),
      start_permanent: env == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ mix_compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "README.ja.md",
        "QUICKSTART.md",
        "AGENTS.md",
        "docs/REQUIREMENTS.md",
        "docs/STATUS.md",
        "docs/ROADMAP.md",
        "docs/TASKS.md",
        "docs/IMPLEMENTATION_PLAN.md",
        "docs/CODE_QUALITY.md",
        "docs/ELIXIR_UPGRADE.md",
        "docs/DB_SCHEMA.md",
        "docs/ERD.md",
        "docs/SEQUENCE.md",
        "docs/ERROR_HANDLING.md",
        "docs/CI_CD.md",
        "docs/CREDO.md",
        "docs/DIALYZER.md",
        "docs/FORMATTER.md",
        "docs/TESTING.md",
        "docs/BRANCH_STRATEGY.md",
        "docs/DESIGN_API_MIGRATION.md",
        "docs/DESIGN_ASH_REFACTOR.md",
        "docs/DESIGN_DATA_ENCRYPTION.md",
        "docs/DESIGN_PRIORITY_CHECK.md",
        "docs/DESIGN_TICKET_RELATIONS.md",
        "docs/DESIGN_USER_DELETION.md",
        "docs/UNDECIDED_ITEMS.md",
        "docs/Walkthrough.md"
      ],
      groups_for_extras: [
        Guides: [
          "README.md",
          "README.ja.md",
          "QUICKSTART.md",
          "AGENTS.md"
        ],
        "Architecture & Design": [
          ~r/docs\/DESIGN_.*/,
          "docs/ERD.md",
          "docs/DB_SCHEMA.md",
          "docs/SEQUENCE.md",
          "docs/REQUIREMENTS.md"
        ],
        "Tooling & Quality": [
          "docs/CODE_QUALITY.md",
          "docs/ELIXIR_UPGRADE.md",
          "docs/CI_CD.md",
          "docs/CREDO.md",
          "docs/DIALYZER.md",
          "docs/FORMATTER.md",
          "docs/TESTING.md",
          "docs/ERROR_HANDLING.md",
          "docs/BRANCH_STRATEGY.md"
        ],
        Miscellaneous: [
          "docs/STATUS.md",
          "docs/ROADMAP.md",
          "docs/TASKS.md",
          "docs/IMPLEMENTATION_PLAN.md",
          "docs/UNDECIDED_ITEMS.md",
          "docs/Walkthrough.md"
        ]
      ],
      groups_for_modules: [
        "Core Context": [
          ~r/HelpdeskCommander\.Helpdesk.*/,
          ~r/HelpdeskCommander\.Accounts.*/,
          ~r/HelpdeskCommander\.Support.*/
        ],
        "Web Interface": [
          ~r/HelpdeskCommanderWeb.*/
        ],
        Workers: [
          ~r/HelpdeskCommander\.Workers.*/
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  @spec application() :: keyword()
  def application do
    [
      mod: {HelpdeskCommander.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  @spec cli() :: keyword()
  def cli do
    [
      preferred_envs: [
        precommit: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.json": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp erlc_paths(:test), do: ["src", "test/support"]
  defp erlc_paths(_), do: ["src"]

  # Dialyzer configuration
  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:ex_unit, :mix],
      flags: [
        :error_handling,
        :underspecs,
        :unknown,
        :unmatched_returns
      ],
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    env = mix_env()

    [
      {:ash_phoenix, "~> 2.3"},
      {:ash_postgres, "~> 2.15"},
      {:ash_authentication, "~> 4.15"},
      {:picosat_elixir, "~> 0.2.3"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:propcheck, "~> 1.5", only: [:test, :dev]},
      {:stream_data, "~> 1.1"},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: env == :dev},
      {:tailwind, "~> 0.5", runtime: env == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:bcrypt_elixir, "~> 3.0"},
      {:swoosh, "~> 1.29"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:hammer, "~> 7.0"},
      {:plug_attack, "~> 0.4.3"},
      {:remote_ip, "~> 1.2"},
      {:oban, "~> 2.20"},
      {:cachex, "~> 4.1"},
      # Tooling
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:observer_cli, "~> 1.8", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp mix_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      try do
        # credo:disable-for-next-line
        Mix.env()
      rescue
        ArgumentError -> env_from_system()
      end
    else
      env_from_system()
    end
  end

  defp mix_compilers do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :compilers, 0) do
      try do
        Mix.compilers()
      rescue
        ArgumentError -> [:yecc, :leex, :erlang, :elixir, :app]
      end
    else
      [:yecc, :leex, :erlang, :elixir, :app]
    end
  end

  defp env_from_system do
    case System.get_env("MIX_ENV", "dev") do
      "prod" -> :prod
      "test" -> :test
      _ -> :dev
    end
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing", "cmd --cd assets npm install"],
      "assets.build": ["compile", "tailwind helpdesk_commander", "esbuild helpdesk_commander"],
      "assets.deploy": [
        "compile",
        "tailwind helpdesk_commander --minify",
        "esbuild helpdesk_commander --minify",
        "phx.digest"
      ]
    ]
  end
end
