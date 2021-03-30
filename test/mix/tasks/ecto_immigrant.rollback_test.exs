defmodule Mix.Tasks.EctoImmigrant.RollbackTest do
  use ExUnit.Case

  import Mix.Tasks.EctoImmigrant.Rollback, only: [run: 2]
  import Support.FileHelpers

  @migrations_path Path.join([tmp_path(), inspect(EctoImmigrant.Migrate), "data_migrations"])

  setup do
    File.mkdir_p!(@migrations_path)
    :ok
  end

  defmodule Repo do
    def start_link(_) do
      Process.put(:started, true)

      Task.start_link(fn ->
        Process.flag(:trap_exit, true)

        receive do
          {:EXIT, _, :normal} -> :ok
        end
      end)
    end

    def stop(_pid) do
      :ok
    end

    def __adapter__ do
      EctoImmigrant.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(EctoImmigrant.Migrate)}", otp_app: :ecto_immigrant]
    end
  end

  defmodule StartedRepo do
    def start_link(_) do
      Process.put(:already_started, true)
      {:error, {:already_started, :whatever}}
    end

    def stop(_) do
      raise "should not be called"
    end

    def __adapter__ do
      EctoImmigrant.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(EctoImmigrant.Migrate)}", otp_app: :ecto_immigrant]
    end
  end

  test "runs the migrator with app_repo config" do
    Application.put_env(:ecto_immigrant, :ecto_repos, [Repo])

    run([], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end)

    assert Process.get(:migrated)
    assert Process.get(:started)
  after
    Application.delete_env(:ecto, :ecto_repos)
  end

  test "runs the migrator after starting repo" do
    run(["-r", to_string(Repo)], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end)

    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator with the already started repo" do
    run(["-r", to_string(StartedRepo)], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end)

    assert Process.get(:migrated)
    assert Process.get(:already_started)
  end

  test "runs the migrator with two repos" do
    run(["-r", to_string(Repo), "-r", to_string(StartedRepo)], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end)

    assert Process.get(:migrated)
    assert Process.get(:started)
    assert Process.get(:already_started)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run(["-r", to_string(Repo), "--quiet", "--prefix", "foo"], fn repo, path, direction, opts ->
      assert repo == Repo

      assert path ==
               Path.expand("tmp/#{inspect(EctoImmigrant.Migrate)}/data_migrations", File.cwd!())

      assert direction == :down
      assert opts[:step] == 1
      refute opts[:all]
      refute opts[:to]
      []
    end)

    assert Process.get(:started)
  end

  test "raises when data migrations path does not exist" do
    File.rm_rf!(@migrations_path)

    assert_raise Mix.Error, fn ->
      run(["-r", to_string(Repo)], fn _, _, _, _ -> [] end)
    end

    assert !Process.get(:started)
  end
end
